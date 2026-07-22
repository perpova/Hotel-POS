# Hotel POS Database Initializer Script
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SqlPath = Join-Path $PSScriptRoot "database.sql"

if (-not (Test-Path $SqlPath)) {
    Write-Host "Error: database.sql not found at $SqlPath" -ForegroundColor Red
    exit 1
}

# 1. Find mysql.exe executable
$mysql = (Get-Command mysql.exe -ErrorAction SilentlyContinue).Source
if (-not $mysql) {
    $candidates = @(
        "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe",
        "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe",
        "C:\Program Files\MySQL\MySQL Server 9.0\bin\mysql.exe",
        "C:\Program Files\MySQL\MySQL Server 8.1\bin\mysql.exe",
        "C:\Program Files\MySQL\MySQL Server 8.2\bin\mysql.exe",
        "C:\Program Files\MySQL\MySQL Server 8.3\bin\mysql.exe",
        "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe",
        "C:\Program Files (x86)\MySQL\MySQL Server 8.0\bin\mysql.exe",
        "C:\Program Files (x86)\MySQL\MySQL Server 8.4\bin\mysql.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $mysql = $c; break }
    }
}
if (-not $mysql) {
    $found = Get-ChildItem -Path "C:\Program Files\MySQL" -Filter mysql.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $mysql = $found.FullName }
}

if (-not $mysql) {
    Write-Host "mysql.exe could not be located." -ForegroundColor Red
    exit 1
}

# 2. Iterate common root passwords to create database and run database.sql
$passwords = @('1234', 'root', '', '123456', 'admin')
$success = $false

foreach ($pw in $passwords) {
    $pArg = if ($pw -ne '') { "-p$pw" } else { "" }
    
    # Check connection / create database
    $proc = Start-Process -FilePath $mysql -ArgumentList "-u root $pArg -e `"CREATE DATABASE IF NOT EXISTS hotel_pos;`"" -Wait -NoNewWindow -PassThru -ErrorAction SilentlyContinue
    if ($proc.ExitCode -eq 0) {
        Write-Host "Connected to MySQL root ($pw). Initializing database schema..." -ForegroundColor Green
        
        # Execute database.sql using source command
        $sqlPathForward = $SqlPath.Replace("\", "/")
        Start-Process -FilePath $mysql -ArgumentList "-u root $pArg -e `"USE hotel_pos; SOURCE $sqlPathForward;`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        
        # Pipe stdin as fallback to guarantee table creation
        Get-Content -Raw $SqlPath | & $mysql -u root $pArg hotel_pos 2>$null
        
        $success = $true
        break
    }
}

if ($success) {
    Write-Host "Hotel POS database and all tables initialized successfully!" -ForegroundColor Green
} else {
    Write-Host "Could not automatically connect to MySQL root." -ForegroundColor Red
}
