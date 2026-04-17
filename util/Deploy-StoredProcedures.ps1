# =============================================================
# Deploy-StoredProcedures.ps1
# Description: Compiles VexTrainer stored procedures from SQL
#              files and grants EXECUTE permission to the
#              'staff' role for each successfully compiled proc.
#
# Usage:
#   powershell.exe -ExecutionPolicy Bypass -File .\util\Deploy-StoredProcedures.ps1
#   powershell.exe -ExecutionPolicy Bypass -File .\util\Deploy-StoredProcedures.ps1 `
#       -serverName "localhost" -loginName "vextrainer01_dbo" -databaseName "VexTrainer01"
#   powershell.exe -ExecutionPolicy Bypass -File .\util\Deploy-StoredProcedures.ps1 `
#       -serverName "localhost" -loginName "vextrainer01_dbo" -databaseName "VexTrainer01" `
#       -listFile "my-procs.txt"
#
# Notes:
#   - Must be run using the vextrainer01_dbo login (db_owner)
#   - Stored procedure SQL files must be in the ../sql/ folder
#   - List file must be in the same folder as this script (util\)
#   - List file contains one filename per line (e.g. usp_GetLessons.sql)
#   - Proc name is derived by stripping the .sql extension
#   - EXECUTE permission is granted to 'staff' role on success
#   - Failed compilations are reported in summary at end
#   - Password is always prompted securely (masked input)
# =============================================================

param(
    [string]$serverName,
    [string]$loginName,
    [string]$databaseName,
    [string]$listFile = "stored-procedures.txt"
)

# -------------------------------------------------------------
# Helper: Write a timestamped, color-coded message to console
# -------------------------------------------------------------
function Write-Console {
    param(
        [string]$message,
        [string]$level = "INFO"  # INFO, SUCCESS, WARN, ERROR
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    switch ($level) {
        "SUCCESS" { Write-Host "[$timestamp] [SUCCESS] $message" -ForegroundColor Green }
        "WARN"    { Write-Host "[$timestamp] [WARN]    $message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "[$timestamp] [ERROR]   $message" -ForegroundColor Red }
        default   { Write-Host "[$timestamp] [INFO]    $message" -ForegroundColor Cyan }
    }
}

# -------------------------------------------------------------
# Prompt for any missing parameters
# -------------------------------------------------------------
Write-Host ""
Write-Host "=================================================" -ForegroundColor White
Write-Host "  VexTrainer Stored Procedure Deployment" -ForegroundColor White
Write-Host "=================================================" -ForegroundColor White
Write-Host ""
Write-Host "  IMPORTANT: Use the vextrainer01_dbo login." -ForegroundColor Yellow
Write-Host "  The vextrainer_teachers login does not have" -ForegroundColor Yellow
Write-Host "  the required permissions to compile procedures." -ForegroundColor Yellow
Write-Host ""

if (-not $serverName) {
    $serverName = Read-Host "  Server name (e.g. localhost or server\instance)"
}

if (-not $loginName) {
    $loginName = Read-Host "  Login name (use vextrainer01_dbo)"
}

# Password is always prompted interactively - never accepted as a
# command-line parameter to prevent it appearing in shell history
$securePassword = Read-Host "  Password" -AsSecureString
$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
)

if (-not $databaseName) {
    $databaseName = Read-Host "  Database name (e.g. VexTrainer01)"
}

Write-Host ""

# -------------------------------------------------------------
# Resolve paths
# Script lives in: util\
# SQL files live in: sql\   (sibling of util\)
# List file lives in: util\ (same folder as this script)
# -------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlDir    = Join-Path (Split-Path -Parent $scriptDir) "sql"
$listPath  = Join-Path $scriptDir $listFile

Write-Console "Script folder : $scriptDir"
Write-Console "SQL folder    : $sqlDir"
Write-Console "List file     : $listPath"
Write-Console "Server        : $serverName"
Write-Console "Login         : $loginName"
Write-Console "Database      : $databaseName"
Write-Host ""

# -------------------------------------------------------------
# Validate paths exist before proceeding
# -------------------------------------------------------------
if (-not (Test-Path $sqlDir)) {
    Write-Console "SQL folder not found: $sqlDir" "ERROR"
    Write-Console "Expected 'sql' folder as sibling of 'util' folder." "ERROR"
    exit 1
}

if (-not (Test-Path $listPath)) {
    Write-Console "List file not found: $listPath" "ERROR"
    Write-Console "Expected '$listFile' in the same folder as this script." "ERROR"
    exit 1
}

# -------------------------------------------------------------
# Verify sqlcmd is available on this machine
# -------------------------------------------------------------
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Console "sqlcmd not found. Please install SQL Server Command Line Tools." "ERROR"
    Write-Console "Download: https://aka.ms/sqlcmdinstall" "ERROR"
    exit 1
}

