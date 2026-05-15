[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$results = @()
$crackWarnings = @()

# ============================================================
# 1. SCAN INSTALLED SOFTWARE FROM REGISTRY
# ============================================================
$regPaths = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

foreach ($regPath in $regPaths) {
  try {
    $items = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
    foreach ($item in $items) {
      if ($item.DisplayName -and $item.DisplayName.Trim() -ne '') {
        $licenseType = 'Unknown'
        $licenseStatus = 'Unknown'
        $crackRisk = 'None'
        $crackDetails = ''

        $name = $item.DisplayName
        $publisher = if ($item.Publisher) { $item.Publisher } else { 'N/A' }
        $version = if ($item.DisplayVersion) { $item.DisplayVersion } else { 'N/A' }
        $installDate = if ($item.InstallDate) { $item.InstallDate } else { 'N/A' }
        $installLocation = if ($item.InstallLocation) { $item.InstallLocation } else { 'N/A' }
        $size = if ($item.EstimatedSize) { [math]::Round($item.EstimatedSize / 1024, 2) } else { 0 }

        $isFree = $false
        $isCommercial = $false
        $isTrial = $false

        # === CRACK TOOL DETECTION ===
        $crackToolPatterns = @(
          'KMSPico', 'KMSAuto', 'KMS Tools', 'KMS Activator', 'KMS_VL_ALL',
          'Re-Loader', 'ReLoader', 'Microsoft Toolkit', 'AAct', 'KMSCleaner',
          'RemoveWAT', 'WAT Remover', 'Windows Loader', 'Daz Loader',
          'HWIDGEN', 'HWIDGen', 'MAS ', 'Microsoft Activation Script',
          'W10 Digital', 'Digital License', 'ConsoleAct',
          'Mini-KMS', 'MiniKMS', 'AutoKMS', 'Auto KMS',
          'Ratiborus', 'PainteR', 'IDM Crack', 'Universal Adobe Patcher',
          'AMTEmu', 'AMT Emulator', 'Adobe Zii', 'GenP', 'CCMaker',
          'Xforce', 'X-Force', 'KeyGen', 'Keygen', 'Patch ', 'Patcher',
          'Crack', 'Cracked', 'Activator', 'Activation',
          'ChingLiu', 'TeamOS', 'CracksHash', 'FileCR'
        )

        foreach ($ct in $crackToolPatterns) {
          if ($name -match [regex]::Escape($ct)) {
            $crackRisk = 'High'
            $crackDetails = "Crack tool detected: matches pattern '$ct'"
            $licenseType = 'Crack Tool'
            $licenseStatus = 'CRACK TOOL DETECTED'
            $crackWarnings += [PSCustomObject]@{
              Type = 'CrackTool'
              Severity = 'Critical'
              App = $name
              Detail = "Known crack/activation tool found in installed programs"
            }
            break
          }
        }

        # === Normal classification ===
        if ($crackRisk -eq 'None') {
          $freePatterns = @('Free', 'Open Source', 'GPL', 'MIT', 'Apache', 'Mozilla', 'GNU', 'Community', 'Freeware')
          foreach ($p in $freePatterns) {
            if ($name -match $p -or $publisher -match $p) { $isFree = $true; break }
          }

          $commercialPubs = @('Microsoft', 'Adobe', 'Autodesk', 'VMware', 'JetBrains', 'Sublime', 'Telerik', 'DevExpress', 'Syncfusion')
          foreach ($p in $commercialPubs) {
            if ($publisher -match $p) { $isCommercial = $true; break }
          }

          $trialPatterns = @('Trial', 'Demo', 'Evaluation', 'Preview')
          foreach ($p in $trialPatterns) {
            if ($name -match $p) { $isTrial = $true; break }
          }

          $knownFree = @('Firefox', 'Chrome', 'Chromium', 'VLC', 'GIMP', 'Audacity', '7-Zip', 'Visual Studio Code', 'VS Code', 'Git', 'Python', 'Node', 'Java', 'OpenJDK', 'LibreOffice', 'FileZilla', 'PuTTY', 'WinSCP', 'OBS Studio', 'Blender', 'Inkscape', 'KeePass', 'Telegram', 'Signal', 'Discord', 'Slack', 'Zoom', 'Steam', 'Epic Games', 'PowerShell', 'Redistributable', 'Runtime', 'SDK', 'Windows Terminal', 'WSL', 'ShareX', 'qBittorrent', 'HandBrake', 'Krita', 'Thunderbird', 'Brave', 'Vivaldi', 'Opera', 'Edge')
          foreach ($kf in $knownFree) {
            if ($name -match [regex]::Escape($kf)) { $isFree = $true; $isCommercial = $false; break }
          }

          $knownCommercial = @('Microsoft Office', 'Microsoft 365', 'Adobe Photoshop', 'Adobe Illustrator', 'Adobe Premiere', 'Adobe Creative', 'Adobe Acrobat Pro', 'Adobe After Effects', 'AutoCAD', 'CorelDRAW', 'WinRAR', 'Internet Download Manager', 'Sublime Text', 'Total Commander', 'Camtasia', 'Snagit', 'MATLAB', 'Norton', 'Kaspersky', 'Bitdefender', 'ESET', 'Avast Premium', 'VMware Workstation', 'Navicat', 'DataGrip', 'IntelliJ IDEA Ultimate', 'PhpStorm', 'WebStorm', 'PyCharm Professional', 'Rider', 'ReSharper', 'SQL Server', 'Visio', 'Project Professional')
          foreach ($kc in $knownCommercial) {
            if ($name -match [regex]::Escape($kc)) { $isCommercial = $true; $isFree = $false; break }
          }

          if ($isTrial) {
            $licenseType = 'Trial/Demo'
            $licenseStatus = 'Trial'
          } elseif ($isFree) {
            $licenseType = 'Free/Open Source'
            $licenseStatus = 'Free'
          } elseif ($isCommercial) {
            $licenseType = 'Commercial'
            $licenseStatus = 'Needs Verification'
          } else {
            $licenseType = 'Unclassified'
            $licenseStatus = 'Unknown'
          }
        }

        # === CHECK DIGITAL SIGNATURE for commercial apps ===
        $sigStatus = 'N/A'
        if ($isCommercial -and $installLocation -and $installLocation -ne 'N/A' -and (Test-Path $installLocation -ErrorAction SilentlyContinue)) {
          try {
            $exeFiles = Get-ChildItem -Path $installLocation -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 3
            foreach ($exe in $exeFiles) {
              $sig = Get-AuthenticodeSignature -FilePath $exe.FullName -ErrorAction SilentlyContinue
              if ($sig) {
                $sigStatus = $sig.Status.ToString()
                if ($sig.Status -ne 'Valid') {
                  $crackRisk = if ($crackRisk -eq 'High') { 'High' } else { 'Medium' }
                  $crackDetails += "Digital signature issue: $($exe.Name) = $sigStatus. "
                }
                break
              }
            }
          } catch {}
        }

        $uns = ''
        if ($item.UninstallString) { $uns = $item.UninstallString }

        $obj = [PSCustomObject]@{
          Name = $name
          Publisher = $publisher
          Version = $version
          InstallDate = $installDate
          InstallLocation = $installLocation
          SizeMB = $size
          LicenseType = $licenseType
          LicenseStatus = $licenseStatus
          CrackRisk = $crackRisk
          CrackDetails = $crackDetails
          SignatureStatus = $sigStatus
          UninstallString = $uns
        }

        $results += $obj
      }
    }
  } catch {}
}

$results = $results | Sort-Object Name -Unique

# ============================================================
# 2. WINDOWS LICENSE - DEEP CHECK
# ============================================================
$windowsLicense = @{}
try {
  $wmiLicense = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($wmiLicense) {
    $windowsLicense['productName'] = $wmiLicense.Name
    $windowsLicense['description'] = $wmiLicense.Description
    $statusText = switch ($wmiLicense.LicenseStatus) {
      0 { 'Unlicensed' }
      1 { 'Licensed' }
      2 { 'OOBGrace' }
      3 { 'OOTGrace' }
      4 { 'NonGenuineGrace' }
      5 { 'Notification' }
      6 { 'ExtendedGrace' }
      default { 'Unknown' }
    }
    $windowsLicense['licenseStatus'] = $statusText
    $windowsLicense['partialKey'] = $wmiLicense.PartialProductKey
    $windowsLicense['gracePeriod'] = $wmiLicense.GracePeriodRemaining
    $windowsLicense['licenseChannel'] = $wmiLicense.Description

    # KMS detection
    $isKMS = $false
    $desc = $wmiLicense.Description
    if ($desc -match 'VOLUME_KMSCLIENT' -or $desc -match 'KMS' -or $desc -match 'VOLUME') {
      $isKMS = $true
      $windowsLicense['activationType'] = 'KMS/Volume'
    } elseif ($desc -match 'RETAIL') {
      $windowsLicense['activationType'] = 'Retail'
    } elseif ($desc -match 'OEM') {
      $windowsLicense['activationType'] = 'OEM'
    } else {
      $windowsLicense['activationType'] = 'Unknown'
    }

    # Check KMS server
    try {
      $kmsKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -ErrorAction SilentlyContinue
      if ($kmsKey.KeyManagementServiceName) {
        $windowsLicense['kmsServer'] = $kmsKey.KeyManagementServiceName
        $windowsLicense['kmsPort'] = $kmsKey.KeyManagementServicePort
        if ($kmsKey.KeyManagementServiceName -match '127\.|localhost|0\.0\.0\.|fake|kms\.|vlmcs') {
          $windowsLicense['kmsWarning'] = 'Suspicious KMS server detected'
          $crackWarnings += [PSCustomObject]@{
            Type = 'KMSActivation'
            Severity = 'High'
            App = 'Windows'
            Detail = "Suspicious KMS server: $($kmsKey.KeyManagementServiceName)"
          }
        }
      }
    } catch {}

    # If KMS without corporate environment indicator
    if ($isKMS) {
      try {
        $domain = (Get-CimInstance Win32_ComputerSystem).Domain
        if (-not $domain -or $domain -eq 'WORKGROUP') {
          $windowsLicense['domainWarning'] = 'KMS activation detected but PC is not domain-joined'
          $crackWarnings += [PSCustomObject]@{
            Type = 'KMSNoDomain'
            Severity = 'Medium'
            App = 'Windows'
            Detail = "KMS/Volume activation used but computer not joined to a domain (Domain: $domain)"
          }
        }
      } catch {}
    }
  }
} catch {}

# ============================================================
# 3. CHECK HOSTS FILE FOR BLOCKED ACTIVATION SERVERS
# ============================================================
$hostsWarnings = @()
try {
  $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
  if (Test-Path $hostsPath) {
    $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
    $blockedDomains = @(
      'activation.sls.microsoft.com',
      'validation.sls.microsoft.com',
      'go.microsoft.com',
      'mpa.one.microsoft.com',
      'sls.update.microsoft.com',
      'genuine.microsoft.com',
      'ols.officeapps.live.com',
      'activate.adobe.com',
      'practivate.adobe.com',
      'lmlicenses.wip4.adobe.com',
      'lm.licenses.adobe.com',
      'na1r.services.adobe.com',
      'hlrcv.stage.adobe.com',
      'adobe-dns.adobe.com',
      'ereg.wip3.adobe.com',
      'activate.wip3.adobe.com',
      'wip3.adobe.com',
      '3dns-3.adobe.com',
      '3dns-2.adobe.com',
      'ereg.adobe.com',
      'activate.wip.adobe.com',
      'wwis-dubc1-vip60.adobe.com',
      'adobeereg.com',
      'jetbrains.com',
      'account.jetbrains.com'
    )

    foreach ($line in $hostsContent) {
      $trimmed = $line.Trim()
      if ($trimmed -and -not $trimmed.StartsWith('#')) {
        foreach ($bd in $blockedDomains) {
          if ($trimmed -match [regex]::Escape($bd)) {
            $hostsWarnings += [PSCustomObject]@{
              BlockedDomain = $bd
              HostsLine = $trimmed
            }
            $crackWarnings += [PSCustomObject]@{
              Type = 'HostsBlock'
              Severity = 'High'
              App = if ($bd -match 'adobe') { 'Adobe Products' } elseif ($bd -match 'microsoft') { 'Microsoft Products' } elseif ($bd -match 'jetbrains') { 'JetBrains Products' } else { 'Unknown' }
              Detail = "Activation server blocked in hosts file: $bd"
            }
          }
        }
      }
    }
  }
} catch {}

# ============================================================
# 4. CHECK FOR CRACK-RELATED SCHEDULED TASKS
# ============================================================
$suspiciousTasks = @()
try {
  $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
  $suspTaskPatterns = @('KMS', 'AutoKMS', 'KMSAuto', 'Activat', 'ReArm', 'Re-Arm', 'AAct', 'ConsoleAct', 'vlmcs', 'YOURHOST')
  foreach ($task in $tasks) {
    foreach ($sp in $suspTaskPatterns) {
      if ($task.TaskName -match $sp -or $task.TaskPath -match $sp) {
        $suspiciousTasks += [PSCustomObject]@{
          TaskName = $task.TaskName
          TaskPath = $task.TaskPath
          State = $task.State.ToString()
        }
        $crackWarnings += [PSCustomObject]@{
          Type = 'ScheduledTask'
          Severity = 'High'
          App = 'System'
          Detail = "Suspicious scheduled task: $($task.TaskName) at $($task.TaskPath)"
        }
        break
      }
    }
  }
} catch {}

# ============================================================
# 5. CHECK FOR CRACK-RELATED PROCESSES
# ============================================================
$suspiciousProcesses = @()
try {
  $procs = Get-Process -ErrorAction SilentlyContinue
  $suspProcPatterns = @('KMSPico', 'KMSAuto', 'AutoKMS', 'KMS Service', 'vlmcsd', 'AAct', 'ConsoleAct', 'w10digital', 'hwidgen', 'MAS')
  foreach ($proc in $procs) {
    foreach ($sp in $suspProcPatterns) {
      if ($proc.ProcessName -match $sp) {
        $suspiciousProcesses += [PSCustomObject]@{
          ProcessName = $proc.ProcessName
          PID = $proc.Id
          Path = $proc.Path
        }
        $crackWarnings += [PSCustomObject]@{
          Type = 'SuspiciousProcess'
          Severity = 'Critical'
          App = 'System'
          Detail = "Suspicious process running: $($proc.ProcessName) (PID: $($proc.Id))"
        }
        break
      }
    }
  }
} catch {}

# ============================================================
# 6. CHECK FOR KNOWN CRACK FILES IN COMMON LOCATIONS
# ============================================================
$crackFilesFound = @()
$crackSearchPaths = @(
  "$env:ProgramFiles",
  "${env:ProgramFiles(x86)}",
  "$env:APPDATA",
  "$env:LOCALAPPDATA",
  "$env:TEMP",
  "$env:PUBLIC\Desktop"
)
$crackFileNames = @('KMSPico', 'KMSAuto', 'AutoKMS', 'Re-Loader', 'amtemu', 'amt_emulator', 'adobe.snr.patch', 'Universal Adobe Patcher', 'GenP', 'painter.exe', 'vlmcsd', 'AAct.exe', 'ConsoleAct')

foreach ($searchPath in $crackSearchPaths) {
  try {
    if (Test-Path $searchPath) {
      foreach ($cfn in $crackFileNames) {
        $found = Get-ChildItem -Path $searchPath -Recurse -Depth 2 -Filter "*$cfn*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
          $crackFilesFound += [PSCustomObject]@{
            FileName = $found.Name
            FullPath = $found.FullName
            LastModified = $found.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
          }
          $crackWarnings += [PSCustomObject]@{
            Type = 'CrackFile'
            Severity = 'Critical'
            App = 'System'
            Detail = "Crack-related file found: $($found.FullName)"
          }
        }
      }
    }
  } catch {}
}

