using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;

namespace LicenseChecker;

public class ReportBuilder
{
    public string Generate(List<AppInfo> apps, WinLicense winLic, List<CrackWarning> warnings)
    {
        int total = apps.Count, free = apps.Count(a => a.LicType == "free");
        int comm = apps.Count(a => a.LicType == "commercial"), unk = apps.Count(a => a.LicType == "unknown");
        int warnCount = warnings.Count;
        int critical = warnings.Count(w => w.Severity == "Critical");
        int high = warnings.Count(w => w.Severity == "High");

        string risk = critical > 0 ? "Critical" : high > 0 ? "High" : warnCount > 0 ? "Medium" : "Clean";
        string riskCls = risk switch { "Critical"=>"risk-critical", "High"=>"risk-high", "Medium"=>"risk-medium", _=>"risk-clean" };

        // App rows
        var rows = new StringBuilder();
        foreach (var a in apps)
        {
            string bc = a.LicType switch { "free"=>"bg-green", "commercial"=>"bg-orange", "trial"=>"bg-yellow", "crack"=>"bg-red", _=>"bg-gray" };
            string bt = a.LicType switch { "free"=>"Mien phi", "commercial"=>"Thuong mai", "trial"=>"Dung thu", "crack"=>"CRACK", _=>"Chua ro" };
            string sz = a.SizeMB > 0 ? (a.SizeMB >= 1024 ? $"{a.SizeMB/1024:F1} GB" : $"{a.SizeMB} MB") : "-";
            string rc = a.LicType == "crack" ? " class=\"cr-row\"" : "";
            rows.AppendLine($"<tr{rc}><td class='n'>{E(a.Name)}</td><td>{E(a.Publisher)}</td><td class='c'>{E(a.Version)}</td><td class='c'>{sz}</td><td class='c'><span class='b {bc}'>{bt}</span></td></tr>");
        }

        // Warnings
        var wsb = new StringBuilder();
        if (warnCount == 0)
        {
            wsb.Append("<div class='al ok'>&#10004; He thong sach - Khong phat hien dau hieu crack</div>");
        }
        else
        {
            wsb.Append($"<div class='al bad'>&#9888; Phat hien <b>{warnCount}</b> van de ban quyen ({critical} Critical, {high} High)</div>");
            foreach (var w in warnings)
            {
                string sc = w.Severity == "Critical" ? "cr" : "hi";
                wsb.Append($"<div class='wi {sc}'><span class='sv'>{w.Severity.ToUpper()}</span><div class='wc'><div class='wt'>{E(w.Type)}</div><div class='wa'>{E(w.Target)}</div><div class='wd'>{E(w.Detail)}</div></div></div>");
            }
        }

        // Windows verdict
        string verdictCls = winLic.IsGenuine ? "vd-ok" : "vd-bad";
        string verdictIcon = winLic.IsGenuine ? "&#10004;" : "&#10008;";
        string verdictHtml = $"<div class='verdict {verdictCls}'><span class='vi'>{verdictIcon}</span> {E(winLic.Verdict)}</div>";

        // Red flags
        var rfHtml = new StringBuilder();
        if (winLic.RedFlags.Count > 0)
        {
            rfHtml.Append("<div class='rf-list'><div class='rf-title'>Chi tiet phan tich:</div>");
            foreach (var rf in winLic.RedFlags)
                rfHtml.Append($"<div class='rf-item'>&#9679; {E(rf)}</div>");
            rfHtml.Append("</div>");
        }

        string wsc = winLic.Status == "Licensed" ? "bg-green" : "bg-red";
        string wst = winLic.Status == "Licensed" ? "Da kich hoat" : winLic.Status;
        string wtc = winLic.Type switch { "Retail"=>"color:#3b82f6", "OEM"=>"color:#22c55e", "KMS/Volume"=>"color:#f59e0b", _=>"" };
        string kmsH = !string.IsNullOrEmpty(winLic.KmsServer) ? $"<div class='wli'><label>KMS Server</label><span style='color:#ef4444;font-weight:700'>{E(winLic.KmsServer)}</span></div>" : "";
        string now = DateTime.Now.ToString("dd/MM/yyyy HH:mm");

        string html = $@"<!DOCTYPE html>
<html lang=""vi""><head><meta charset=""UTF-8""><meta name=""viewport"" content=""width=device-width,initial-scale=1"">
<title>License Checker Report</title>
<link href=""https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap"" rel=""stylesheet"">
<style>
*{{box-sizing:border-box;margin:0;padding:0}}body{{font-family:'Inter',system-ui,sans-serif;background:#0a0a0f;color:#e8e8f0;line-height:1.6}}.ct{{max-width:1200px;margin:0 auto;padding:24px}}
h1{{font-size:1.5rem;font-weight:800;background:linear-gradient(135deg,#6366f1,#a855f7);-webkit-background-clip:text;-webkit-text-fill-color:transparent}}
.sub{{color:#6a6a82;font-size:.85rem;margin-bottom:20px}}.sg{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:20px}}
.st{{padding:16px;background:#12121a;border:1px solid rgba(255,255,255,.06);border-radius:12px;text-align:center}}.stv{{font-size:2rem;font-weight:800;display:block}}.stl{{font-size:.72rem;color:#6a6a82;text-transform:uppercase;letter-spacing:.5px}}
.cb{{color:#3b82f6}}.cg{{color:#22c55e}}.co{{color:#f59e0b}}.crd{{color:#ef4444}}.cgr{{color:#6a6a82}}
.cd{{background:#12121a;border:1px solid rgba(255,255,255,.06);border-radius:12px;padding:20px;margin-bottom:16px}}.cd h2{{font-size:1rem;font-weight:600;margin-bottom:12px;display:flex;align-items:center;gap:8px}}
.al{{padding:14px 20px;border-radius:10px;font-size:.9rem;margin-bottom:16px;display:flex;align-items:center;gap:10px}}
.ok{{background:rgba(34,197,94,.08);border:1px solid rgba(34,197,94,.25);color:#22c55e}}.bad{{background:rgba(239,68,68,.08);border:1px solid rgba(239,68,68,.25);color:#ef4444}}
.wi{{padding:12px 16px;background:#0a0a0f;border:1px solid rgba(255,255,255,.06);border-radius:8px;font-size:.85rem;display:flex;align-items:flex-start;gap:10px;margin-bottom:6px}}
.wi.cr{{border-left:3px solid #ef4444}}.wi.hi{{border-left:3px solid #f97316}}
.sv{{padding:2px 8px;border-radius:10px;font-size:.65rem;font-weight:700;text-transform:uppercase;flex-shrink:0;margin-top:2px}}
.cr .sv{{background:rgba(239,68,68,.15);color:#ef4444}}.hi .sv{{background:rgba(249,115,22,.15);color:#f97316}}
.wc{{flex:1}}.wt{{font-size:.72rem;color:#6a6a82;text-transform:uppercase;letter-spacing:.5px}}.wa{{font-weight:600;font-size:.88rem;margin:2px 0}}.wd{{color:#a0a0b8;font-size:.82rem}}
.rb{{display:inline-block;padding:4px 14px;border-radius:20px;font-size:.75rem;font-weight:700;text-transform:uppercase}}
.risk-critical{{background:rgba(239,68,68,.15);color:#ef4444;border:1px solid rgba(239,68,68,.3)}}.risk-high{{background:rgba(249,115,22,.15);color:#f97316}}.risk-medium{{background:rgba(245,158,11,.15);color:#f59e0b}}.risk-clean{{background:rgba(34,197,94,.15);color:#22c55e}}
.verdict{{padding:14px 20px;border-radius:10px;font-size:.95rem;font-weight:600;margin:12px 0;display:flex;align-items:center;gap:10px}}
.vd-ok{{background:rgba(34,197,94,.08);border:1px solid rgba(34,197,94,.25);color:#22c55e}}
.vd-bad{{background:rgba(239,68,68,.08);border:1px solid rgba(239,68,68,.25);color:#ef4444}}
.vi{{font-size:1.3rem}}
.rf-list{{margin:12px 0;padding:14px 18px;background:#0a0a0f;border-radius:8px;border:1px solid rgba(239,68,68,.15)}}
.rf-title{{font-size:.78rem;color:#ef4444;text-transform:uppercase;letter-spacing:.5px;font-weight:600;margin-bottom:8px}}
.rf-item{{font-size:.84rem;color:#e8e8f0;padding:4px 0;border-bottom:1px solid rgba(255,255,255,.03)}}
.rf-item:last-child{{border-bottom:none}}
.wg{{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px;margin-top:12px}}.wli{{padding:8px 12px;background:#0a0a0f;border-radius:6px;border:1px solid rgba(255,255,255,.05)}}.wli label{{display:block;font-size:.7rem;color:#6a6a82;text-transform:uppercase;letter-spacing:.5px;margin-bottom:2px}}.wli span{{font-size:.88rem;font-weight:500}}
.b{{padding:3px 10px;border-radius:12px;font-size:.72rem;font-weight:600;white-space:nowrap}}.bg-green{{background:rgba(34,197,94,.12);color:#22c55e}}.bg-orange{{background:rgba(245,158,11,.12);color:#f59e0b}}.bg-yellow{{background:rgba(234,179,8,.12);color:#eab308}}.bg-red{{background:rgba(239,68,68,.15);color:#ef4444}}.bg-gray{{background:rgba(160,160,184,.08);color:#6a6a82}}
table{{width:100%;border-collapse:collapse;font-size:.85rem}}th{{text-align:left;padding:10px 12px;border-bottom:1px solid rgba(255,255,255,.08);color:#6a6a82;font-size:.75rem;text-transform:uppercase;letter-spacing:.5px;font-weight:600;position:sticky;top:0;background:#12121a;z-index:1}}
td{{padding:10px 12px;border-bottom:1px solid rgba(255,255,255,.04)}}tr:hover td{{background:rgba(255,255,255,.02)}}.cr-row td{{background:rgba(239,68,68,.04)}}.cr-row:hover td{{background:rgba(239,68,68,.08)}}
.n{{font-weight:600}}.c{{text-align:center}}.tb{{display:flex;gap:10px;margin-bottom:12px;flex-wrap:wrap;align-items:center}}
.tb input{{flex:1;min-width:200px;padding:8px 14px;background:#0a0a0f;border:1px solid rgba(255,255,255,.08);border-radius:8px;color:#e8e8f0;font-size:.85rem;outline:none}}.tb input:focus{{border-color:#6366f1}}
.tb select{{padding:8px 12px;background:#0a0a0f;border:1px solid rgba(255,255,255,.08);border-radius:8px;color:#e8e8f0;font-size:.85rem;outline:none}}
.ft{{text-align:center;padding:20px;color:#6a6a82;font-size:.78rem;border-top:1px solid rgba(255,255,255,.04);margin-top:24px}}
@media(max-width:768px){{.sg{{grid-template-columns:repeat(2,1fr)}}th:nth-child(3),td:nth-child(3),th:nth-child(4),td:nth-child(4){{display:none}}}}
</style></head><body><div class=""ct"">
<div style=""display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:8px"">
<div><h1>&#128737; License Checker Report</h1><div class=""sub"">{Environment.MachineName} &bull; {now}</div></div>
<span class=""rb {riskCls}"">{risk}</span></div>
<div class=""sg"">
<div class=""st""><span class=""stv cb"">{total}</span><span class=""stl"">Tong</span></div>
<div class=""st""><span class=""stv cg"">{free}</span><span class=""stl"">Mien phi</span></div>
<div class=""st""><span class=""stv co"">{comm}</span><span class=""stl"">Thuong mai</span></div>
<div class=""st""><span class=""stv cgr"">{unk}</span><span class=""stl"">Chua ro</span></div>
<div class=""st""><span class=""stv crd"">{warnCount}</span><span class=""stl"">Canh bao</span></div>
</div>
{wsb}
<div class=""cd""><h2>&#127987; Ban quyen Windows <span class=""b {wsc}"" style=""margin-left:auto"">{wst}</span></h2>
{verdictHtml}
<div class=""wg"">
<div class=""wli""><label>San pham</label><span>{E(winLic.Product)}</span></div>
<div class=""wli""><label>Key</label><span>XXXXX-{winLic.PartialKey}</span></div>
<div class=""wli""><label>Kieu kich hoat</label><span style=""{wtc};font-weight:600"">{winLic.Type}</span></div>
{kmsH}
<div class=""wli""><label>Kenh</label><span>{E(winLic.Description)}</span></div>
</div>
{rfHtml}
</div>
<div class=""cd""><h2>&#128230; Phan mem ({total})</h2>
<div class=""tb""><input type=""text"" id=""s"" placeholder=""Tim kiem..."" oninput=""f()"">
<select id=""ft"" onchange=""f()""><option value="""">Tat ca</option><option value=""free"">Mien phi</option><option value=""commercial"">Thuong mai</option><option value=""trial"">Dung thu</option><option value=""crack"">Crack</option><option value=""unknown"">Chua ro</option></select></div>
<div style=""max-height:600px;overflow-y:auto;border-radius:8px""><table id=""t""><thead><tr><th>Ten</th><th>Nha PH</th><th>Version</th><th>Size</th><th class=""c"">Trang thai</th></tr></thead><tbody>{rows}</tbody></table></div>
<div id=""ci"" style=""text-align:center;padding:10px;color:#6a6a82;font-size:.8rem""></div></div>
<div class=""ft"">License Checker v1.0 &bull; {now}</div></div>
<script>function f(){{var s=document.getElementById('s').value.toLowerCase(),v=document.getElementById('ft').value,r=document.querySelectorAll('#t tbody tr'),n=0;r.forEach(function(r){{var a=r.cells[0].textContent.toLowerCase(),p=r.cells[1].textContent.toLowerCase(),b=r.querySelector('.b'),t=b?b.textContent.toLowerCase():'',m={{'mien phi':'free','thuong mai':'commercial','dung thu':'trial','crack':'crack','chua ro':'unknown'}},y=m[t]||'unknown',ms=!s||a.includes(s)||p.includes(s),mf=!v||y===v;r.style.display=(ms&&mf)?'':'none';if(ms&&mf)n++}});document.getElementById('ci').textContent='Hien thi '+n+'/'+r.length+' ung dung'}};f()</script></body></html>";

        var path = Path.Combine(Path.GetTempPath(), "LicenseChecker-Report.html");
        File.WriteAllText(path, html, Encoding.UTF8);
        return path;
    }

    static string E(string s) => WebUtility.HtmlEncode(s ?? "");
}
