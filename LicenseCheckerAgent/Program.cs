using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace LicenseCheckerAgent
{
    class Program
    {
        // This will be replaced by the build script
        static string ServerUrl = "http://10.225.0.26:3847";
        static readonly HttpClient httpClient = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        
        static async Task Main(string[] args)
        {
            string machineName = Environment.MachineName;
            string osVersion = Environment.OSVersion.VersionString;
            
            // Allow override from args if needed
            if (args.Length > 0 && args[0].StartsWith("http"))
            {
                ServerUrl = args[0];
            }

            // Create Mutex to prevent multiple instances
            using var mutex = new System.Threading.Mutex(true, "LicenseCheckerAgent_Mutex", out bool createdNew);
            if (!createdNew)
            {
                return; // Already running
            }

            while (true)
            {
                try
                {
                    string pingUrl = $"{ServerUrl}/api/agents/ping?id={Uri.EscapeDataString(machineName)}&os={Uri.EscapeDataString(osVersion)}";
                    var response = await httpClient.GetAsync(pingUrl);
                    if (response.IsSuccessStatusCode)
                    {
                        string json = await response.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        var root = doc.RootElement;
                        
                        if (root.TryGetProperty("command", out JsonElement cmdElem) && cmdElem.ValueKind == JsonValueKind.String)
                        {
                            string cmd = cmdElem.GetString();
                            if (cmd == "SCAN")
                            {
                                await PerformScanAndUpload(machineName);
                            }
                        }
                    }
                }
                catch (Exception)
                {
                    // Server might be offline, ignore and retry later
                }

                await Task.Delay(5000); // Wait 5 seconds before next ping
            }
        }

        static async Task PerformScanAndUpload(string machineName)
        {
            string tempScript = Path.Combine(Path.GetTempPath(), $"scan_{Guid.NewGuid():N}.ps1");
            try
            {
                // Extract embedded script
                var assembly = Assembly.GetExecutingAssembly();
                using (Stream stream = assembly.GetManifestResourceStream("LicenseCheckerAgent.scan.ps1"))
                {
                    if (stream == null) return;
                    using (FileStream fileStream = new FileStream(tempScript, FileMode.Create, FileAccess.Write))
                    {
                        stream.CopyTo(fileStream);
                    }
                }

                // Run PowerShell
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{tempScript}\"",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.UTF8
                };

                using var process = Process.Start(psi);
                string output = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                // Find JSON part in output
                int jsonStart = output.IndexOf('{');
                if (jsonStart != -1)
                {
                    string jsonResult = output.Substring(jsonStart);
                    
                    // Upload
                    var content = new StringContent(jsonResult, Encoding.UTF8, "application/json");
                    string uploadUrl = $"{ServerUrl}/api/scan/upload?id={Uri.EscapeDataString(machineName)}";
                    await httpClient.PostAsync(uploadUrl, content);
                }
            }
            catch (Exception)
            {
                // Error during scan or upload
            }
            finally
            {
                if (File.Exists(tempScript))
                {
                    try { File.Delete(tempScript); } catch { }
                }
            }
        }
    }
}

