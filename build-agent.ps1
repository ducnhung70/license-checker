$ErrorActionPreference = 'Stop'

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   License Checker Agent Builder v2.0" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Detect LAN IP
$ipAddress = (Get-NetIPAddress -AddressFamily IPv4 -Type Unicast | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|Virtual|WSL|VMware|VirtualBox' } | Select-Object -First 1).IPAddress

if (-not $ipAddress) {
    # Fallback if no matching adapter found
    $ipAddress = (Get-NetIPAddress -AddressFamily IPv4 -Type Unicast | Where-Object { $_.InterfaceAlias -ne 'Loopback Pseudo-Interface 1' } | Select-Object -First 1).IPAddress
}

if (-not $ipAddress) {
    Write-Host "Khong the tu dong nhan dien dia chi IP cua may ban!" -ForegroundColor Red
    $ipAddress = Read-Host "Vui long nhap thu cong dia chi IP cua may nay (vd: 192.168.1.10)"
}

Write-Host "`n[+] Phat hien dia chi IP Server: $ipAddress" -ForegroundColor Green
$serverUrl = "http://${ipAddress}:3847"

# 2. Update Program.cs
$projectDir = Join-Path $PWD "LicenseCheckerAgent"
$programFile = Join-Path $projectDir "Program.cs"

if (-not (Test-Path $programFile)) {
    Write-Host "[-] Khong tim thay file $programFile!" -ForegroundColor Red
    exit 1
}

$content = Get-Content $programFile -Raw
# Replace placeholder or any previously set IP
$newContent = $content -replace 'static string ServerUrl = "http://[^"]+:3847";', "static string ServerUrl = `"$serverUrl`";"

if ($content -eq $newContent) {
    Write-Host "[-] Khong tim thay bien ServerUrl de thay the trong Program.cs!" -ForegroundColor Yellow
} else {
    Set-Content -Path $programFile -Value $newContent -Encoding UTF8
    Write-Host "[+] Da ghim cung IP $serverUrl vao ma nguon Agent." -ForegroundColor Green
}

# 3. Publish
Write-Host "`n[+] Dang bien dich Agent thanh file exe doc lap..." -ForegroundColor Cyan
Set-Location $projectDir
dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o "..\dist" | Out-Null

Set-Location ..

if (Test-Path "dist\LicenseCheckerAgent.exe") {
    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "   BIEN DICH THANH CONG!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "File Agent nam tai: $(Join-Path $PWD 'dist\LicenseCheckerAgent.exe')"
    Write-Host "-> Ban co the copy file nay sang may khac de chay." -ForegroundColor Yellow
} else {
    Write-Host "`n[-] Bien dich that bai!" -ForegroundColor Red
}
