<#
.SYNOPSIS
  License Checker - Kiem tra ban quyen & phat hien crack phan mem
.DESCRIPTION
  Quet toan bo phan mem, phat hien crack, tao bao cao HTML tu dong mo tren trinh duyet.
  Chay voi quyen Administrator de ket qua chinh xac nhat.
.NOTES
  Author: AnhNVT | Version: 1.0
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "    License Checker v1.0" -ForegroundColor White
Write-Host "    Kiem tra ban quyen & phat hien crack" -ForegroundColor Gray
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. SCAN INSTALLED SOFTWARE
# ============================================================
Write-Host "  [1/6] Quet phan mem da cai dat..." -ForegroundColor Yellow
$apps = @()
$regPaths = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($rp in $regPaths) {
  $items = Get-ItemProperty $rp -EA SilentlyContinue
  foreach ($item in $items) {
    if ($item.DisplayName -and $item.DisplayName.Trim() -ne '') {
      $name = $item.DisplayName
      $publisher = if ($item.Publisher) { $item.Publisher } else { 'N/A' }
      $version = if ($item.DisplayVersion) { $item.DisplayVersion } else { 'N/A' }
      $size = if ($item.EstimatedSize) { [math]::Round($item.EstimatedSize / 1024, 1) } else { 0 }
      $installLoc = if ($item.InstallLocation) { $item.InstallLocation } else { '' }

      $licType = 'unknown'; $crackRisk = 'none'

      # Crack tool detection
      $crackPatterns = @('KMSPico','KMSAuto','KMS Tools','KMS Activator','Re-Loader','ReLoader','Microsoft Toolkit','AAct','KMSCleaner','RemoveWAT','Windows Loader','Daz Loader','HWIDGEN','HWIDGen','MAS ','Mini-KMS','AutoKMS','Ratiborus','AMTEmu','AMT Emulator','Adobe Zii','GenP','CCMaker','Xforce','X-Force','Universal Adobe Patcher')
      foreach ($cp in $crackPatterns) {
        if ($name -match [regex]::Escape($cp)) { $licType = 'crack'; $crackRisk = 'critical'; break }
      }

      if ($licType -ne 'crack') {
        $knownFree = @('Firefox','Chrome','Chromium','VLC','GIMP','Audacity','7-Zip','Visual Studio Code','VS Code','Git','Python','Node','Java','OpenJDK','LibreOffice','FileZilla','PuTTY','WinSCP','OBS Studio','Blender','Inkscape','KeePass','Telegram','Discord','Slack','Zoom','Steam','Epic Games','PowerShell','Redistributable','Runtime','SDK','Windows Terminal','ShareX','qBittorrent','HandBrake','Krita','Thunderbird','Brave','Vivaldi','Opera','Edge','.NET','Visual C')
        foreach ($kf in $knownFree) { if ($name -match [regex]::Escape($kf)) { $licType = 'free'; break } }

        if ($licType -eq 'unknown') {
          $knownComm = @('Microsoft Office','Microsoft 365','Adobe Photoshop','Adobe Illustrator','Adobe Premiere','Adobe Creative','Adobe Acrobat Pro','AutoCAD','CorelDRAW','WinRAR','Internet Download Manager','Sublime Text','Total Commander','Camtasia','Snagit','MATLAB','Norton','Kaspersky','Bitdefender','ESET','Avast Premium','VMware Workstation','Navicat','DataGrip','IntelliJ IDEA Ultimate','PhpStorm','WebStorm','PyCharm Professional','Rider','ReSharper','SQL Server','Visio','Project Professional')
          foreach ($kc in $knownComm) { if ($name -match [regex]::Escape($kc)) { $licType = 'commercial'; break } }
        }
        if ($licType -eq 'unknown') {
          $commPubs = @('Microsoft','Adobe','Autodesk','VMware','JetBrains','Telerik','DevExpress')
          foreach ($cp2 in $commPubs) { if ($publisher -match $cp2) { $licType = 'commercial'; break } }
        }
        $freeKw = @('Free','Open Source','GPL','MIT','Apache','Mozilla','GNU','Community','Freeware')
        foreach ($fk in $freeKw) { if ($licType -eq 'unknown' -and ($name -match $fk -or $publisher -match $fk)) { $licType = 'free'; break } }
        if ($name -match 'Trial|Demo|Evaluation|Preview') { $licType = 'trial' }
      }

      $apps += [PSCustomObject]@{ Name=$name; Publisher=$publisher; Version=$version; SizeMB=$size; LicType=$licType; CrackRisk=$crackRisk; InstallLoc=$installLoc }
    }
  }
}
$apps = $apps | Sort-Object Name -Unique
Write-Host "    -> Tim thay $($apps.Count) ung dung" -ForegroundColor Green

