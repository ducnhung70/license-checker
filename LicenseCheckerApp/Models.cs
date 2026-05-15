using System.Collections.Generic;

namespace LicenseChecker;

public class AppInfo
{
    public string Name { get; set; } = "";
    public string Publisher { get; set; } = "N/A";
    public string Version { get; set; } = "N/A";
    public double SizeMB { get; set; }
    public string LicType { get; set; } = "unknown"; // free, commercial, trial, crack, unknown
    public string CrackRisk { get; set; } = "none";
}

public class WinLicense
{
    public string Product { get; set; } = "";
    public string Status { get; set; } = "Unknown";
    public string Type { get; set; } = "Unknown";       // Retail, OEM, KMS/Volume
    public string PartialKey { get; set; } = "";
    public string Description { get; set; } = "";
    public string KmsServer { get; set; } = "";
    public string KmsWarning { get; set; } = "";
    public bool IsGenuine { get; set; } = true;          // Final verdict
    public string Verdict { get; set; } = "";             // Human-readable verdict
    public List<string> RedFlags { get; set; } = new();   // All suspicious findings
}

public class CrackWarning
{
    public string Severity { get; set; } = "Medium";  // Critical, High, Medium
    public string Type { get; set; } = "";             // KMS, Hosts, Task, Process, CrossCheck
    public string Target { get; set; } = "";           // What app/component
    public string Detail { get; set; } = "";           // Description
}
