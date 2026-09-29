using System;
using System.IO;
using System.Text;
using System.Net;
using System.Diagnostics;
using System.Collections;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Text.RegularExpressions;

// Local reporting adapter for the unmodified Khronos glTF Validator CLI.
class GCGLBValidation {
    // Official Lucide circle-check, circle-x and circle-alert SVGs: https://lucide.dev
    const string LucideLicense = "<!-- Lucide Icons: ISC License. Copyright (c) 2026 Lucide Icons and Contributors.\nPermission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.\nTHE SOFTWARE IS PROVIDED AS IS AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE. -->";
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 64 * 1024 * 1024 };
    static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
    const string ReportCss = @"
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f5f7f8;color:#202b32;font:14px 'Segoe UI',Arial,sans-serif;line-height:1.55;padding:42px 28px}main{max-width:1120px;margin:auto}
.page-header{display:flex;align-items:center;justify-content:space-between;gap:20px;margin-bottom:28px}.eyebrow{font-size:11px;font-weight:700;letter-spacing:.14em;color:#75818b}h1{font-size:27px;letter-spacing:-.7px;margin:5px 0 0;font-weight:650}.header-link{padding:10px 18px;background:white;border:1px solid #e1e7e9;border-radius:9px;color:#32434b;text-decoration:none;font-weight:600}
.hero{display:flex;align-items:center;gap:24px;padding:34px 38px;border-radius:16px;position:relative;overflow:hidden}.hero.success{background:linear-gradient(115deg,#123e35,#17745e);color:#fff}.hero.error{background:linear-gradient(115deg,#672f3b,#a93f52);color:#fff}.hero.incomplete{background:linear-gradient(115deg,#665124,#94753a);color:#fff}.hero svg{width:70px;height:70px;padding:12px;flex-shrink:0;background:#ffffff18;border:1px solid #ffffff28;border-radius:20px}.hero h2{font-size:34px;letter-spacing:.035em;margin:0 0 4px;line-height:1.2;font-weight:700}.hero p{margin:0;color:#fff;font-size:15px}.hero .subline{font-size:12px;color:#ffffffb8;margin-top:10px}
.metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin:22px 0 34px}.metric{background:white;border:1px solid #e7ecee;border-radius:13px;padding:22px 24px;box-shadow:0 3px 9px #20332903}.metric strong{display:block;font-size:31px;letter-spacing:-1px;line-height:1.2;font-weight:650;margin-bottom:8px}.metric span{font-size:12px;color:#7a858f}.good{color:#168565}.bad{color:#ce4358}.warning{color:#b4822d}.muted{color:#7b8790;font-weight:400}
.section-title{font-size:18px;letter-spacing:-.25px;margin:0 0 14px;font-weight:650}.section-title .muted{font-size:12px;margin-left:9px}.card{background:#fff;border:1px solid #e5eaed;border-radius:12px;margin:10px 0;box-shadow:0 3px 9px #20332903;overflow:hidden}.card>summary{display:flex;align-items:center;gap:14px;padding:20px 22px;list-style:none;cursor:pointer;transition:background .15s}.card>summary::-webkit-details-marker{display:none}.card>summary:hover{background:#f8fbfa}.card>summary:after{content:'\203A';font-size:23px;color:#8c979d;margin-left:6px}.card[open]>summary:after{transform:rotate(90deg)}.card[open]>summary{border-bottom:1px solid #edf0f2}.file-name{font-size:14px;font-weight:650;overflow-wrap:anywhere;flex:1}.status-badge{padding:4px 10px;font-size:11px;border-radius:6px;font-weight:700;white-space:nowrap}.status-badge.good{background:#e8f6ef}.status-badge.bad{background:#ffedf0}.status-badge.muted{background:#f0f3f5}.summary-counts{font-size:12px;color:#7b8790;white-space:nowrap}.card>p,.card>.counts,.card>.notice,.card>.stats,.card>details{margin:18px 22px}.counts{color:#63717c;font-size:13px}p{color:#7a858f;font-size:12px}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.stats span{font-size:12px;color:#7a858f;background:#f7f9fa;border:1px solid #edf1f2;border-radius:9px;padding:14px 16px}.stats strong{display:block;color:#263a43;font-size:22px;font-weight:600;margin-top:4px}.notice{border:1px solid #efdfb9;border-radius:8px;padding:12px 15px;background:#fffbf2;font-size:12px;color:#8c703c}.notice strong{display:block;margin-bottom:3px}
details>summary{cursor:pointer;font-weight:600}summary:focus-visible,a:focus-visible{outline:3px solid #57bba2;outline-offset:3px}details details{border:1px solid #e7edef;border-radius:8px;padding:12px 15px;overflow:auto}table{width:100%;border-collapse:collapse;margin-top:12px;font-size:12px}th,td{text-align:left;padding:12px;border-bottom:1px solid #edf1f3;vertical-align:top;overflow-wrap:anywhere}th{font-size:10px;text-transform:uppercase;letter-spacing:.07em;color:#89959c;background:#f7f9fa}code{font-size:11px;color:#61717e}a{color:#14816b;text-decoration:none}a:hover{text-decoration:underline}.export-log{margin-top:26px;border-top:1px solid #e0e7ea;padding-top:20px;color:#7a858f;font-size:12px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#fff;border:1px solid #e5eaed;padding:18px;border-radius:9px;font-size:12px}.report-footer{margin-top:28px;color:#98a2a9;font-size:11px}
@media(max-width:700px){body{padding:24px 14px}h1{font-size:22px}.page-header{align-items:flex-start}.header-link{display:none}.hero{padding:25px 22px;gap:16px}.hero h2{font-size:26px}.hero svg{width:54px;height:54px;padding:9px;border-radius:15px}.metrics{grid-template-columns:repeat(2,1fr);gap:10px}.metric{padding:17px}.metric strong{font-size:27px}.card>summary{padding:16px;gap:9px;flex-wrap:wrap}.summary-counts{width:100%;order:3}.stats{grid-template-columns:repeat(2,1fr)}.section-title .muted{display:block;margin-left:0;margin-top:4px}}
";
    static object Get(Dictionary<string, object> data, string key) { object item; return data.TryGetValue(key, out item) ? item : null; }
    static string Html(object item) { return WebUtility.HtmlEncode(Convert.ToString(item)); }
    static string Quote(string item) { if (item.Contains("\"")) throw new ArgumentException("Invalid path."); return "\"" + item + "\""; }
    static int Count(Dictionary<string, object> data, string key) {
        object item = Get(data, key);
        if (item == null) throw new InvalidDataException("Incomplete validator report: " + key);
        int count = Convert.ToInt32(item);
        if (count < 0) throw new InvalidDataException("Invalid validator count.");
        return count;
    }
    static void Main(string[] args) {
        try {
            if (args.Length == 3 && args[0] == "validate") Validate(Path.GetFullPath(args[1]), Path.GetFullPath(args[2]));
            else if (args.Length == 2 && args[0] == "report") Report(Path.GetFullPath(args[1]));
            else if (args.Length == 2 && args[0] == "clean") CleanReports(Path.GetFullPath(args[1]));
            else throw new ArgumentException("Expected validate <GLB> <report folder>, report <report folder>, or clean <validation folder>.");
        } catch (Exception error) { Console.Error.WriteLine(error.Message); Environment.ExitCode = 1; }
    }
    static void CleanReports(string folder) {
        folder = folder.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (!string.Equals(Path.GetFileName(folder), "validation", StringComparison.OrdinalIgnoreCase))
            throw new IOException("Cleanup requires the validation folder.");
        if (!Directory.Exists(folder)) return;
        // Never traverse junctions or delete unrelated files placed beside our reports.
        for (var ancestor = new DirectoryInfo(folder); ancestor != null; ancestor = ancestor.Parent)
            if ((ancestor.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Validation cleanup does not follow directory links.");
        foreach (string candidate in Directory.GetDirectories(folder)) {
            string resolved = Path.GetFullPath(candidate);
            if (!string.Equals(Path.GetDirectoryName(resolved), folder, StringComparison.OrdinalIgnoreCase)) throw new IOException("Report folder escaped cleanup root.");
            string leaf = Path.GetFileName(resolved);
            if (!Regex.IsMatch(leaf, @"^(?:[0-9]{8}-[0-9]{6}-)?[a-f0-9]{32}$")) continue;
            if ((File.GetAttributes(resolved) & FileAttributes.ReparsePoint) != 0) continue;
            string manifest = Path.Combine(resolved, "files.txt");
            if (!File.Exists(manifest) || (File.GetAttributes(manifest) & FileAttributes.ReparsePoint) != 0 || Directory.GetDirectories(resolved).Length != 0) continue;
            var ownedNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "files.txt", "batch-summary.txt", "index.html" };
            bool safe = true;
            foreach (string filename in File.ReadAllLines(manifest)) {
                if (filename.Length == 0) continue;
                if (Path.GetFileName(filename) != filename || !filename.EndsWith(".glb", StringComparison.OrdinalIgnoreCase)) { safe = false; break; }
                foreach (string suffix in new[] { ".result.json", ".report.json", ".summary.txt", ".validator.log" }) ownedNames.Add(filename + suffix);
            }
            foreach (string reportFile in Directory.GetFiles(resolved))
                if (!ownedNames.Contains(Path.GetFileName(reportFile)) || (File.GetAttributes(reportFile) & FileAttributes.ReparsePoint) != 0) safe = false;
            if (!safe) continue;
            foreach (string reportFile in Directory.GetFiles(resolved)) File.Delete(reportFile);
            Directory.Delete(resolved, false);
        }
    }
    static void Validate(string input, string folder) {
        Directory.CreateDirectory(folder);
        string filename = Path.GetFileName(input), prefix = Path.Combine(folder, filename);
        var record = new Dictionary<string, object> { { "filename", filename }, { "validated", false } };
        try {
            string executable = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "gltf_validator.exe");
            var start = new ProcessStartInfo(executable, "-o -t " + Quote(input)) {
                UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            string reportContent, logContent; int exitCode;
            using (var process = Process.Start(start)) {
                var output = process.StandardOutput.ReadToEndAsync();
                var errors = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(120000)) { process.Kill(); process.WaitForExit(); throw new IOException("Validation timed out."); }
                reportContent = output.Result; logContent = errors.Result; exitCode = process.ExitCode;
            }
            File.WriteAllText(prefix + ".validator.log", logContent, Utf8);
            var report = Json.DeserializeObject(reportContent) as Dictionary<string, object>;
            if (report == null || Get(report, "validatorVersion") == null) throw new InvalidDataException("Validator returned no valid report.");
            var issues = Get(report, "issues") as Dictionary<string, object>;
            if (issues == null) throw new InvalidDataException("Validator report has no issue counts.");
            int errorCount = Count(issues, "numErrors"), warningCount = Count(issues, "numWarnings");
            if (exitCode != 0 && errorCount == 0) throw new IOException("Validator process failed without reporting validation errors.");
            // Reports survive cleanup of the temporary packed GLB.
            report["uri"] = filename;
            File.WriteAllText(prefix + ".report.json", Json.Serialize(report), Utf8);
            File.WriteAllText(prefix + ".summary.txt", errorCount + "\n" + warningCount, Utf8);
            record["validated"] = true; record["report"] = report;
            record["bytes"] = new FileInfo(input).Length;
        } catch (Exception error) {
            record["failure"] = error.Message;
            throw;
        } finally { File.WriteAllText(prefix + ".result.json", Json.Serialize(record), Utf8); }
    }
    static void Report(string folder) {
        string[] filenames = Array.FindAll(File.ReadAllLines(Path.Combine(folder, "files.txt")), item => item.Length > 0);
        int totalErrors = 0, totalWarnings = 0, totalInfos = 0, checkedFiles = 0, failedFiles = 0;
        foreach (string filename in filenames) {
            if (Path.GetFileName(filename) != filename) throw new InvalidDataException("Invalid report filename.");
            string recordPath = Path.Combine(folder, filename + ".result.json");
            if (!File.Exists(recordPath)) continue;
            var record = (Dictionary<string, object>)Json.DeserializeObject(File.ReadAllText(recordPath));
            if (!Convert.ToBoolean(Get(record, "validated"))) { failedFiles++; continue; }
            var report = (Dictionary<string, object>)Get(record, "report");
            var issues = (Dictionary<string, object>)Get(report, "issues");
            checkedFiles++;
            totalErrors += Count(issues, "numErrors"); totalWarnings += Count(issues, "numWarnings"); totalInfos += Count(issues, "numInfos");
        }
        bool hasErrors = totalErrors > 0 || failedFiles > 0;
        bool isComplete = filenames.Length > 0 && checkedFiles == filenames.Length;
        string state = hasErrors ? "error" : (isComplete ? "success" : "incomplete");
        string headline = hasErrors ? "ERRORS FOUND" : (isComplete ? "SUCCESS" : "INCOMPLETE");
        string explanation = hasErrors ? "Review the highlighted files and their validation logs below." : (isComplete ? "Validation completed. No errors detected." : "Some files have not been validated. Review the export log below.");
        var body = new StringBuilder();
        body.Append("<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Khronos GLB Validation</title><style>" + ReportCss + "</style><main><header class='page-header'><div><span class='eyebrow'>EXPORT REPORT</span><h1>Khronos GLB Validation</h1></div><a class='header-link' href='#files'>View files</a></header>");
        body.Append(LucideLicense);
        string symbol = state == "success" ? "<path d='m16 9-5.5 5.5L8 12'/>" : (state == "error" ? "<path d='m15 9-6 6'/><path d='m9 9 6 6'/>" : "<line x1='12' x2='12' y1='8' y2='12'/><line x1='12' x2='12.01' y1='16' y2='16'/>");
        body.Append("<section class='hero " + state + "' role='status'><svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='12' cy='12' r='10'/>" + symbol + "</svg><div><h2>" + headline + "</h2><p>" + explanation + "</p><p class='subline'>" + checkedFiles + " of " + filenames.Length + " files validated.</p></div></section>");
        body.Append("<section class='metrics'><div class='metric'><strong>" + checkedFiles + " / " + filenames.Length + "</strong><span>Files validated</span></div><div class='metric'><strong class='" + (hasErrors ? "bad" : "good") + "'>" + totalErrors + "</strong><span>Errors" + (failedFiles > 0 ? " · " + failedFiles + " failed checks" : "") + "</span></div><div class='metric'><strong class='warning'>" + totalWarnings + "</strong><span>Warnings</span></div><div class='metric'><strong>" + totalInfos + "</strong><span>Information</span></div></section><h2 id='files' class='section-title'>Files <span class='muted'>· click to view details</span></h2>");
        foreach (string filename in filenames) {
            if (filename.Length == 0) continue;
            if (Path.GetFileName(filename) != filename) throw new InvalidDataException("Invalid report filename.");
            string recordPath = Path.Combine(folder, filename + ".result.json");
            body.Append("<details class='card'><summary><span class='file-name'>" + Html(filename) + "</span>");
            if (!File.Exists(recordPath)) { body.Append("<span class='status-badge muted'>Not validated</span></summary><p>Export stopped before this file could be validated.</p></details>"); continue; }
            var record = (Dictionary<string, object>)Json.DeserializeObject(File.ReadAllText(recordPath));
            if (!Convert.ToBoolean(Get(record, "validated"))) { body.Append("<span class='status-badge bad'>Validation failed</span></summary><p>" + Html(Get(record, "failure")) + "</p></details>"); continue; }
            var report = (Dictionary<string, object>)Get(record, "report");
            var issues = (Dictionary<string, object>)Get(report, "issues");
            int errors = Count(issues, "numErrors"), warnings = Count(issues, "numWarnings");
            body.Append("<span class='summary-counts'>" + errors + " errors · " + warnings + " warnings</span><span class='status-badge " + (errors == 0 ? "good'>Passed" : "bad'>Errors found") + "</span>");
            body.Append("</summary><div class='counts'>Errors: " + errors + " · Warnings: " + warnings + " · Information: " + Count(issues, "numInfos") + " · Hints: " + Count(issues, "numHints") + "</div>");
            body.Append("<p>Validator " + Html(Get(report, "validatorVersion")) + " · " + Html(Get(report, "validatedAt")) + " · " + (Convert.ToInt64(Get(record, "bytes")) / 1048576.0).ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + " MB</p>");
            var messages = Get(issues, "messages") as IEnumerable;
            var unsupported = new List<string>();
            if (messages != null) foreach (Dictionary<string, object> message in messages) if (Convert.ToString(Get(message, "code")) == "UNSUPPORTED_EXTENSION") unsupported.Add(Convert.ToString(Get(message, "message")));
            foreach (string limitation in unsupported) body.Append("<div class='notice'><strong>Validation limitation</strong><br>" + Html(limitation) + "</div>");
            var info = Get(report, "info") as Dictionary<string, object>;
            if (info != null) {
                body.Append("<div class='stats'>");
                string[] keys = { "materialCount", "totalVertexCount", "totalTriangleCount", "drawCallCount", "maxUVs", "animationCount" };
                string[] labels = { "Materials", "Vertices", "Triangles", "Draw calls", "UV sets", "Animations" };
                for (int i = 0; i < keys.Length; i++) if (Get(info, keys[i]) != null) body.Append("<span>" + labels[i] + ": <strong>" + Html(Get(info, keys[i])) + "</strong></span>");
                body.Append("</div>");
            }
            if (Convert.ToBoolean(Get(issues, "truncated"))) body.Append("<p class='warning'>The validator truncated the message list. Counts may exceed the messages shown.</p>");
            if (messages != null) {
                body.Append("<details><summary>Messages</summary><table><thead><tr><th>Level</th><th>Issue</th><th>Location</th></tr></thead><tbody>");
                string[] severityNames = { "Error", "Warning", "Information", "Hint" };
                foreach (Dictionary<string, object> message in messages) {
                    int severity = Convert.ToInt32(Get(message, "severity"));
                    body.Append("<tr><td>" + Html(severity >= 0 && severity < severityNames.Length ? severityNames[severity] : "Unknown") + "</td><td><code>" + Html(Get(message, "code")) + "</code><br>" + Html(Get(message, "message")) + "</td><td><code>" + Html(Get(message, "pointer") ?? Get(message, "offset")) + "</code></td></tr>");
                }
                body.Append("</tbody></table></details>");
            }
            body.Append("<p><a href='" + Html(Uri.EscapeDataString(filename + ".report.json")) + "'>Full JSON report</a></p></details>");
        }
        string batchSummary = Path.Combine(folder, "batch-summary.txt");
        if (File.Exists(batchSummary)) body.Append("<details class='export-log'><summary>Export log</summary><pre>" + Html(File.ReadAllText(batchSummary)) + "</pre></details>");
        body.Append("</main></html>");
        File.WriteAllText(Path.Combine(folder, "index.html"), body.ToString(), Utf8);
    }
}