# -------------------------------------------------------------
# Read list file - skip blank lines and comment lines (# prefix)
# -------------------------------------------------------------
$allLines = Get-Content $listPath
$fileList = $allLines | Where-Object {
    $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#")
}

if ($fileList.Count -eq 0) {
    Write-Console "No files found in list file: $listPath" "WARN"
    exit 0
}

Write-Console "Found $($fileList.Count) procedure(s) to compile."
Write-Host ""

# -------------------------------------------------------------
# Compile each stored procedure and grant permissions
# -------------------------------------------------------------
$successList = @()
$failureList = @()

foreach ($fileName in $fileList) {

    $fileName = $fileName.Trim()
    $sqlFile  = Join-Path $sqlDir $fileName

    # Derive proc name by stripping .sql extension
    $procName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

    Write-Console "Compiling: $fileName (proc: $procName)"

    # Validate the SQL file exists
    if (-not (Test-Path $sqlFile)) {
        Write-Console "File not found, skipping: $sqlFile" "ERROR"
        $failureList += [PSCustomObject]@{
            File   = $fileName
            Proc   = $procName
            Reason = "File not found: $sqlFile"
        }
        continue
    }

    # -------------------------------------------------------------
    # Run sqlcmd to compile the stored procedure
    # -S: server, -U: login, -P: password, -d: database
    # -i: input file
    # -b: exit with non-zero code on SQL error
    # -V 1: treat messages of severity 1 and above as errors
    # -------------------------------------------------------------
    $sqlcmdOutput = & sqlcmd -S $serverName -U $loginName -P $password -d $databaseName -i $sqlFile -b -V 1 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Console "Failed to compile: $fileName" "ERROR"
        # Print sqlcmd output for immediate troubleshooting
        $sqlcmdOutput | ForEach-Object {
            Write-Host "         $_" -ForegroundColor Red
        }
        $failureList += [PSCustomObject]@{
            File   = $fileName
            Proc   = $procName
            Reason = ($sqlcmdOutput -join " | ")
        }
        continue
    }

    Write-Console "Compiled successfully: $procName" "SUCCESS"

    # -------------------------------------------------------------
    # Grant EXECUTE permission to 'staff' role
    # Only runs if compilation succeeded above
    # -------------------------------------------------------------
    $grantSql    = "GRANT EXECUTE ON [dbo].[$procName] TO [staff];"
    $grantOutput = & sqlcmd -S $serverName -U $loginName -P $password -d $databaseName -Q $grantSql -b -V 1 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Console "Compiled but GRANT failed: $procName" "WARN"
        $grantOutput | ForEach-Object {
            Write-Host "         $_" -ForegroundColor Yellow
        }
        # Compilation succeeded - record with grant failure noted
        $successList += [PSCustomObject]@{
            File        = $fileName
            Proc        = $procName
            GrantStatus = "GRANT FAILED"
        }
    }
    else {
        Write-Console "EXECUTE granted to [staff]: $procName" "SUCCESS"
        $successList += [PSCustomObject]@{
            File        = $fileName
            Proc        = $procName
            GrantStatus = "OK"
        }
    }

    Write-Host ""
}

# -------------------------------------------------------------
# Summary
# -------------------------------------------------------------
Write-Host ""
Write-Host "=================================================" -ForegroundColor White
Write-Host "  Deployment Summary" -ForegroundColor White
Write-Host "=================================================" -ForegroundColor White
Write-Host ""

Write-Console "Total processed : $($fileList.Count)"
Write-Console "Succeeded       : $($successList.Count)" "SUCCESS"

if ($failureList.Count -gt 0) {
    Write-Console "Failed          : $($failureList.Count)" "ERROR"
}
else {
    Write-Console "Failed          : 0" "SUCCESS"
}

if ($successList.Count -gt 0) {
    Write-Host ""
    Write-Host "  Successful compilations:" -ForegroundColor Green
    foreach ($item in $successList) {
        $grantFlag = if ($item.GrantStatus -eq "OK") { "" } else { " (GRANT FAILED - run GRANT manually)" }
        Write-Host "    [OK] $($item.Proc)$grantFlag" -ForegroundColor Green
    }
}

if ($failureList.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failed compilations:" -ForegroundColor Red
    foreach ($item in $failureList) {
        Write-Host "    [FAIL] $($item.File)" -ForegroundColor Red
        Write-Host "           $($item.Reason)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Console "Fix the errors above and re-run the script." "WARN"
    Write-Console "Edit $listFile to list only failed files if preferred." "WARN"
}

Write-Host ""

# -------------------------------------------------------------
# Clear password from memory
# -------------------------------------------------------------
$password = $null
[System.GC]::Collect()

# Exit with non-zero code if any failures occurred
# Useful if this script is ever called from a parent process
if ($failureList.Count -gt 0) { exit 1 } else { exit 0 }

###