# ============================================================
# 7. CHECK OFFICE / VISIO / PROJECT ACTIVATION (DEEP)
# ============================================================
$officeLicense = @{}
try {
  # Scan ALL Microsoft products (Office, Visio, Project, etc.)
  $allMsProducts = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction SilentlyContinue | Where-Object {
    ($_.Name -match 'Office|Visio|Project' -and $_.PartialProductKey) -or
    ($_.ApplicationID -eq '0ff1ce15-a989-479d-af46-f275c6370663' -and $_.PartialProductKey)
  }
  if ($allMsProducts) {
    $officeList = @()
    foreach ($op in $allMsProducts) {
      $offStatus = switch ($op.LicenseStatus) {
        0 { 'Unlicensed' }
        1 { 'Licensed' }
        2 { 'OOBGrace' }
        3 { 'OOTGrace' }
        4 { 'NonGenuineGrace' }
        5 { 'Notification' }
        6 { 'ExtendedGrace' }
        default { 'Unknown' }
      }
      $offItem = @{
        name = $op.Name
        status = $offStatus
        partialKey = $op.PartialProductKey
        channel = $op.Description
        gracePeriod = $op.GracePeriodRemaining
        licenseFamily = $op.LicenseFamily
        redFlags = @()
      }

      $isKmsVol = ($op.Description -match 'VOLUME' -or $op.Description -match 'KMS' -or $op.Description -match 'VOLUME_KMSCLIENT')

      if ($isKmsVol) {
        $offItem['activationType'] = 'KMS/Volume'
        try {
          $domain = (Get-CimInstance Win32_ComputerSystem).Domain
          if (-not $domain -or $domain -eq 'WORKGROUP') {
            $offItem['warning'] = 'KMS activation but not domain-joined'
            $offItem.redFlags += 'KMS/Volume nhung may khong gia nhap domain'
            $sev = if ($op.Name -match 'Visio|Project') { 'High' } else { 'Medium' }
            $crackWarnings += [PSCustomObject]@{
              Type = 'OfficeKMS'
              Severity = $sev
              App = $op.Name
              Detail = "$($op.Name) su dung KMS/Volume activation nhung PC khong gia nhap domain - nghi van crack"
            }
          }
        } catch {}
      } elseif ($op.Description -match 'RETAIL') {
        $offItem['activationType'] = 'Retail'
      } elseif ($op.Description -match 'MAK') {
        $offItem['activationType'] = 'MAK'
      } elseif ($op.Description -match 'Subscription') {
        $offItem['activationType'] = 'Subscription'
      } else {
        $offItem['activationType'] = 'Unknown'
      }

      # === GVLK (Generic Volume License Key) Detection ===
      # These keys are ALWAYS indicators of KMS crack when used outside enterprise environment
      $gvlkDatabase = @{
        # Office 2021 LTSC GVLK
        'FXYTK' = 'Office LTSC Pro Plus 2021'
        '6F7TH' = 'Office LTSC Standard 2021'
        'KNH8D' = 'Visio LTSC Pro 2021'
        'MJVNY' = 'Visio LTSC Std 2021'
        'FQHGJ' = 'Project LTSC Pro 2021'
        'J2JDC' = 'Project LTSC Std 2021'
        # Office 2019 GVLK
        'VQ9DP' = 'Office Pro Plus 2019'
        '869NQ' = 'Office Standard 2019'
        '9BGNQ' = 'Visio Pro 2019'
        '7TQNQ' = 'Visio Std 2019'
        'B4NPR' = 'Project Pro 2019'
        'C4F7P' = 'Project Std 2019'
        # Office 2016 GVLK
        'WFG99' = 'Office Pro Plus 2016'
        'JNRGM' = 'Office Standard 2016'
        'PD3PC' = 'Visio Pro 2016'
        '7WHWN' = 'Visio Std 2016'
        'YC7DK' = 'Project Pro 2016'
        'GNFHQ' = 'Project Std 2016'
        # Office 365
        'NK7R4' = 'Office 365 ProPlus'
        'R69KK' = 'Office 365 Business'
        # Office 2024 GVLK
        'XJ2XN' = 'Office LTSC Pro Plus 2024'
        'V28N4' = 'Office LTSC Standard 2024'
        'B7TN8' = 'Visio LTSC Pro 2024'
        '9VV2F' = 'Project LTSC Pro 2024'
      }

      $pk = $op.PartialProductKey
      if ($pk -and $gvlkDatabase.ContainsKey($pk)) {
        $offItem.redFlags += "Product key cuoi '$pk' la GVLK (Generic Volume License Key) cua $($gvlkDatabase[$pk]) -> crack KMS"
        $offItem['gvlkMatch'] = $gvlkDatabase[$pk]
        $crackWarnings += [PSCustomObject]@{
          Type = 'GVLKDetected'
          Severity = 'Critical'
          App = $op.Name
          Detail = "GVLK detected: Key cuoi '$pk' la key generic cho '$($gvlkDatabase[$pk])' -> 100% kich hoat bang KMS crack"
        }
      }

      # === Grace period anomaly check ===
      if ($op.GracePeriodRemaining -eq 0 -and $isKmsVol -and $offStatus -eq 'Licensed') {
        $offItem.redFlags += 'Grace period = 0 phut voi KMS -> dau hieu crack (KMS server gia lap)'
        $crackWarnings += [PSCustomObject]@{
          Type = 'GracePeriodAnomaly'
          Severity = 'High'
          App = $op.Name
          Detail = "$($op.Name): Grace period = 0 voi KMS activation -> dau hieu KMS crack"
        }
      }

      # === NonGenuine / Notification status ===
      if ($offStatus -eq 'NonGenuineGrace' -or $offStatus -eq 'Notification') {
        $offItem.redFlags += "Trang thai '$offStatus' - Microsoft da phat hien ban quyen khong hop le"
        $crackWarnings += [PSCustomObject]@{
          Type = 'NonGenuine'
          Severity = 'Critical'
          App = $op.Name
          Detail = "$($op.Name) o trang thai '$offStatus' - Microsoft xac nhan ban quyen KHONG hop le"
        }
      }

      $officeList += $offItem
    }
    $officeLicense['products'] = $officeList
  }
} catch {}