# ============================================================
# 2. WINDOWS LICENSE
# ============================================================
Write-Host "  [2/6] Kiem tra ban quyen Windows..." -ForegroundColor Yellow
$winLic = @{ Status='Unknown'; Type='Unknown'; Key=''; Product=''; Desc=''; KmsServer=''; KmsWarn='' }
try {
  $wmi = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -EA Stop | Select-Object -First 1
  if ($wmi) {
    $winLic.Product = $wmi.Name
    $winLic.Desc = $wmi.Description
    $winLic.Key = $wmi.PartialProductKey
    $winLic.Status = switch ($wmi.LicenseStatus) { 0{'Unlicensed'} 1{'Licensed'} 2{'OOBGrace'} 3{'OOTGrace'} 4{'NonGenuine'} 5{'Notification'} 6{'ExtendedGrace'} default{'Unknown'} }
    if ($wmi.Description -match 'VOLUME|KMS') { $winLic.Type = 'KMS/Volume' }
    elseif ($wmi.Description -match 'RETAIL') { $winLic.Type = 'Retail' }
    elseif ($wmi.Description -match 'OEM') { $winLic.Type = 'OEM' }
    $kmsReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -EA SilentlyContinue
    if ($kmsReg.KeyManagementServiceName) {
      $winLic.KmsServer = "$($kmsReg.KeyManagementServiceName):$($kmsReg.KeyManagementServicePort)"
      if ($kmsReg.KeyManagementServiceName -match '127\.|localhost|0\.0\.0\.|kms\.|vlmcs') { $winLic.KmsWarn = 'KMS server dang ngo' }
    }
  }
} catch {}
$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
Write-Host "    -> $osCaption - $($winLic.Status)" -ForegroundColor Green

# ============================================================
# 3. HOSTS FILE CHECK
# ============================================================
Write-Host "  [3/6] Kiem tra file hosts..." -ForegroundColor Yellow
$hostsBlocked = @()
try {
  $hostsContent = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -EA SilentlyContinue
  $blockedDomains = @('activation.sls.microsoft.com','validation.sls.microsoft.com','genuine.microsoft.com','activate.adobe.com','practivate.adobe.com','lmlicenses.wip4.adobe.com','lm.licenses.adobe.com','activate.wip3.adobe.com','ereg.adobe.com','3dns-3.adobe.com','3dns-2.adobe.com','adobeereg.com','account.jetbrains.com')
  foreach ($line in $hostsContent) {
    $t = $line.Trim()
    if ($t -and -not $t.StartsWith('#')) {
      foreach ($bd in $blockedDomains) {
        if ($t -match [regex]::Escape($bd)) { $hostsBlocked += "$bd" }
      }
    }
  }
} catch {}
Write-Host "    -> $($hostsBlocked.Count) domain bi chan" -ForegroundColor $(if ($hostsBlocked.Count -gt 0) {'Red'} else {'Green'})

