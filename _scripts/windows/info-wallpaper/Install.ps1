<#
.SYNOPSIS
    Registers a scheduled task that refreshes the info-wallpaper at logon and
    on RDP (re)connect, and drops a manual-update launcher.
.PARAMETER Uninstall
    Remove the scheduled tasks instead of creating them.
#>
[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$Dir    = $PSScriptRoot
$Script = Join-Path $Dir 'Update-InfoWallpaper.ps1'
$TaskLogon   = 'InfoWallpaper-Logon'
$TaskConnect = 'InfoWallpaper-RdpConnect'

if ($Uninstall) {
    foreach ($t in $TaskLogon, $TaskConnect) {
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $t -Confirm:$false
            Write-Host "Removed task: $t" -ForegroundColor Yellow
        }
    }
    return
}

# Prefer PowerShell 7 (pwsh) if present, else Windows PowerShell
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" }

$action = New-ScheduledTaskAction -Execute $pwsh `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`""

# Run hidden, in the interactive session, only when this user is logged on
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Trigger 1: at logon
$trigLogon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

Register-ScheduledTask -TaskName $TaskLogon -Action $action -Principal $principal `
    -Settings $settings -Trigger $trigLogon -Force | Out-Null
Write-Host "Registered: $TaskLogon (runs at logon)" -ForegroundColor Green

# Trigger 2: on RDP (re)connect — event 25 in TerminalServices-LocalSessionManager.
# Built via CIM because New-ScheduledTaskTrigger has no event-trigger option.
try {
    $subscription = @"
<QueryList><Query Id="0" Path="Microsoft-Windows-TerminalServices-LocalSessionManager/Operational">
<Select Path="Microsoft-Windows-TerminalServices-LocalSessionManager/Operational">
*[System[Provider[@Name='Microsoft-Windows-TerminalServices-LocalSessionManager'] and (EventID=25 or EventID=21)]]
</Select></Query></QueryList>
"@
    $cimClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $trigConnect = New-CimInstance -CimClass $cimClass -ClientOnly
    $trigConnect.Enabled      = $true
    $trigConnect.Subscription = $subscription
    Register-ScheduledTask -TaskName $TaskConnect -Action $action -Principal $principal `
        -Settings $settings -Trigger $trigConnect -Force | Out-Null
    Write-Host "Registered: $TaskConnect (runs on RDP connect/reconnect)" -ForegroundColor Green
} catch {
    Write-Host "Skipped RDP-connect trigger ($($_.Exception.Message)). Logon trigger still active." -ForegroundColor Yellow
}

# Manual-update launcher
$cmd = Join-Path $Dir 'Update now.cmd'
@"
@echo off
"$pwsh" -NoProfile -ExecutionPolicy Bypass -File "$Script" %*
"@ | Set-Content -Path $cmd -Encoding ASCII
Write-Host "Manual updater: `"$cmd`"" -ForegroundColor Green
Write-Host "Done." -ForegroundColor Cyan