# ============================================================
# 7b. DEEP DIGITAL SIGNATURE SCAN FOR COMMERCIAL APPS
# ============================================================
$signatureResults = @()
$commercialApps = $results | Where-Object { $_.LicenseType -eq 'Commercial' -and $_.InstallLocation -and $_.InstallLocation -ne 'N/A' }
foreach ($app in $commercialApps) {
  try {
    $loc = $app.InstallLocation
    if (-not (Test-Path $loc -ErrorAction SilentlyContinue)) { continue }

    # Find main EXE files (up to 5)
    $exeFiles = Get-ChildItem -Path $loc -Filter '*.exe' -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 5
    $hasInvalidSig = $false
    $hasModifiedExe = $false
    $sigDetails = @()

    foreach ($exe in $exeFiles) {
      $sig = Get-AuthenticodeSignature -FilePath $exe.FullName -ErrorAction SilentlyContinue
      if ($sig) {
        $sigStr = $sig.Status.ToString()
        if ($sigStr -ne 'Valid') {
          $hasInvalidSig = $true
          $sigDetails += "$($exe.Name): $sigStr"
          # Check signer mismatch (common crack indicator)
          if ($sig.SignerCertificate) {
            $signerName = $sig.SignerCertificate.Subject
            if ($app.Publisher -and $app.Publisher -ne 'N/A') {
              $pubLower = $app.Publisher.ToLower()
              $sigLower = $signerName.ToLower()
              if (-not ($sigLower -match [regex]::Escape($pubLower.Split(' ')[0]))) {
                $hasModifiedExe = $true
                $sigDetails += "Signer KHONG KHOP voi publisher: Signer='$signerName', Publisher='$($app.Publisher)'"
              }
            }
          }
        } elseif ($sigStr -eq 'NotSigned') {
          # Unsigned commercial EXE is suspicious
          $hasInvalidSig = $true
          $sigDetails += "$($exe.Name): Khong co chu ky so"
        }
      }
    }

    if ($hasInvalidSig -or $hasModifiedExe) {
      $severity = if ($hasModifiedExe) { 'High' } else { 'Medium' }
      $app.CrackRisk = if ($app.CrackRisk -eq 'High' -or $app.CrackRisk -eq 'Critical') { $app.CrackRisk } else { $severity }
      $app.CrackDetails = ($app.CrackDetails + ' Chu ky so bat thuong: ' + ($sigDetails -join '; ')).Trim()
      $signatureResults += [PSCustomObject]@{
        App = $app.Name
        Issues = $sigDetails
        HasModifiedExe = $hasModifiedExe
      }
      $crackWarnings += [PSCustomObject]@{
        Type = 'DigitalSignature'
        Severity = $severity
        App = $app.Name
        Detail = "Chu ky so bat thuong tren file EXE: $($sigDetails -join '; ')"
      }
    }
  } catch {}
}