# ============================================================
# 4. SCHEDULED TASKS
# ============================================================
Write-Host "  [4/6] Kiem tra Scheduled Tasks..." -ForegroundColor Yellow
$suspTasks = @()
try {
  $tasks = Get-ScheduledTask -EA SilentlyContinue
  $taskPat = @('KMS','AutoKMS','KMSAuto','Activat','ReArm','Re-Arm','AAct','ConsoleAct','vlmcs')
  foreach ($task in $tasks) {
    foreach ($tp in $taskPat) {
      if ($task.TaskName -match $tp) { $suspTasks += "$($task.TaskName) ($($task.State))"; break }
    }
  }
} catch {}
Write-Host "    -> $($suspTasks.Count) task dang ngo" -ForegroundColor $(if ($suspTasks.Count -gt 0) {'Red'} else {'Green'})

# ============================================================
# 5. SUSPICIOUS PROCESSES
# ============================================================
Write-Host "  [5/6] Kiem tra processes..." -ForegroundColor Yellow
$suspProcs = @()
try {
  $procs = Get-Process -EA SilentlyContinue
  $procPat = @('KMSPico','KMSAuto','AutoKMS','vlmcsd','AAct','ConsoleAct','hwidgen')
  foreach ($proc in $procs) {
    foreach ($pp in $procPat) {
      if ($proc.ProcessName -match $pp) { $suspProcs += "$($proc.ProcessName) (PID:$($proc.Id))"; break }
    }
  }
} catch {}
Write-Host "    -> $($suspProcs.Count) process dang ngo" -ForegroundColor $(if ($suspProcs.Count -gt 0) {'Red'} else {'Green'})

# ============================================================
# 6. GENERATE HTML REPORT
# ============================================================
Write-Host "  [6/6] Tao bao cao HTML..." -ForegroundColor Yellow

$totalApps = $apps.Count
$freeCount = ($apps | Where-Object { $_.LicType -eq 'free' }).Count
$commCount = ($apps | Where-Object { $_.LicType -eq 'commercial' }).Count
$trialCount = ($apps | Where-Object { $_.LicType -eq 'trial' }).Count
$crackCount = ($apps | Where-Object { $_.LicType -eq 'crack' }).Count
$unkCount = ($apps | Where-Object { $_.LicType -eq 'unknown' }).Count
$totalWarnings = $crackCount + $hostsBlocked.Count + $suspTasks.Count + $suspProcs.Count
$riskLevel = if ($crackCount -gt 0 -or $suspProcs.Count -gt 0) {'Critical'} elseif ($hostsBlocked.Count -gt 0 -or $suspTasks.Count -gt 0) {'High'} elseif ($winLic.Type -eq 'KMS/Volume') {'Medium'} else {'Clean'}

# Build app rows HTML
$appRowsHtml = ''
foreach ($a in $apps) {
  $badgeCls = switch ($a.LicType) { 'free'{'bg-green'} 'commercial'{'bg-orange'} 'trial'{'bg-yellow'} 'crack'{'bg-red'} default{'bg-gray'} }
  $badgeTxt = switch ($a.LicType) { 'free'{'Mien phi'} 'commercial'{'Thuong mai'} 'trial'{'Dung thu'} 'crack'{'CRACK'} default{'Chua ro'} }
  $sz = if ($a.SizeMB -gt 0) { if ($a.SizeMB -ge 1024) { "$([math]::Round($a.SizeMB/1024,1)) GB" } else { "$($a.SizeMB) MB" } } else { '-' }
  $rowCls = if ($a.LicType -eq 'crack') { ' class="crack-row"' } else { '' }
  $appRowsHtml += "<tr$rowCls><td class='app-name'>$([System.Web.HttpUtility]::HtmlEncode($a.Name))</td><td>$([System.Web.HttpUtility]::HtmlEncode($a.Publisher))</td><td class='center'>$($a.Version)</td><td class='center'>$sz</td><td class='center'><span class='badge $badgeCls'>$badgeTxt</span></td></tr>`n"
}

