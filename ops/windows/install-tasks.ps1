<#
.SYNOPSIS
    Registers the scheduled tasks that keep the system running and backed up.

.DESCRIPTION
    Creates three Windows scheduled tasks:

      FamilyApp-API        starts the API at boot and restarts it if it dies
      FamilyApp-Backup     nightly database dump, with retention
      FamilyApp-Reconcile  nightly ledger check

    Nothing is created unless you pass -Execute. Without it the script prints
    what it WOULD do, so you can read it before changing your machine.

    Run from an elevated PowerShell prompt.

.EXAMPLE
    # See what would happen
    .\install-tasks.ps1

.EXAMPLE
    # Actually register them
    .\install-tasks.ps1 -Execute
#>
[CmdletBinding()]
param(
    [string]$ApiDirectory,
    [string]$BackupTime = '02:15',
    [string]$ReconcileTime = '02:45',
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'

# Resolved here rather than as a param default: $PSScriptRoot is not always
# populated when defaults are evaluated, which made the script fail before it
# printed anything.
if (-not $ApiDirectory) {
    $scriptRoot = if ($PSScriptRoot) {
        $PSScriptRoot
    }
    else {
        Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $ApiDirectory = (Resolve-Path (Join-Path $scriptRoot '..\..\api')).Path
}

if (-not (Test-Path (Join-Path $ApiDirectory 'package.json'))) {
    throw "No package.json in $ApiDirectory. Pass -ApiDirectory with the path to the api folder."
}

$npm = (Get-Command npm.cmd -ErrorAction SilentlyContinue)
if ($null -eq $npm) { throw 'npm.cmd not found on PATH. Install Node.js first.' }
$npmPath = $npm.Source

# Runs as the current user so it inherits the same PATH and profile that a manual
# `npm start` would. A dedicated service account is better if one exists.
$principalUser = "$env:USERDOMAIN\$env:USERNAME"

$tasks = @(
    @{
        Name        = 'FamilyApp-API'
        Description = 'Family association API — starts at boot, restarts on failure'
        Arguments   = 'start'
        Trigger     = 'AtStartup'
    },
    @{
        Name        = 'FamilyApp-Backup'
        Description = 'Nightly database backup with retention'
        Arguments   = 'run backup'
        Trigger     = $BackupTime
    },
    @{
        Name        = 'FamilyApp-Reconcile'
        Description = 'Nightly ledger reconciliation — alerts by exit code'
        Arguments   = 'run reconcile'
        Trigger     = $ReconcileTime
    }
)

Write-Host ''
Write-Host "  api directory : $ApiDirectory"
Write-Host "  npm           : $npmPath"
Write-Host "  run as        : $principalUser"
Write-Host ''

foreach ($task in $tasks) {
    $when = if ($task.Trigger -eq 'AtStartup') { 'at boot' } else { "daily at $($task.Trigger)" }
    Write-Host ("  {0,-22} {1,-18} npm {2}" -f $task.Name, $when, $task.Arguments)
}
Write-Host ''

if (-not $Execute) {
    Write-Host '  Dry run - nothing was changed. Re-run with -Execute to register these.' -ForegroundColor Yellow
    Write-Host ''
    return
}

foreach ($task in $tasks) {
    $action = New-ScheduledTaskAction -Execute $npmPath `
        -Argument $task.Arguments -WorkingDirectory $ApiDirectory

    if ($task.Trigger -eq 'AtStartup') {
        $trigger = New-ScheduledTaskTrigger -AtStartup
        # The API is long-running: no time limit, and bring it back if it exits.
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
            -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
    }
    else {
        $trigger = New-ScheduledTaskTrigger -Daily -At $task.Trigger
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
            -StartWhenAvailable
    }

    Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false -ErrorAction SilentlyContinue

    Register-ScheduledTask -TaskName $task.Name -Description $task.Description `
        -Action $action -Trigger $trigger -Settings $settings `
        -User $principalUser -RunLevel Limited | Out-Null

    Write-Host "  registered $($task.Name)" -ForegroundColor Green
}

Write-Host ''
Write-Host '  Done. Verify with:' -ForegroundColor Green
Write-Host '    Get-ScheduledTask -TaskName FamilyApp-*'
Write-Host ''
Write-Host '  Start the API now without rebooting:'
Write-Host '    Start-ScheduledTask -TaskName FamilyApp-API'
Write-Host ''
Write-Host '  A failing backup or reconcile shows a non-zero Last Run Result in'
Write-Host '  Task Scheduler. Check it weekly, or attach an email action to the task.'
Write-Host ''
