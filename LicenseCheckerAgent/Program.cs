using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace LicenseCheckerAgent
{
    static class Program
    {
        // This will be replaced by the build script
        static string ServerUrl = "http://10.225.0.26:3847";
        static readonly HttpClient httpClient = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        static NotifyIcon trayIcon;
        static ToolStripMenuItem statusMenuItem;
        static CancellationTokenSource cts = new CancellationTokenSource();

        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            // Allow override from args if needed
            if (args.Length > 0 && args[0].StartsWith("http"))
            {
                ServerUrl = args[0];
            }

            // Create Mutex to prevent multiple instances
            using var mutex = new Mutex(true, "LicenseCheckerAgent_Mutex", out bool createdNew);
            if (!createdNew)
            {
                MessageBox.Show("Agent Ä‘Ã£ Ä‘ang cháº¡y ngáº§m rá»“i!", "License Checker", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return; // Already running
            }

            // Setup Tray Icon
            trayIcon = new NotifyIcon()
            {
                Icon = SystemIcons.Shield, // Use a system shield icon temporarily
                ContextMenuStrip = new ContextMenuStrip(),
                Visible = true,
                Text = "License Checker Agent - Äang khá»Ÿi Ä‘á»™ng..."
            };

            statusMenuItem = new ToolStripMenuItem("Äang cháº¡y ngáº§m...");
            statusMenuItem.Enabled = false;

            var exitMenuItem = new ToolStripMenuItem("ThoÃ¡t");
            exitMenuItem.Click += (s, e) =>
            {
                cts.Cancel();
                trayIcon.Visible = false;
                Application.Exit();
            };

            trayIcon.ContextMenuStrip.Items.Add(statusMenuItem);
            trayIcon.ContextMenuStrip.Items.Add(new ToolStripSeparator());
            trayIcon.ContextMenuStrip.Items.Add(exitMenuItem);

            // Start the background polling task
            Task.Run(() => AgentLoop(cts.Token));

            // Start the WinForms message loop (keeps application open and responsive)
            Application.Run();
        }

        static async Task AgentLoop(CancellationToken token)
        {
            string machineName = Environment.MachineName;
            string osVersion = Environment.OSVersion.VersionString;

            // Update UI from background thread
            UpdateTrayText($"Agent Sáºµn SÃ ng\nIP: {ServerUrl}");

            while (!token.IsCancellationRequested)
            {
                try
                {
                    string pingUrl = $"{ServerUrl}/api/agents/ping?id={Uri.EscapeDataString(machineName)}&os={Uri.EscapeDataString(osVersion)}";
                    var response = await httpClient.GetAsync(pingUrl, token);
                    if (response.IsSuccessStatusCode)
                    {
                        string json = await response.Content.ReadAsStringAsync(token);
                        using var doc = JsonDocument.Parse(json);
                        var root = doc.RootElement;
                        
                        if (root.TryGetProperty("command", out JsonElement cmdElem) && cmdElem.ValueKind == JsonValueKind.String)
                        {
                            string cmd = cmdElem.GetString();
                            if (cmd == "SCAN")
                            {
                                UpdateTrayText("Äang nháº­n lá»‡nh quÃ©t...");
                                await PerformScanAndUpload(machineName, token);
                                UpdateTrayText($"Agent Sáºµn SÃ ng\nIP: {ServerUrl}");
                            }
                        }
                    }
                }
                catch (TaskCanceledException)
                {
                    break;
                }
                catch (Exception)
                {
                    // Server might be offline, ignore and retry later
                }

                try
                {
                    await Task.Delay(5000, token); // Wait 5 seconds before next ping
                }
                catch (TaskCanceledException)
                {
                    break;
                }
            }
        }

        static async Task PerformScanAndUpload(string machineName, CancellationToken token)
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
                        await stream.CopyToAsync(fileStream, token);
                    }
                }

                UpdateTrayText("Äang thá»±c thi quÃ©t (PowerShell)...");

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
                if (process == null) return;
                
                string output = await process.StandardOutput.ReadToEndAsync(token);
                await process.WaitForExitAsync(token);

                UpdateTrayText("Äang gá»­i káº¿t quáº£ lÃªn Server...");

                // Find JSON part in output
                int jsonStart = output.IndexOf('{');
                if (jsonStart != -1)
                {
                    string jsonResult = output.Substring(jsonStart);
                    
                    // Upload
                    var content = new StringContent(jsonResult, Encoding.UTF8, "application/json");
                    string uploadUrl = $"{ServerUrl}/api/scan/upload?id={Uri.EscapeDataString(machineName)}";
                    await httpClient.PostAsync(uploadUrl, content, token);
                    
                    trayIcon.ShowBalloonTip(3000, "License Checker", "ÄÃ£ quÃ©t vÃ  gá»­i káº¿t quáº£ thÃ nh cÃ´ng!", ToolTipIcon.Info);
                }
            }
            catch (TaskCanceledException)
            {
                // exiting
            }
            catch (Exception ex)
            {
                trayIcon.ShowBalloonTip(3000, "Lá»—i QuÃ©t", ex.Message, ToolTipIcon.Error);
            }
            finally
            {
                if (File.Exists(tempScript))
                {
                    try { File.Delete(tempScript); } catch { }
                }
            }
        }

        static void UpdateTrayText(string text)
        {
            if (trayIcon != null)
            {
                // Text limit for NotifyIcon is 63 chars
                string shortText = text.Length > 63 ? text.Substring(0, 60) + "..." : text;
                trayIcon.Text = shortText;
                
                if (statusMenuItem != null)
                {
                    // For the context menu, we can show full text (using first line)
                    string firstLine = text.Split('\n')[0];
                    statusMenuItem.Text = firstLine;
                }
            }
        }
    }
}