# ============================================================
# 7c. REGISTRY TAMPERING CHECK (CRACK INDICATORS)
# ============================================================
$regTamperWarnings = @()

# Check if Office OSPP auto-renewal is disabled (common crack technique)
try {
  $osppPaths = @(
    'HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform',
    'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
  )
  foreach ($osppPath in $osppPaths) {
    if (Test-Path $osppPath) {
      $ospp = Get-ItemProperty $osppPath -ErrorAction SilentlyContinue
      if ($ospp.KeyManagementServiceName) {
        $regTamperWarnings += "Office KMS Server configured: $($ospp.KeyManagementServiceName)"
        if ($ospp.KeyManagementServiceName -match '127\.|localhost|0\.0\.0\.|kms\.|vlmcs') {
          $crackWarnings += [PSCustomObject]@{
            Type = 'RegistryTamper'
            Severity = 'Critical'
            App = 'Microsoft Office'
            Detail = "Office KMS server dang ngo trong registry: $($ospp.KeyManagementServiceName)"
          }
        }
      }
    }
  }
} catch {}

# Check for disabled Windows Defender Real-time (some cracks require this)
try {
  $defenderKey = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -ErrorAction SilentlyContinue
  if ($defenderKey.DisableRealtimeMonitoring -eq 1) {
    $regTamperWarnings += 'Windows Defender Real-Time Protection da bi TAT qua Group Policy'
    $crackWarnings += [PSCustomObject]@{
      Type = 'DefenderDisabled'
      Severity = 'Medium'
      App = 'System'
      Detail = 'Windows Defender Real-Time Protection bi tat qua GP - thuong thay khi cai crack'
    }
  }
} catch {}

