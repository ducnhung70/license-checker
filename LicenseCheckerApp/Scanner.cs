using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace LicenseChecker;

public class Scanner
{
    static readonly string[] CrackPatterns = { "KMSPico","KMSAuto","KMS Tools","KMS Activator","Re-Loader","ReLoader","Microsoft Toolkit","AAct","KMSCleaner","RemoveWAT","Windows Loader","Daz Loader","HWIDGEN","HWIDGen","Mini-KMS","AutoKMS","Ratiborus","AMTEmu","AMT Emulator","Adobe Zii","GenP","CCMaker","Xforce","X-Force","Universal Adobe Patcher" };
    static readonly string[] KnownFree = { "Firefox","Chrome","Chromium","VLC","GIMP","Audacity","7-Zip","Visual Studio Code","VS Code","Git","Python","Node","Java","OpenJDK","LibreOffice","FileZilla","PuTTY","WinSCP","OBS Studio","Blender","Inkscape","KeePass","Telegram","Discord","Slack","Zoom","Steam","Epic Games","PowerShell","Redistributable","Runtime","SDK","Windows Terminal","ShareX","qBittorrent","HandBrake","Krita","Thunderbird","Brave","Vivaldi","Opera","Edge",".NET","Visual C" };
    static readonly string[] KnownCommercial = { "Microsoft Office","Microsoft 365","Adobe Photoshop","Adobe Illustrator","Adobe Premiere","Adobe Creative","Adobe Acrobat Pro","AutoCAD","CorelDRAW","WinRAR","Internet Download Manager","Sublime Text","Total Commander","Camtasia","Snagit","MATLAB","Norton","Kaspersky","Bitdefender","ESET","Avast Premium","VMware Workstation","Navicat","DataGrip","IntelliJ IDEA Ultimate","PhpStorm","WebStorm","PyCharm Professional","Rider","ReSharper","SQL Server","Visio","Project Professional" };
    static readonly string[] CommercialPubs = { "Microsoft","Adobe","Autodesk","VMware","JetBrains","Telerik","DevExpress" };
    static readonly string[] BlockedDomains = { "activation.sls.microsoft.com","validation.sls.microsoft.com","genuine.microsoft.com","activate.adobe.com","practivate.adobe.com","lmlicenses.wip4.adobe.com","lm.licenses.adobe.com","activate.wip3.adobe.com","ereg.adobe.com","adobeereg.com","account.jetbrains.com" };
    static readonly string[] TaskPatterns = { "KMS","AutoKMS","KMSAuto","Activat","ReArm","Re-Arm","AAct","ConsoleAct","vlmcs","Renewal" };

    // Known public KMS servers used for piracy
    static readonly string[] PublicKmsServers = {
        "185.213.174.199", "107.175.77.7", "kms.digiboy.ir", "kms.lotro.cc",
        "kms8.msguides.com", "kms9.msguides.com", "kms.zhuxiaole.org",
        "kms.loli.beer", "kms.cangshui.net", "kms.library.hk",
        "s8.uk.to", "s9.us", "hq1.chinancce.com"
    };

    // Known HWID/Digital license generic keys (not real purchased keys)
    static readonly string[] GenericVLKeys = {
        "W269N", "VK7JG", "YNMGQ", "8DVY4", "3V66T", "MH37W", "TX9XD",
        "3KHY7", "7HNRX", "NPPR9", "WGGHN", "PVMJN", "J9PJD"
    };

