using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Threading;
using System.Web.Script.Serialization;

class GCPreviewServer {
    static JavaScriptSerializer Json { get { return new JavaScriptSerializer(); } }
    static readonly object CaptureLock = new object();
    static string Root, SceneDirectory, ModelName, ViewerName, Token, Origin;
    static Bitmap Capture;
    static string CaptureId;
    static int NextX, NextY, RowHeight;
    static DateTime CaptureActivity;
    const long MaxPixels = 100000000;
    const int TileLimit = 2048;
    static void Main(string[] args) {
        try {
            if (args.Length != 3) throw new ArgumentException("Expected viewer folder, loopback port and context JSON.");
            Root = Path.GetFullPath(args[0]).TrimEnd('\\') + "\\";
            int port = int.Parse(args[1]);
            Dictionary<string,object> context = Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(args[2]));
            SceneDirectory = Convert.ToString(context["sceneDirectory"]);
            ModelName = Convert.ToString(context["modelName"]);
            ViewerName = Convert.ToString(context["viewerName"]);
            Token = Convert.ToString(context["token"]);
            Origin = "http://127.0.0.1:" + port;
            TcpListener listener = new TcpListener(IPAddress.Loopback, port);
            listener.Start();
            using (Timer timer = new Timer(delegate {
                lock (CaptureLock) { if (Capture != null && (DateTime.UtcNow-CaptureActivity).TotalSeconds > 180) ClearCapture(); }
            }, null, 30000, 30000)) {
                while (true) {
                    TcpClient client = listener.AcceptTcpClient();
                    ThreadPool.QueueUserWorkItem(delegate { Handle(client); });
                }
            }
        } catch (Exception error) { Console.Error.WriteLine(error.Message); Environment.ExitCode = 1; }
    }
    static string Line(Stream stream) {
        MemoryStream bytes = new MemoryStream();
        int value;
        while ((value = stream.ReadByte()) >= 0) {
            if (value == 10) return Encoding.ASCII.GetString(bytes.ToArray()).TrimEnd('\r');
            if (bytes.Length >= 8192) throw new IOException("HTTP header too long.");
            bytes.WriteByte((byte)value);
        }
        throw new IOException("Connection closed.");
    }
    static void Handle(TcpClient client) {
        using(client) {
            NetworkStream stream = client.GetStream();
            stream.ReadTimeout = 30000; stream.WriteTimeout = 30000;
            try {
                string[] request = Line(stream).Split(' ');
                if(request.Length != 3) throw new IOException("Invalid request.");
                var headers = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                for(int index=0; index<64; index++) {
                    string line = Line(stream);
                    if(line.Length == 0) break;
                    int colon = line.IndexOf(':');
                    if(colon <= 0) throw new IOException("Invalid header.");
                    headers[line.Substring(0,colon)] = line.Substring(colon+1).Trim();
                    if(index==63) throw new IOException("Too many headers.");
                }
                string host;
                if(!headers.TryGetValue("Host",out host) || "http://"+host != Origin) { SendJson(stream,403,new {error="Invalid local host."}); return; }
                string path = Uri.UnescapeDataString(request[1].Split('?')[0]);
                if(path.StartsWith("/gc-screenshot/",StringComparison.Ordinal)) {
                    string auth, requestOrigin;
                    if(!headers.TryGetValue("X-GC-Token",out auth) || auth != Token ||
                       (headers.TryGetValue("Origin",out requestOrigin) && requestOrigin != Origin)) {
                        SendJson(stream,403,new {error="Reopen Preview from the converter."}); return;
                    }
                    if(request[0]=="GET" && path=="/gc-screenshot/config") {
                        SendJson(stream,200,new { canSave=SceneDirectory.Length>0 && Directory.Exists(SceneDirectory), model=ModelName, viewer=ViewerName, maxPixels=MaxPixels, tileLimit=TileLimit }); return;
                    }
                    if(request[0]!="POST") { SendJson(stream,405,new {error="POST required."}); return; }
                    string lengthText;
                    long length;
                    if(!headers.TryGetValue("Content-Length",out lengthText) || !long.TryParse(lengthText,out length) || length<0 || length>32*1024*1024) throw new IOException("Invalid upload size.");
                    byte[] body = new byte[(int)length];
                    int received=0;
                    while(received<body.Length) { int count=stream.Read(body,received,body.Length-received); if(count==0) throw new IOException("Incomplete upload."); received+=count; }
                    lock(CaptureLock) { Screenshot(stream,path,headers,body); }
                    return;
                }
                if(request[0]!="GET" && request[0]!="HEAD") { SendJson(stream,405,new {error="GET required."}); return; }
                if(path=="/viewer-ready.txt") { Send(stream,200,"text/plain",Encoding.UTF8.GetBytes(Token),request[0]=="HEAD"); return; }
                string filePath = path=="/gc-screenshot.js" ? Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"GC-Preview-Screenshot.js") :
                    Path.GetFullPath(Path.Combine(Root,path.TrimStart('/').Replace('/','\\')));
                if(path!="/gc-screenshot.js" && (!filePath.StartsWith(Root,StringComparison.OrdinalIgnoreCase) || path.Contains("/.gc-"))) { SendJson(stream,404,new {error="Not found."}); return; }
                if(path=="/") filePath=Path.Combine(Root,"index.html");
                if(!File.Exists(filePath)) { SendJson(stream,404,new {error="Not found."}); return; }
                if(path=="/" || path=="/index.html") {
                    string html=File.ReadAllText(filePath);
                    html=html.Replace("</body>","<script src=\"/gc-screenshot.js\"></script></body>");
                    Send(stream,200,"text/html; charset=utf-8",Encoding.UTF8.GetBytes(html),request[0]=="HEAD"); return;
                }
                using(FileStream file = new FileStream(filePath,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)) {
                    Header(stream,200,Mime(Path.GetExtension(filePath)),file.Length);
                    if(request[0]!="HEAD") file.CopyTo(stream);
                }
            } catch(Exception error) {
                try { SendJson(stream,400,new {error=error.Message}); } catch {}
            }
        }
    }
    static void Screenshot(Stream stream,string path,Dictionary<string,string> headers,byte[] body) {
        CaptureActivity=DateTime.UtcNow;
        if(path=="/gc-screenshot/begin") {
            if(SceneDirectory.Length==0 || !Directory.Exists(SceneDirectory)) throw new IOException("Save the 3ds Max scene, then reopen Preview.");
            if(Capture!=null) throw new IOException("Another screenshot is being saved. Wait or cancel it.");
            var data=Json.Deserialize<Dictionary<string,int>>(Encoding.UTF8.GetString(body));
            int width=data["width"], height=data["height"];
            if(width<1 || height<1 || width>20000 || height>20000 || (long)width*height>MaxPixels) throw new IOException("Screenshot limit: 20000 pixels per side and 100 megapixels.");
            Capture=new Bitmap(width,height,PixelFormat.Format32bppArgb);
            CaptureId=Guid.NewGuid().ToString("N"); NextX=0; NextY=0; RowHeight=0;
            SendJson(stream,200,new {id=CaptureId}); return;
        }
        string id;
        if(Capture==null || !headers.TryGetValue("X-GC-Capture",out id) || id!=CaptureId) throw new IOException("Screenshot session expired. Try again.");
        if(path=="/gc-screenshot/cancel") { ClearCapture(); SendJson(stream,200,new {ok=true}); return; }
        if(path=="/gc-screenshot/tile") {
            int x=int.Parse(headers["X-GC-X"]), y=int.Parse(headers["X-GC-Y"]);
            if(body.Length<8 || body[0]!=137 || body[1]!=80 || body[2]!=78 || body[3]!=71) throw new IOException("PNG tile required.");
            using(var memory=new MemoryStream(body)) using(var tile=Image.FromStream(memory,true,true)) {
                if(x!=NextX || y!=NextY || tile.Width<1 || tile.Height<1 || tile.Width>TileLimit || tile.Height>TileLimit ||
                   x+tile.Width>Capture.Width || y+tile.Height>Capture.Height ||
                   (NextX>0 && tile.Height!=RowHeight)) throw new IOException("Invalid screenshot tile order or dimensions.");
                using(Graphics graphics=Graphics.FromImage(Capture)) {
                    graphics.CompositingMode=System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                    graphics.DrawImageUnscaled(tile,x,y);
                }
                RowHeight=tile.Height; NextX+=tile.Width;
                if(NextX==Capture.Width) { NextX=0; NextY+=RowHeight; }
            }
            SendJson(stream,200,new {ok=true}); return;
        }
        if(path=="/gc-screenshot/finish") {
            if(NextX!=0 || NextY!=Capture.Height) throw new IOException("Screenshot is incomplete.");
            string stem=SafeName(ModelName);
            string filePath=Path.Combine(SceneDirectory,stem+".png");
            string temporary=Path.Combine(SceneDirectory,".gc-shot-"+CaptureId+".tmp");
            try {
                using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)) Capture.Save(output,ImageFormat.Png);
                if(File.Exists(filePath)) File.Replace(temporary,filePath,null);
                else File.Move(temporary,filePath);
                SendJson(stream,200,new {path=filePath,width=Capture.Width,height=Capture.Height});
            } finally { ClearCapture(); if(File.Exists(temporary)) File.Delete(temporary); }
            return;
        }
        throw new IOException("Unknown screenshot operation.");
    }
    static void ClearCapture() { if(Capture!=null) Capture.Dispose(); Capture=null; CaptureId=null; }
    static string SafeName(string name) {
        foreach(char value in Path.GetInvalidFileNameChars()) name=name.Replace(value,'_');
        name=name.Trim().TrimEnd('.');
        return name.Length==0 ? "LOD" : name.Substring(0,Math.Min(name.Length,100));
    }
    static string Mime(string extension) {
        switch(extension.ToLowerInvariant()) {
            case ".html": return "text/html; charset=utf-8"; case ".js": return "application/javascript";
            case ".css": return "text/css"; case ".json": return "application/json"; case ".wasm": return "application/wasm";
            case ".png": return "image/png"; case ".jpg": case ".jpeg": return "image/jpeg"; case ".svg": return "image/svg+xml";
            case ".hdr": return "image/vnd.radiance"; case ".glb": return "model/gltf-binary"; case ".gltf": return "model/gltf+json";
            default: return "application/octet-stream";
        }
    }
    static void SendJson(Stream stream,int status,object value) { Send(stream,status,"application/json",Encoding.UTF8.GetBytes(Json.Serialize(value)),false); }
    static void Send(Stream stream,int status,string type,byte[] body,bool head) { Header(stream,status,type,body.Length); if(!head) stream.Write(body,0,body.Length); }
    static void Header(Stream stream,int status,string type,long length) {
        string text="HTTP/1.1 "+status+" "+(status==200?"OK":"Error")+"\r\nContent-Type: "+type+"\r\nContent-Length: "+length+
            "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n";
        byte[] bytes=Encoding.ASCII.GetBytes(text); stream.Write(bytes,0,bytes.Length);
    }
}