# Check for tampered Office licensing tokens
try {
  $tokenPaths = @(
    "$env:ProgramData\Microsoft\OfficeSoftwareProtectionPlatform\tokens.dat",
    "$env:LOCALAPPDATA\Microsoft\Office\Licenses"
  )
  foreach ($tp in $tokenPaths) {
    if (Test-Path $tp -ErrorAction SilentlyContinue) {
      $tokenInfo = Get-Item $tp -ErrorAction SilentlyContinue
      if ($tokenInfo -and $tokenInfo.PSIsContainer) {
        $licFiles = Get-ChildItem $tp -Recurse -ErrorAction SilentlyContinue
        if ($licFiles.Count -eq 0) {
          $regTamperWarnings += "Office license folder ton tai nhung rong: $tp"
        }
      }
    }
  }
} catch {}

# Check for Visio/Project specific registry entries that indicate piracy
try {
  $officeRegPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Office\16.0\Visio\InstallRoot',
    'HKLM:\SOFTWARE\Microsoft\Office\16.0\MS Project\InstallRoot',
    'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
  )
  foreach ($orp in $officeRegPaths) {
    if (Test-Path $orp) {
      $offReg = Get-ItemProperty $orp -ErrorAction SilentlyContinue
      if ($offReg.Path) {
        $mainExe = $null
        if ($orp -match 'Visio') {
          $mainExe = Join-Path $offReg.Path 'VISIO.EXE'
        } elseif ($orp -match 'Project') {
          $mainExe = Join-Path $offReg.Path 'WINPROJ.EXE'
        }
        if ($mainExe -and (Test-Path $mainExe -ErrorAction SilentlyContinue)) {
          $sig = Get-AuthenticodeSignature -FilePath $mainExe -ErrorAction SilentlyContinue
          if ($sig -and $sig.Status -ne 'Valid') {
            $appName = if ($orp -match 'Visio') { 'Microsoft Visio' } else { 'Microsoft Project' }
            $crackWarnings += [PSCustomObject]@{
              Type = 'ModifiedExe'
              Severity = 'Critical'
              App = $appName
              Detail = "File chinh $($mainExe | Split-Path -Leaf) co chu ky so '$($sig.Status)' - file da bi thay doi (crack/patch)"
            }
          }
        }
      }
    }
  }
} catch {}

# Check Office C2R product configuration for licensing anomalies
try {
  $c2rConfig = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
  if ($c2rConfig) {
    $officeLicense['c2rChannel'] = $c2rConfig.CDNBaseUrl
    $officeLicense['c2rProductIds'] = $c2rConfig.ProductReleaseIds
    # Check if using Volume channel without enterprise environment
    if ($c2rConfig.ProductReleaseIds -and $c2rConfig.ProductReleaseIds -match 'Volume') {
      try {
        $domain = (Get-CimInstance Win32_ComputerSystem).Domain
        if (-not $domain -or $domain -eq 'WORKGROUP') {
          $crackWarnings += [PSCustomObject]@{
            Type = 'C2RVolume'
            Severity = 'High'
            App = 'Office (C2R)'
            Detail = "Office Click-to-Run su dung kenh Volume ('$($c2rConfig.ProductReleaseIds)') nhung may khong gia nhap domain"
          }
        }
      } catch {}
    }
    # Visio or Project installed as add-on without proper subscription
    if ($c2rConfig.ProductReleaseIds -match 'VisioProVolume|VisioStdVolume|ProjectProVolume|ProjectStdVolume') {
      $matchedProducts = [regex]::Matches($c2rConfig.ProductReleaseIds, '(Visio|Project)(Pro|Std)(Volume|Retail)') | ForEach-Object { $_.Value }
      foreach ($mp in $matchedProducts) {
        if ($mp -match 'Volume') {
          try {
            $domain = (Get-CimInstance Win32_ComputerSystem).Domain
            if (-not $domain -or $domain -eq 'WORKGROUP') {
              $appDisplayName = if ($mp -match 'Visio') { 'Microsoft Visio' } else { 'Microsoft Project' }
              $crackWarnings += [PSCustomObject]@{
                Type = 'ProductVolume'
                Severity = 'High'
                App = $appDisplayName
                Detail = "$appDisplayName cai dat qua kenh Volume ('$mp') nhung may khong trong domain - nghi van crack"
              }
            }
          } catch {}
        }
      }
    }
  }
} catch {}

# ============================================================
# 8. CROSS-ANALYSIS: Phan tich cheo cac dau hieu
# ============================================================
$publicKmsServers = @('185.213.174.199','107.175.77.7','kms.digiboy.ir','kms.lotro.cc','kms8.msguides.com','kms9.msguides.com','kms.zhuxiaole.org','kms.loli.beer','kms.cangshui.net','kms.library.hk','s8.uk.to','s9.us','hq1.chinancce.com')
$genericVLKeys = @('W269N','VK7JG','YNMGQ','8DVY4','3V66T','MH37W','TX9XD','3KHY7','7HNRX','NPPR9','WGGHN','PVMJN','J9PJD')