    public List<AppInfo> ScanApps()
    {
        var apps = new Dictionary<string, AppInfo>(StringComparer.OrdinalIgnoreCase);
        string[] regPaths = {
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        };
        foreach (var rp in regPaths)
            ScanRegKey(Registry.LocalMachine, rp, apps);
        ScanRegKey(Registry.CurrentUser, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", apps);
        return apps.Values.OrderBy(a => a.Name).ToList();
    }

    void ScanRegKey(RegistryKey root, string subPath, Dictionary<string, AppInfo> apps)
    {
        try
        {
            using var key = root.OpenSubKey(subPath);
            if (key == null) return;
            foreach (var subName in key.GetSubKeyNames())
            {
                try
                {
                    using var sub = key.OpenSubKey(subName);
                    var name = sub?.GetValue("DisplayName")?.ToString()?.Trim();
                    if (string.IsNullOrEmpty(name) || apps.ContainsKey(name)) continue;
                    var pub = sub?.GetValue("Publisher")?.ToString() ?? "N/A";
                    var ver = sub?.GetValue("DisplayVersion")?.ToString() ?? "N/A";
                    var sizeObj = sub?.GetValue("EstimatedSize");
                    double size = sizeObj != null ? Math.Round(Convert.ToDouble(sizeObj) / 1024.0, 1) : 0;
                    var app = new AppInfo { Name = name, Publisher = pub, Version = ver, SizeMB = size };
                    Classify(app);
                    apps[name] = app;
                }
                catch { }
            }
        }
        catch { }
    }

    void Classify(AppInfo app)
    {
        foreach (var cp in CrackPatterns)
            if (Contains(app.Name, cp)) { app.LicType = "crack"; app.CrackRisk = "critical"; return; }
        foreach (var kf in KnownFree)
            if (Contains(app.Name, kf)) { app.LicType = "free"; return; }
        foreach (var kc in KnownCommercial)
            if (Contains(app.Name, kc)) { app.LicType = "commercial"; return; }
        foreach (var cp in CommercialPubs)
            if (Contains(app.Publisher, cp)) { app.LicType = "commercial"; return; }
        string[] freeKw = { "Free", "Open Source", "GPL", "MIT", "Apache", "Mozilla", "GNU", "Community", "Freeware" };
        foreach (var fk in freeKw)
            if (Contains(app.Name, fk) || Contains(app.Publisher, fk)) { app.LicType = "free"; return; }
        if (Regex.IsMatch(app.Name, @"Trial|Demo|Evaluation|Preview", RegexOptions.IgnoreCase))
            app.LicType = "trial";
    }

    static bool Contains(string text, string pattern)
        => text.IndexOf(pattern, StringComparison.OrdinalIgnoreCase) >= 0;

    // ================================================================
    // WINDOWS LICENSE - DEEP CHECK
    // ================================================================
    public WinLicense CheckWindowsLicense()
    {
        var lic = new WinLicense();
        try
        {
            var ps = RunPowerShell(@"
$w = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter ""ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL"" -EA Stop | Select-Object -First 1
$k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -EA SilentlyContinue
$di = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA SilentlyContinue
$domain = (Get-CimInstance Win32_ComputerSystem).Domain
""$($w.Name)|$($w.LicenseStatus)|$($w.PartialProductKey)|$($w.Description)|$($k.KeyManagementServiceName)|$($k.KeyManagementServicePort)|$($di.DigitalProductId -ne $null)|$domain|$($w.GracePeriodRemaining)""");

            var parts = ps.Trim().Split('|');
            if (parts.Length >= 9)
            {
                lic.Product = parts[0];
                lic.Status = parts[1] switch { "1" => "Licensed", "0" => "Unlicensed", _ => parts[1] };
                lic.PartialKey = parts[2];
                lic.Description = parts[3];

                if (parts[3].Contains("VOLUME") || parts[3].Contains("KMS")) lic.Type = "KMS/Volume";
                else if (parts[3].Contains("RETAIL")) lic.Type = "Retail";
                else if (parts[3].Contains("OEM")) lic.Type = "OEM";

                string kmsHost = parts[4].Trim();
                string kmsPort = string.IsNullOrEmpty(parts[5].Trim()) ? "1688" : parts[5].Trim();
                string domain = parts[7].Trim();

                // === RED FLAG ANALYSIS ===

                // 1. KMS server exists
                if (!string.IsNullOrEmpty(kmsHost))
                {
                    lic.KmsServer = $"{kmsHost}:{kmsPort}";

                    // Check if it's a known public crack KMS server
                    bool isPublicKms = false;
                    foreach (var pks in PublicKmsServers)
                        if (kmsHost.Contains(pks, StringComparison.OrdinalIgnoreCase)) { isPublicKms = true; break; }

                    if (isPublicKms)
                    {
                        lic.RedFlags.Add($"KMS server la server crack cong cong: {kmsHost}");
                        lic.KmsWarning = "KMS server crack!";
                    }
                    else if (Regex.IsMatch(kmsHost, @"^(\d{1,3}\.){3}\d{1,3}$"))
                    {
                        // It's an IP address - suspicious unless in corporate environment
                        lic.RedFlags.Add($"KMS server la dia chi IP: {kmsHost} (thuong chi thay trong moi truong crack)");
                    }
                    else
                    {
                        lic.RedFlags.Add($"KMS server duoc cau hinh: {kmsHost}");
                    }
                }

                // 2. Retail channel but has KMS server = contradiction
                if (lic.Type == "Retail" && !string.IsNullOrEmpty(kmsHost))
                {
                    lic.RedFlags.Add("MAU THUAN: Kenh kich hoat la RETAIL nhung lai co KMS server -> dau hieu crack HWID/KMS");
                }

                // 3. KMS/Volume but not domain-joined
                if (lic.Type == "KMS/Volume" && (string.IsNullOrEmpty(domain) || domain == "WORKGROUP"))
                {
                    lic.RedFlags.Add("KMS/Volume activation nhung may khong join domain -> nghi van crack");
                }

                // 4. Check partial key against known generic VL keys
                if (!string.IsNullOrEmpty(lic.PartialKey))
                {
                    foreach (var gk in GenericVLKeys)
                    {
                        if (lic.PartialKey.Equals(gk, StringComparison.OrdinalIgnoreCase))
                        {
                            lic.RedFlags.Add($"Product key cuoi '{lic.PartialKey}' trung voi key generic/VL pho bien -> crack");
                            break;
                        }
                    }
                }

                // 5. Grace period = 0 with Licensed status on RETAIL + KMS = suspicious
                if (parts[8].Trim() == "0" && lic.Status == "Licensed" && !string.IsNullOrEmpty(kmsHost))
                {
                    lic.RedFlags.Add("Grace period = 0 voi KMS server -> kich hoat bang cong cu crack");
                }

                // === FINAL VERDICT ===
                if (lic.RedFlags.Count == 0)
                {
                    lic.IsGenuine = true;
                    lic.Verdict = "BAN QUYEN HOP LE - Khong phat hien dau hieu bat thuong";
                }
                else if (lic.RedFlags.Count == 1 && lic.Type == "KMS/Volume")
                {
                    lic.IsGenuine = true; // Could be legitimate corporate
                    lic.Verdict = "CO THE HOP LE - KMS/Volume (kiem tra moi truong doanh nghiep)";
                }
                else
                {
                    lic.IsGenuine = false;
                    lic.Verdict = $"NGHI VAN CRACK - Phat hien {lic.RedFlags.Count} dau hieu bat thuong";
                }
            }
        }
        catch { }
        return lic;
    }

    // ================================================================
    // HOSTS FILE
    // ================================================================
    public List<string> CheckHostsFile()
    {
        var blocked = new List<string>();
        try
        {
            var hostsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "drivers", "etc", "hosts");
            foreach (var line in File.ReadAllLines(hostsPath))
            {
                var t = line.Trim();
                if (string.IsNullOrEmpty(t) || t.StartsWith("#")) continue;
                foreach (var bd in BlockedDomains)
                    if (t.Contains(bd, StringComparison.OrdinalIgnoreCase)) { blocked.Add(bd); break; }
            }
        }
        catch { }
        return blocked;
    }

    // ================================================================
    // SCHEDULED TASKS
    // ================================================================
    public List<string> CheckScheduledTasks()
    {
        var suspicious = new List<string>();
        try
        {
            var output = RunPowerShell("Get-ScheduledTask | Select-Object -ExpandProperty TaskName");
            foreach (var taskName in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                var name = taskName.Trim();
                foreach (var tp in TaskPatterns)
                    if (name.Contains(tp, StringComparison.OrdinalIgnoreCase)) { suspicious.Add(name); break; }
            }
        }
        catch { }
        return suspicious;
    }

    // ================================================================
    // CROSS-ANALYSIS: combine all signals to produce final warnings
    // ================================================================
    public List<CrackWarning> CrossAnalyze(List<AppInfo> apps, WinLicense winLic, List<string> blocked, List<string> tasks)
    {
        var warnings = new List<CrackWarning>();

        // Crack tools in installed apps
        foreach (var a in apps.Where(a => a.LicType == "crack"))
            warnings.Add(new CrackWarning { Severity = "Critical", Type = "Crack Tool", Target = a.Name, Detail = $"Phan mem crack '{a.Name}' duoc cai dat tren may" });

        // Windows license red flags
        foreach (var rf in winLic.RedFlags)
            warnings.Add(new CrackWarning { Severity = "Critical", Type = "Windows License", Target = "Windows", Detail = rf });

        // Windows verdict
        if (!winLic.IsGenuine)
            warnings.Add(new CrackWarning { Severity = "Critical", Type = "Ket luan", Target = "Windows", Detail = winLic.Verdict });

        // Hosts file blocks
        foreach (var h in blocked)
        {
            string target = h.Contains("adobe") ? "Adobe" : h.Contains("jetbrains") ? "JetBrains" : "Microsoft";
            warnings.Add(new CrackWarning { Severity = "High", Type = "Hosts File", Target = target, Detail = $"Domain kich hoat bi chan: {h}" });
        }

        // Suspicious tasks
        foreach (var t in tasks)
            warnings.Add(new CrackWarning { Severity = "High", Type = "Scheduled Task", Target = "System", Detail = $"Task dang ngo: {t}" });

        // === CROSS-CHECK: Retail + KMS + Activation task = definitely cracked ===
        bool hasKms = !string.IsNullOrEmpty(winLic.KmsServer);
        bool hasActivationTask = tasks.Any(t => t.Contains("Activ", StringComparison.OrdinalIgnoreCase) || t.Contains("Renewal", StringComparison.OrdinalIgnoreCase));

        if (winLic.Type == "Retail" && hasKms && hasActivationTask)
        {
            warnings.Add(new CrackWarning
            {
                Severity = "Critical",
                Type = "Phan tich cheo",
                Target = "Windows",
                Detail = "KET LUAN: Windows CRACK - Kenh Retail + KMS server cong cong + Task tu dong gia han = 100% crack (HWID/KMS tool)"
            });
        }
        else if (hasKms && hasActivationTask)
        {
            warnings.Add(new CrackWarning
            {
                Severity = "Critical",
                Type = "Phan tich cheo",
                Target = "Windows",
                Detail = "KET LUAN: Windows NGHI VAN CRACK CAO - Co KMS server + Task tu dong gia han kich hoat"
            });
        }
        else if (hasKms && winLic.Type == "Retail")
        {
            warnings.Add(new CrackWarning
            {
                Severity = "High",
                Type = "Phan tich cheo",
                Target = "Windows",
                Detail = "CANH BAO: Kenh Retail nhung co KMS server -> bat thuong, co the da bi crack"
            });
        }

        return warnings;
    }

    static string RunPowerShell(string script)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{script.Replace("\"", "\\\"")}\"",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            CreateNoWindow = true,
            StandardOutputEncoding = System.Text.Encoding.UTF8
        };
        using var proc = Process.Start(psi)!;
        var result = proc.StandardOutput.ReadToEnd();
        proc.WaitForExit(30000);
        return result;
    }
}
