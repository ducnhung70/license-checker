# scan-remote.ps1 - WinRM Remote Scan Wrapper
param(
  [Parameter(Mandatory=$false)]
  [string]$TargetComputer = 'localhost',
  [Parameter(Mandatory=$false)]
  [string]$Username = '',
  [Parameter(Mandatory=$false)]
  [string]$Password = ''
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scanScript = Join-Path $scriptDir 'scan.ps1'

if ($TargetComputer -eq 'localhost' -or $TargetComputer -eq '127.0.0.1' -or $TargetComputer -eq $env:COMPUTERNAME) {
  # Local scan - run directly
  & $scanScript
} else {
  # Remote scan via WinRM
  try {
    $sessionParams = @{ ComputerName = $TargetComputer; ErrorAction = 'Stop' }

    if ($Username -and $Password) {
      $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
      $cred = New-Object System.Management.Automation.PSCredential($Username, $secPass)
      $sessionParams['Credential'] = $cred
    }

    $scanContent = Get-Content $scanScript -Raw

    $result = Invoke-Command @sessionParams -ScriptBlock {
      param($script)
      $sb = [scriptblock]::Create($script)
      & $sb
    } -ArgumentList $scanContent

    # Invoke-Command returns deserialized objects; re-serialize to JSON
    if ($result -is [string]) {
      $result
    } else {
      $result | ConvertTo-Json -Depth 5
    }
  } catch {
    @{
      error = $true
      errorMessage = $_.Exception.Message
      target = $TargetComputer
      timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    } | ConvertTo-Json -Depth 3
  }
}