$windowsVerdict = @{ isGenuine = $true; verdict = ''; redFlags = @() }
$kmsHost = $windowsLicense['kmsServer']
$activationType = $windowsLicense['activationType']
$partialKey = $windowsLicense['partialKey']

# 8a. Check public KMS server
if ($kmsHost) {
  $isPublic = $false
  foreach ($pks in $publicKmsServers) {
    if ($kmsHost -match [regex]::Escape($pks)) { $isPublic = $true; break }
  }
  if ($isPublic) {
    $windowsVerdict.redFlags += "KMS server la server crack cong cong: $kmsHost"
    $crackWarnings += [PSCustomObject]@{ Type='CrossCheck'; Severity='Critical'; App='Windows'; Detail="KMS server '$kmsHost' la server crack cong cong" }
  } elseif ($kmsHost -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
    $windowsVerdict.redFlags += "KMS server la dia chi IP: $kmsHost (thuong chi thay trong moi truong crack)"
    $crackWarnings += [PSCustomObject]@{ Type='CrossCheck'; Severity='High'; App='Windows'; Detail="KMS server la dia chi IP: $kmsHost" }
  }
}

# 8b. Retail + KMS = contradiction
if ($activationType -eq 'Retail' -and $kmsHost) {
  $windowsVerdict.redFlags += "MAU THUAN: Kenh Retail nhung co KMS server -> dau hieu crack HWID/KMS"
  $crackWarnings += [PSCustomObject]@{ Type='CrossCheck'; Severity='Critical'; App='Windows'; Detail="Kenh Retail nhung co KMS server '$kmsHost' -> crack HWID/KMS" }
}

# 8c. Check generic VL key
if ($partialKey) {
  foreach ($gk in $genericVLKeys) {
    if ($partialKey -eq $gk) {
      $windowsVerdict.redFlags += "Product key cuoi '$partialKey' trung voi key generic/VL -> crack"
      $crackWarnings += [PSCustomObject]@{ Type='CrossCheck'; Severity='Critical'; App='Windows'; Detail="Product key cuoi '$partialKey' la key generic/VL crack" }
      break
    }
  }
}

# 8d. Grace period = 0 with KMS
if ($windowsLicense['gracePeriod'] -eq 0 -and $kmsHost -and $windowsLicense['licenseStatus'] -eq 'Licensed') {
  $windowsVerdict.redFlags += "Grace period = 0 voi KMS server -> kich hoat bang crack"
  $crackWarnings += [PSCustomObject]@{ Type='CrossCheck'; Severity='Critical'; App='Windows'; Detail="Grace period = 0 voi KMS server -> crack" }
}

# 8e. Retail + KMS + Activation Task = definite crack
$hasKms = [bool]$kmsHost
$hasActivationTask = ($suspiciousTasks | Where-Object { $_.TaskName -match 'Activ|Renewal' }).Count -gt 0
if ($activationType -eq 'Retail' -and $hasKms -and $hasActivationTask) {
  $crackWarnings += [PSCustomObject]@{ Type='CrossCheck'; Severity='Critical'; App='Windows'; Detail="KET LUAN: Windows CRACK 100% - Retail + KMS server crack + Task tu dong gia han" }
} elseif ($hasKms -and $hasActivationTask) {
  $crackWarnings += [PSCustomObject]@{ Type='CrossCheck'; Severity='Critical'; App='Windows'; Detail="KET LUAN: Windows NGHI VAN CRACK CAO - KMS server + Task tu dong gia han" }
} elseif ($activationType -eq 'Retail' -and $hasKms) {
  $crackWarnings += [PSCustomObject]@{ Type='CrossCheck'; Severity='High'; App='Windows'; Detail="CANH BAO: Retail nhung co KMS server -> bat thuong" }
}

# Final verdict
if ($windowsVerdict.redFlags.Count -eq 0) {
  $windowsVerdict.isGenuine = $true
  $windowsVerdict.verdict = 'BAN QUYEN HOP LE - Khong phat hien dau hieu bat thuong'
} elseif ($windowsVerdict.redFlags.Count -eq 1 -and $activationType -eq 'KMS/Volume') {
  $windowsVerdict.isGenuine = $true
  $windowsVerdict.verdict = 'CO THE HOP LE - KMS/Volume (kiem tra moi truong doanh nghiep)'
} else {
  $windowsVerdict.isGenuine = $false
  $windowsVerdict.verdict = "NGHI VAN CRACK - Phat hien $($windowsVerdict.redFlags.Count) dau hieu bat thuong"
}

$windowsLicense['isGenuine'] = $windowsVerdict.isGenuine
$windowsLicense['verdict'] = $windowsVerdict.verdict
$windowsLicense['redFlags'] = $windowsVerdict.redFlags

# ============================================================
# 9. UNIVERSAL SOFTWARE KEY EXTRACTION & VALIDATION
# ============================================================
$softwareKeys = @()

# --- Known crack/generic key databases ---
$crackKeyDB = @{
  'WinRAR' = @('0000000000','AXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX')
  'IDM' = @('XJJXZ','Y6FGR','D89BY','5S4EH','HUDVE','EC0Q6','POAQL','FJJTG','L35DI','DDUJA','1QLHG')
}

# Helper: extract keys from a registry path
function Get-RegKeys($path, $valueNames) {
  $found = @()
  try {
    if (Test-Path $path -EA SilentlyContinue) {
      $props = Get-ItemProperty $path -EA SilentlyContinue
      foreach ($vn in $valueNames) {
        $val = $props.$vn
        if ($val -and $val.ToString().Trim() -ne '') { $found += @{ Name=$vn; Value=$val.ToString().Trim() } }
      }
    }
  } catch {}
  return $found
}

