using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;

namespace LicenseChecker;

class Program
{
    static void Main()
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.Title = "License Checker v1.0";

        Print("  ========================================", ConsoleColor.Cyan);
        Print("    License Checker v1.0", ConsoleColor.White);
        Print("    Kiem tra ban quyen & phat hien crack", ConsoleColor.Gray);
        Print("  ========================================", ConsoleColor.Cyan);
        Console.WriteLine();

        var scanner = new Scanner();

        Print("  [1/6] Quet phan mem...", ConsoleColor.Yellow);
        var apps = scanner.ScanApps();
        Print($"    -> {apps.Count} ung dung", ConsoleColor.Green);

        Print("  [2/6] Kiem tra Windows license...", ConsoleColor.Yellow);
        var winLic = scanner.CheckWindowsLicense();
        var wColor = winLic.IsGenuine ? ConsoleColor.Green : ConsoleColor.Red;
        Print($"    -> {winLic.Status} ({winLic.Type})", wColor);
        if (!winLic.IsGenuine) Print($"    -> {winLic.Verdict}", ConsoleColor.Red);

        Print("  [3/6] Kiem tra file hosts...", ConsoleColor.Yellow);
        var blocked = scanner.CheckHostsFile();
        Print($"    -> {blocked.Count} domain bi chan", blocked.Count > 0 ? ConsoleColor.Red : ConsoleColor.Green);

        Print("  [4/6] Kiem tra Scheduled Tasks...", ConsoleColor.Yellow);
        var tasks = scanner.CheckScheduledTasks();
        Print($"    -> {tasks.Count} task dang ngo", tasks.Count > 0 ? ConsoleColor.Red : ConsoleColor.Green);

        Print("  [5/6] Phan tich cheo...", ConsoleColor.Yellow);
        var warnings = scanner.CrossAnalyze(apps, winLic, blocked, tasks);
        var warnColor = warnings.Count > 0 ? ConsoleColor.Red : ConsoleColor.Green;
        Print($"    -> {warnings.Count} canh bao", warnColor);

        Print("  [6/6] Tao bao cao...", ConsoleColor.Yellow);
        var report = new ReportBuilder();
        var path = report.Generate(apps, winLic, warnings);

        Console.WriteLine();
        Print("  ========================================", ConsoleColor.Cyan);
        if (warnings.Count > 0)
            Print($"  !! PHAT HIEN {warnings.Count} VAN DE BAN QUYEN !!", ConsoleColor.Red);
        else
            Print("    He thong sach!", ConsoleColor.Green);
        Print("    Dang mo bao cao...", ConsoleColor.Green);
        Print($"    {path}", ConsoleColor.Gray);
        Print("  ========================================", ConsoleColor.Cyan);

        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    static void Print(string msg, ConsoleColor c)
    {
        Console.ForegroundColor = c;
        Console.WriteLine(msg);
        Console.ResetColor();
    }
}