# Build warnings HTML
$warningsHtml = ''
if ($totalWarnings -eq 0) {
  $warningsHtml = '<div class="alert alert-clean"><span class="alert-icon">&#10004;</span> He thong sach - Khong phat hien dau hieu crack</div>'
} else {
  $warningsHtml = '<div class="alert alert-danger"><span class="alert-icon">&#9888;</span> Phat hien <strong>' + $totalWarnings + '</strong> canh bao!</div><div class="warn-list">'
  foreach ($ca in ($apps | Where-Object { $_.LicType -eq 'crack' })) {
    $warningsHtml += "<div class='warn-item critical'><span class='sev'>CRITICAL</span><strong>Crack Tool:</strong> $([System.Web.HttpUtility]::HtmlEncode($ca.Name))</div>"
  }
  foreach ($hb in $hostsBlocked) {
    $warningsHtml += "<div class='warn-item high'><span class='sev'>HIGH</span><strong>Hosts block:</strong> $hb</div>"
  }
  foreach ($st in $suspTasks) {
    $warningsHtml += "<div class='warn-item high'><span class='sev'>HIGH</span><strong>Task:</strong> $st</div>"
  }
  foreach ($sp in $suspProcs) {
    $warningsHtml += "<div class='warn-item critical'><span class='sev'>CRITICAL</span><strong>Process:</strong> $sp</div>"
  }
  $warningsHtml += '</div>'
}

# Windows license HTML
$winStatusCls = switch ($winLic.Status) { 'Licensed'{'bg-green'} 'Unlicensed'{'bg-red'} default{'bg-gray'} }
$winStatusTxt = switch ($winLic.Status) { 'Licensed'{'Da kich hoat'} 'Unlicensed'{'Chua kich hoat'} default{$winLic.Status} }
$winTypeCls = switch ($winLic.Type) { 'Retail'{'color:#3b82f6'} 'OEM'{'color:#22c55e'} 'KMS/Volume'{'color:#f59e0b'} default{''} }
$kmsHtml = if ($winLic.KmsServer) { "<div class='wl-item'><label>KMS Server</label><span style='color:#ef4444'>$($winLic.KmsServer)</span></div>" } else { '' }
$kmsWarnHtml = if ($winLic.KmsWarn) { "<div class='wl-item'><label>Canh bao</label><span style='color:#ef4444'>$($winLic.KmsWarn)</span></div>" } else { '' }

$riskCls = switch ($riskLevel) { 'Critical'{'risk-critical'} 'High'{'risk-high'} 'Medium'{'risk-medium'} default{'risk-clean'} }