# --- Per-product key extraction ---
$keyRules = @(
  @{ App='WinRAR'; Paths=@('HKCU:\SOFTWARE\WinRAR','HKLM:\SOFTWARE\WinRAR','HKLM:\SOFTWARE\WOW6432Node\WinRAR'); Values=@('Key','RegKey','exe64') ; LicFile="$env:APPDATA\WinRAR\rarreg.key" },
  @{ App='Internet Download Manager'; Paths=@('HKCU:\SOFTWARE\DownloadManager','HKLM:\SOFTWARE\Internet Download Manager'); Values=@('Serial','FName','LName','Email','S1') },
  @{ App='Sublime Text'; Paths=@('HKCU:\SOFTWARE\Sublime Text 3\Registration','HKCU:\SOFTWARE\Sublime Text\Registration'); Values=@('license_key','email') },
  @{ App='VMware Workstation'; Paths=@('HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation','HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation'); Values=@('License.ws.16.0.e5.202','ProductID','Serial') },
  @{ App='Navicat'; Paths=@('HKCU:\SOFTWARE\PremiumSoft\Navicat\Registration','HKCU:\SOFTWARE\PremiumSoft\NavicatPG\Registration','HKCU:\SOFTWARE\PremiumSoft\NavicatMYSQL\Registration'); Values=@('Key','Registration','Info') },
  @{ App='CorelDRAW'; Paths=@('HKLM:\SOFTWARE\Corel\CorelDRAW','HKLM:\SOFTWARE\WOW6432Node\Corel\CorelDRAW'); Values=@('Serial','SerialNumber') },
  @{ App='ESET'; Paths=@('HKLM:\SOFTWARE\ESET\ESET Security\CurrentVersion\Info','HKLM:\SOFTWARE\ESET\ESET NOD32 Antivirus\CurrentVersion\Info'); Values=@('ProductKey','SeatId') },
  @{ App='Kaspersky'; Paths=@('HKLM:\SOFTWARE\KasperskyLab','HKLM:\SOFTWARE\WOW6432Node\KasperskyLab'); Values=@('LicenseKey') },
  @{ App='Total Commander'; Paths=@('HKCU:\SOFTWARE\Ghisler\Total Commander','HKLM:\SOFTWARE\Ghisler\Total Commander'); Values=@('Key','Registration') },
  @{ App='Camtasia'; Paths=@('HKCU:\SOFTWARE\TechSmith\Camtasia Studio','HKLM:\SOFTWARE\TechSmith\Camtasia'); Values=@('RegistrationKey','SoftwareKey','CamtasiaKey') },
  @{ App='Snagit'; Paths=@('HKCU:\SOFTWARE\TechSmith\Snagit','HKLM:\SOFTWARE\TechSmith\Snagit'); Values=@('RegistrationKey','SoftwareKey') }
)

foreach ($rule in $keyRules) {
  $keyData = @{ app=$rule.App; keys=@(); keySource=''; keyStatus='NotFound'; keyDetails='' }
  foreach ($p in $rule.Paths) {
    $kf = Get-RegKeys $p $rule.Values
    if ($kf.Count -gt 0) {
      $keyData.keys = $kf
      $keyData.keySource = 'Registry'
      $keyData.keyStatus = 'Found'
      break
    }
  }
  # Check license file if defined
  if ($rule.LicFile -and (Test-Path $rule.LicFile -EA SilentlyContinue)) {
    $keyData.keySource = if ($keyData.keySource -eq 'Registry') { 'Registry+File' } else { 'LicenseFile' }
    $keyData.keyStatus = 'Found'
    $keyData.keyDetails += "License file: $($rule.LicFile). "
  }
  # Validate against crack DB
  if ($keyData.keyStatus -eq 'Found' -and $crackKeyDB.ContainsKey($rule.App)) {
    foreach ($k in $keyData.keys) {
      foreach ($ck in $crackKeyDB[$rule.App]) {
        if ($k.Value -match [regex]::Escape($ck)) {
          $keyData.keyStatus = 'Crack'
          $keyData.keyDetails += "Key '$($k.Value)' trung voi key crack da biet. "
          $crackWarnings += [PSCustomObject]@{
            Type = 'CrackedKey'
            Severity = 'Critical'
            App = $rule.App
            Detail = "Product key cua $($rule.App) trung voi key crack: $($k.Value)"
          }
        }
      }
    }
  }
  $softwareKeys += $keyData
}

# --- JetBrains IDE license check ---
$jbProducts = @('IntelliJ IDEA','PhpStorm','WebStorm','PyCharm','Rider','DataGrip','GoLand','CLion','RubyMine')
foreach ($jb in $jbProducts) {
  try {
    $evalPath = "$env:APPDATA\JetBrains"
    if (Test-Path $evalPath -EA SilentlyContinue) {
      $jbDirs = Get-ChildItem $evalPath -Directory -EA SilentlyContinue | Where-Object { $_.Name -match $jb.Replace(' ','') }
      foreach ($jbd in $jbDirs) {
        $evalFile = Join-Path $jbd.FullName 'eval'
        $keyFile = Join-Path $jbd.FullName 'config\license'
        $status = 'NotFound'
        $detail = ''
        if (Test-Path "$evalFile\*" -EA SilentlyContinue) {
          $status = 'Evaluation'
          $detail = 'Dang su dung ban dung thu (eval folder ton tai)'
        }
        if (Test-Path "$keyFile\*" -EA SilentlyContinue) {
          $licFiles = Get-ChildItem $keyFile -EA SilentlyContinue
          $status = 'Licensed'
          $detail = "Co $($licFiles.Count) license file(s)"
        }
        # Check for known crack patterns in JB config
        $optFile = Join-Path $jbd.FullName 'config\options\other.xml'
        if (Test-Path $optFile -EA SilentlyContinue) {
          $content = Get-Content $optFile -Raw -EA SilentlyContinue
          if ($content -match 'evlsprt|ja-netfilter|fineagent|mymap') {
            $status = 'Crack'
            $detail += ' Phat hien crack agent (ja-netfilter/fineagent)'
            $crackWarnings += [PSCustomObject]@{
              Type = 'CrackedKey'
              Severity = 'Critical'
              App = $jb
              Detail = "JetBrains $jb su dung crack agent (ja-netfilter)"
            }
          }
        }
        if ($status -ne 'NotFound') {
          $softwareKeys += @{ app=$jb; keys=@(); keySource='ConfigFile'; keyStatus=$status; keyDetails=$detail }
        }
      }
    }
  } catch {}
}

# Check JetBrains license server in vmoptions
try {
  $vmoptsLocations = @("$env:APPDATA\JetBrains","$env:USERPROFILE")
  foreach ($loc in $vmoptsLocations) {
    $vmFiles = Get-ChildItem $loc -Filter '*.vmoptions' -Recurse -Depth 3 -EA SilentlyContinue
    foreach ($vf in $vmFiles) {
      $content = Get-Content $vf.FullName -Raw -EA SilentlyContinue
      if ($content -match 'javaagent.*ja-netfilter|javaagent.*fineagent|javaagent.*mymap') {
        $crackWarnings += [PSCustomObject]@{
          Type = 'CrackedKey'
          Severity = 'Critical'
          App = 'JetBrains'
          Detail = "Crack agent trong vmoptions: $($vf.FullName)"
        }
      }
    }
  }
} catch {}

