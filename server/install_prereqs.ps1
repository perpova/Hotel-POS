# ============================================================
#  Hotel POS - Prerequisites Downloader & Installer Script
# ============================================================
param (
    [switch]$InstallNode,
    [switch]$InstallMySQL
)

$TempDir = [System.IO.Path]::GetTempPath()

if ($InstallNode) {
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Downloading Node.js v20 LTS Runtime Installer...     " -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    $nodeMsi = Join-Path $TempDir "node-v20-x64.msi"
    $nodeUrl = "https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeMsi -UseBasicParsing
        Write-Host "Installing Node.js silently..." -ForegroundColor Green
        Start-Process msiexec.exe -ArgumentList "/i `"$nodeMsi`" /qn /norestart" -Wait
        Remove-Item $nodeMsi -Force -ErrorAction SilentlyContinue
        Write-Host "Node.js installation finished successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error downloading or installing Node.js: $_" -ForegroundColor Red
    }
}

if ($InstallMySQL) {
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Downloading MySQL Community Installer 8.0...         " -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    $mysqlMsi = Join-Path $TempDir "mysql-installer.msi"
    $mysqlUrl = "https://dev.mysql.com/get/Downloads/MySQLInstaller/mysql-installer-web-community-8.0.36.0.msi"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $mysqlUrl -OutFile $mysqlMsi -UseBasicParsing
        Write-Host "Launching MySQL Installer setup..." -ForegroundColor Green
        Start-Process msiexec.exe -ArgumentList "/i `"$mysqlMsi`" /passive" -Wait
        Remove-Item $mysqlMsi -Force -ErrorAction SilentlyContinue
        Write-Host "MySQL setup launcher completed!" -ForegroundColor Green
    } catch {
        Write-Host "Error downloading or installing MySQL: $_" -ForegroundColor Red
    }
}
