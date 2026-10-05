using System;
using System.IO;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Web.Script.Serialization;
using System.Drawing;

// Post-process only the caller-owned intermediate glTF, before KTX2 packing.
class GCTextureConvert {
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
    static string Quote(string value) { return "\"" + value + "\""; }
    static void Run(string executable, string arguments) {
        using (var process = Process.Start(new ProcessStartInfo(executable, arguments) {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true
        })) {
            string errors = process.StandardError.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != 0) throw new Exception(Path.GetFileName(executable) + ": " + errors);
        }
    }
    static byte[] ReadURI(string root, string uri) {
        if (uri.StartsWith("data:", StringComparison.OrdinalIgnoreCase)) {
            int comma = uri.IndexOf(',');
            if (comma < 0 || !uri.Substring(0, comma).EndsWith(";base64")) throw new Exception("Unsupported image data URI.");
            return Convert.FromBase64String(uri.Substring(comma + 1));
        }
        string decoded = Uri.UnescapeDataString(uri);
        string resolved = Path.GetFullPath(Path.Combine(root, decoded));
        if (Path.IsPathRooted(decoded) || !resolved.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            throw new Exception("Texture or buffer is outside the export staging folder.");
        return File.ReadAllBytes(resolved);
    }
    static byte[] ImageBytes(Dictionary<string, object> document, Dictionary<string, object> image, string root) {
        if (image.ContainsKey("uri")) return ReadURI(root, (string)image["uri"]);
        if (!image.ContainsKey("bufferView")) throw new Exception("Image has no URI or buffer view.");
        var views = (IList)document["bufferViews"];
        var view = (Dictionary<string, object>)views[Convert.ToInt32(image["bufferView"])];
        var buffers = (IList)document["buffers"];
        var buffer = (Dictionary<string, object>)buffers[Convert.ToInt32(view["buffer"])];
        byte[] data = ReadURI(root, (string)buffer["uri"]);
        int offset = view.ContainsKey("byteOffset") ? Convert.ToInt32(view["byteOffset"]) : 0;
        int length = Convert.ToInt32(view["byteLength"]);
        if (offset < 0 || length < 0 || offset > data.Length - length) throw new Exception("Invalid image buffer view.");
        byte[] result = new byte[length];
        Buffer.BlockCopy(data, offset, result, 0, length);
        return result;
    }
    static int Main(string[] args) {
        try {
            if (args.Length != 3) throw new Exception("Expected glTF, convert.exe and jpegoptim.exe paths.");
            string gltf = Path.GetFullPath(args[0]);
            string root = Path.GetDirectoryName(gltf) + Path.DirectorySeparatorChar;
            var document = Json.Deserialize<Dictionary<string, object>>(File.ReadAllText(gltf));
            if (!document.ContainsKey("images")) { Console.WriteLine("Converted 0 textures."); return 0; }
            var images = (IList)document["images"];
            string folderName = "jpg_" + Guid.NewGuid().ToString("N");
            string folder = Path.Combine(root, folderName);
            Directory.CreateDirectory(folder);
            for (int index = 0; index < images.Count; index++) {
                var image = (Dictionary<string, object>)images[index];
                string input = Path.Combine(folder, index + ".source");
                string output = Path.Combine(folder, index + ".jpg");
                File.WriteAllBytes(input, ImageBytes(document, image, root));
                // Keep RGB samples: no gamma, ICC or display transform, including normal/data maps.
                // Force 4:4:4 so normal-map channels are not chroma-subsampled.
                Run(args[1], Quote(input + "[0]") + " -alpha off -strip -depth 8 -sampling-factor 1x1 -quality 100 " + Quote(output));
                Run(args[2], "--strip-all --all-progressive -f -o -q -m90 " + Quote(output));
                using (var stream = File.OpenRead(output)) {
                    if (stream.ReadByte() != 255 || stream.ReadByte() != 216) throw new Exception("Conversion did not produce JPEG.");
                }
                using (var bitmap = Image.FromFile(output)) {
                    if (bitmap.Width < 1 || bitmap.Height < 1) throw new Exception("Invalid JPEG dimensions.");
                }
                File.Delete(input);
                image.Remove("bufferView");
                image["uri"] = folderName + "/" + index + ".jpg";
                image["mimeType"] = "image/jpeg";
            }
            // Leave image indices and all material/texture bindings unchanged. Publish only when all succeeded.
            string temporary = Path.Combine(root, folderName + ".gltf.tmp");
            File.WriteAllText(temporary, Json.Serialize(document), new UTF8Encoding(false));
            File.Replace(temporary, gltf, null);
            Console.WriteLine("Converted " + images.Count + " textures to JPG.");
            return 0;
        } catch (Exception error) { Console.Error.WriteLine(error.Message); return 1; }
    }
}