# --- Adobe license check ---
try {
  $adobePaths = @(
    "$env:ProgramData\Adobe\SLStore",
    "$env:APPDATA\Adobe\SLStore",
    "${env:ProgramFiles}\Adobe\Adobe Creative Cloud\Utils",
    "${env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud\Utils"
  )
  foreach ($ap in $adobePaths) {
    if (Test-Path $ap -EA SilentlyContinue) {
      $slFiles = Get-ChildItem $ap -Filter '*.dr' -EA SilentlyContinue
      $pFiles = Get-ChildItem $ap -Filter '*.plist' -EA SilentlyContinue
      $hasFiles = ($slFiles.Count + $pFiles.Count) -gt 0
      if ($hasFiles) {
        $softwareKeys += @{
          app = 'Adobe Creative Cloud'
          keys = @()
          keySource = 'SLStore'
          keyStatus = 'Found'
          keyDetails = "SLStore: $($slFiles.Count) .dr files, $($pFiles.Count) .plist files"
        }
      }
    }
  }
  # Check for GenP/amtemu indicators
  $adobeAppPath = "${env:ProgramFiles}\Adobe"
  if (Test-Path $adobeAppPath -EA SilentlyContinue) {
    $patchFiles = Get-ChildItem $adobeAppPath -Recurse -Depth 3 -EA SilentlyContinue | Where-Object { $_.Name -match 'painter\.dll|amtlib\.dll\.bak|GenP|activation\.dat' }
    if ($patchFiles) {
      $crackWarnings += [PSCustomObject]@{
        Type = 'CrackedKey'
        Severity = 'Critical'
        App = 'Adobe Products'
        Detail = "Tim thay file patch/crack Adobe: $($patchFiles.Name -join ', ')"
      }
    }
  }
} catch {}

# --- AutoCAD/Autodesk license check ---
try {
  $adskPaths = @('HKLM:\SOFTWARE\Autodesk','HKLM:\SOFTWARE\WOW6432Node\Autodesk')
  foreach ($ap in $adskPaths) {
    if (Test-Path $ap -EA SilentlyContinue) {
      $adskKeys = Get-ChildItem $ap -Recurse -Depth 3 -EA SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -EA SilentlyContinue
        if ($props.SerialNumber -or $props.ProductKey -or $props.'Serial Number') {
          @{ serial=$props.SerialNumber; productKey=$props.ProductKey; sn=$props.'Serial Number' }
        }
      } | Where-Object { $_ }
      if ($adskKeys) {
        foreach ($ak in $adskKeys) {
          $keyVal = if ($ak.serial) { $ak.serial } elseif ($ak.sn) { $ak.sn } else { $ak.productKey }
          # Autodesk crack serials often are 666-69696969, 066-66666666, etc
          $isCrack = $keyVal -match '^(666|069|066)-\d{8}$'
          $softwareKeys += @{
            app = 'Autodesk Product'
            keys = @(@{Name='Serial';Value=$keyVal})
            keySource = 'Registry'
            keyStatus = if ($isCrack) { 'Crack' } else { 'Found' }
            keyDetails = if ($isCrack) { "Serial '$keyVal' trung voi pattern key crack Autodesk" } else { '' }
          }
          if ($isCrack) {
            $crackWarnings += [PSCustomObject]@{
              Type = 'CrackedKey'
              Severity = 'Critical'
              App = 'Autodesk'
              Detail = "Serial Autodesk '$keyVal' la key crack (pattern 666/069/066)"
            }
          }
        }
      }
    }
  }
} catch {}

# --- Merge key info into app results ---
foreach ($sk in $softwareKeys) {
  $matchApp = $results | Where-Object { $_.Name -match [regex]::Escape($sk.app) } | Select-Object -First 1
  if ($matchApp) {
    $matchApp | Add-Member -NotePropertyName 'ProductKey' -NotePropertyValue $(if ($sk.keys.Count -gt 0) { ($sk.keys | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; ' } else { '' }) -Force
    $matchApp | Add-Member -NotePropertyName 'KeySource' -NotePropertyValue $sk.keySource -Force
    $matchApp | Add-Member -NotePropertyName 'KeyStatus' -NotePropertyValue $sk.keyStatus -Force
    $matchApp | Add-Member -NotePropertyName 'KeyDetails' -NotePropertyValue $sk.keyDetails -Force
    if ($sk.keyStatus -eq 'Crack') {
      $matchApp.CrackRisk = 'High'
      $matchApp.CrackDetails = ($matchApp.CrackDetails + ' ' + $sk.keyDetails).Trim()
    }
  }
}

# ============================================================
# BUILD OUTPUT
# ============================================================
$riskSummary = @{
  critical = ($crackWarnings | Where-Object { $_.Severity -eq 'Critical' }).Count
  high = ($crackWarnings | Where-Object { $_.Severity -eq 'High' }).Count
  medium = ($crackWarnings | Where-Object { $_.Severity -eq 'Medium' }).Count
  totalWarnings = $crackWarnings.Count
  riskLevel = if (($crackWarnings | Where-Object { $_.Severity -eq 'Critical' }).Count -gt 0) { 'Critical' } elseif (($crackWarnings | Where-Object { $_.Severity -eq 'High' }).Count -gt 0) { 'High' } elseif (($crackWarnings | Where-Object { $_.Severity -eq 'Medium' }).Count -gt 0) { 'Medium' } else { 'Clean' }
}

$output = @{
  timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  computerName = $env:COMPUTERNAME
  userName = $env:USERNAME
  osVersion = (Get-CimInstance Win32_OperatingSystem).Caption
  totalApps = $results.Count
  apps = $results
  windowsLicense = $windowsLicense
  officeLicense = $officeLicense
  crackWarnings = $crackWarnings
  hostsWarnings = $hostsWarnings
  suspiciousTasks = $suspiciousTasks
  suspiciousProcesses = $suspiciousProcesses
  crackFilesFound = $crackFilesFound
  signatureResults = $signatureResults
  regTamperWarnings = $regTamperWarnings
  softwareKeys = $softwareKeys
  riskSummary = $riskSummary
}

$output | ConvertTo-Json -Depth 5