$html = @"
<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>License Checker Report</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Inter',system-ui,sans-serif;background:#0a0a0f;color:#e8e8f0;line-height:1.6;min-height:100vh}
.container{max-width:1200px;margin:0 auto;padding:24px}
h1{font-size:1.6rem;font-weight:800;background:linear-gradient(135deg,#6366f1,#a855f7);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:4px}
.subtitle{color:#6a6a82;font-size:.85rem;margin-bottom:24px}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin-bottom:20px}
.stat{padding:16px;background:#12121a;border:1px solid rgba(255,255,255,.06);border-radius:12px;text-align:center}
.stat-val{font-size:2rem;font-weight:800;display:block}
.stat-lbl{font-size:.75rem;color:#6a6a82;text-transform:uppercase;letter-spacing:.5px}
.stat .c-blue{color:#3b82f6}.stat .c-green{color:#22c55e}.stat .c-orange{color:#f59e0b}.stat .c-red{color:#ef4444}.stat .c-gray{color:#6a6a82}
.card{background:#12121a;border:1px solid rgba(255,255,255,.06);border-radius:12px;padding:20px;margin-bottom:16px}
.card h2{font-size:1rem;font-weight:600;margin-bottom:12px;display:flex;align-items:center;gap:8px}
.alert{padding:14px 20px;border-radius:10px;font-size:.9rem;margin-bottom:16px;display:flex;align-items:center;gap:10px}
.alert-clean{background:rgba(34,197,94,.08);border:1px solid rgba(34,197,94,.25);color:#22c55e}
.alert-danger{background:rgba(239,68,68,.08);border:1px solid rgba(239,68,68,.25);color:#ef4444}
.alert-icon{font-size:1.3rem}
.warn-list{display:flex;flex-direction:column;gap:6px;margin-bottom:16px}
.warn-item{padding:10px 14px;background:#0a0a0f;border:1px solid rgba(255,255,255,.06);border-radius:8px;font-size:.85rem;display:flex;align-items:center;gap:10px}
.warn-item.critical{border-left:3px solid #ef4444}.warn-item.high{border-left:3px solid #f97316}
.sev{padding:2px 8px;border-radius:10px;font-size:.65rem;font-weight:700;text-transform:uppercase;flex-shrink:0}
.critical .sev{background:rgba(239,68,68,.15);color:#ef4444}.high .sev{background:rgba(249,115,22,.15);color:#f97316}
.risk-badge{display:inline-block;padding:4px 14px;border-radius:20px;font-size:.75rem;font-weight:700;text-transform:uppercase}
.risk-critical{background:rgba(239,68,68,.15);color:#ef4444}.risk-high{background:rgba(249,115,22,.15);color:#f97316}
.risk-medium{background:rgba(245,158,11,.15);color:#f59e0b}.risk-clean{background:rgba(34,197,94,.15);color:#22c55e}
.wl-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px;margin-top:12px}
.wl-item label{display:block;font-size:.7rem;color:#6a6a82;text-transform:uppercase;letter-spacing:.5px;margin-bottom:2px}
.wl-item span{font-size:.88rem;font-weight:500}
.badge{padding:3px 10px;border-radius:12px;font-size:.72rem;font-weight:600;white-space:nowrap}
.bg-green{background:rgba(34,197,94,.12);color:#22c55e}.bg-orange{background:rgba(245,158,11,.12);color:#f59e0b}
.bg-yellow{background:rgba(234,179,8,.12);color:#eab308}.bg-red{background:rgba(239,68,68,.15);color:#ef4444}
.bg-gray{background:rgba(160,160,184,.08);color:#6a6a82}
table{width:100%;border-collapse:collapse;font-size:.85rem}
th{text-align:left;padding:10px 12px;border-bottom:1px solid rgba(255,255,255,.08);color:#6a6a82;font-size:.75rem;text-transform:uppercase;letter-spacing:.5px;font-weight:600;position:sticky;top:0;background:#12121a;z-index:1}
td{padding:10px 12px;border-bottom:1px solid rgba(255,255,255,.04)}
tr:hover td{background:rgba(255,255,255,.02)}
.crack-row td{background:rgba(239,68,68,.04)}.crack-row:hover td{background:rgba(239,68,68,.08)}
.app-name{font-weight:600}.center{text-align:center}
.toolbar{display:flex;gap:10px;margin-bottom:12px;flex-wrap:wrap;align-items:center}
.toolbar input{flex:1;min-width:200px;padding:8px 14px;background:#0a0a0f;border:1px solid rgba(255,255,255,.08);border-radius:8px;color:#e8e8f0;font-size:.85rem;outline:none}
.toolbar input:focus{border-color:#6366f1}
.toolbar select{padding:8px 12px;background:#0a0a0f;border:1px solid rgba(255,255,255,.08);border-radius:8px;color:#e8e8f0;font-size:.85rem;outline:none}
.footer{text-align:center;padding:20px;color:#6a6a82;font-size:.78rem;border-top:1px solid rgba(255,255,255,.04);margin-top:24px}
@media(max-width:768px){.stats{grid-template-columns:repeat(2,1fr)}th:nth-child(3),td:nth-child(3),th:nth-child(4),td:nth-child(4){display:none}}
</style>
</head>
<body>
<div class="container">
<div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:8px">
<div><h1>&#128737; License Checker Report</h1><div class="subtitle">$env:COMPUTERNAME &bull; $osCaption &bull; $(Get-Date -Format 'dd/MM/yyyy HH:mm')</div></div>
<span class="risk-badge $riskCls">$riskLevel</span>
</div>

<div class="stats">
<div class="stat"><span class="stat-val c-blue">$totalApps</span><span class="stat-lbl">Tong ung dung</span></div>
<div class="stat"><span class="stat-val c-green">$freeCount</span><span class="stat-lbl">Mien phi / OSS</span></div>
<div class="stat"><span class="stat-val c-orange">$commCount</span><span class="stat-lbl">Thuong mai</span></div>
<div class="stat"><span class="stat-val c-gray">$unkCount</span><span class="stat-lbl">Chua ro</span></div>
<div class="stat"><span class="stat-val c-red">$totalWarnings</span><span class="stat-lbl">Canh bao Crack</span></div>
</div>

$warningsHtml

<div class="card">
<h2>&#127987; Ban quyen Windows <span class="badge $winStatusCls" style="margin-left:auto">$winStatusTxt</span></h2>
<div class="wl-grid">
<div class="wl-item"><label>San pham</label><span>$($winLic.Product)</span></div>
<div class="wl-item"><label>Product Key</label><span>XXXXX-$($winLic.Key)</span></div>
<div class="wl-item"><label>Kieu kich hoat</label><span style="$winTypeCls;font-weight:600">$($winLic.Type)</span></div>
$kmsHtml$kmsWarnHtml
<div class="wl-item"><label>Kenh</label><span>$($winLic.Desc)</span></div>
</div>
</div>

<div class="card">
<h2>&#128230; Danh sach phan mem ($totalApps)</h2>
<div class="toolbar">
<input type="text" id="search" placeholder="Tim kiem phan mem..." oninput="filterTable()">
<select id="filterType" onchange="filterTable()">
<option value="">Tat ca</option><option value="free">Mien phi</option><option value="commercial">Thuong mai</option><option value="trial">Dung thu</option><option value="crack">Crack</option><option value="unknown">Chua ro</option>
</select>
</div>
<div style="max-height:600px;overflow-y:auto;border-radius:8px">
<table id="appTable">
<thead><tr><th>Ten ung dung</th><th>Nha phat hanh</th><th>Phien ban</th><th>Dung luong</th><th class="center">Trang thai</th></tr></thead>
<tbody>$appRowsHtml</tbody>
</table>
</div>
<div id="countInfo" style="text-align:center;padding:10px;color:#6a6a82;font-size:.8rem"></div>
</div>

<div class="footer">License Checker v1.0 &bull; Tao tu dong boi PowerShell &bull; $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</div>
</div>
<script>
function filterTable(){
  var s=document.getElementById('search').value.toLowerCase();
  var f=document.getElementById('filterType').value;
  var rows=document.querySelectorAll('#appTable tbody tr');
  var shown=0;
  rows.forEach(function(r){
    var name=r.cells[0].textContent.toLowerCase();
    var pub=r.cells[1].textContent.toLowerCase();
    var badge=r.querySelector('.badge');
    var type=badge?badge.textContent.toLowerCase():'';
    var typeMap={'mien phi':'free','thuong mai':'commercial','dung thu':'trial','crack':'crack','chua ro':'unknown'};
    var rowType=typeMap[type]||'unknown';
    var matchSearch=!s||name.includes(s)||pub.includes(s);
    var matchFilter=!f||rowType===f;
    r.style.display=(matchSearch&&matchFilter)?'':'none';
    if(matchSearch&&matchFilter)shown++;
  });
  document.getElementById('countInfo').textContent='Hien thi '+shown+'/'+rows.length+' ung dung';
}
filterTable();
</script>
</body>
</html>
"@

$reportPath = Join-Path $env:TEMP "LicenseChecker-Report.html"
Add-Type -AssemblyName System.Web
$html | Out-File -FilePath $reportPath -Encoding UTF8 -Force

Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "    Hoan tat! Dang mo bao cao..." -ForegroundColor Green
Write-Host "    $reportPath" -ForegroundColor Gray
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""

Start-Process $reportPath
