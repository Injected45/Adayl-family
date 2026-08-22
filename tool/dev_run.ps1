# dev_run.ps1 — `flutter run` with a stdin you can reach from anywhere.
#
#   powershell -ExecutionPolicy Bypass -File tool\dev_run.ps1
#
# WHY THIS EXISTS
#
# Hot reload and hot restart are keystrokes — `r` and `R` typed into the terminal
# that `flutter run` owns. That is fine for a human with the window in front of
# them, and useless for anything driving the app from outside it: a hidden
# window, a script, or an agent. Without a way in, every code change costs a full
# Gradle build (2-4 minutes) instead of a hot restart (1-2 seconds).
#
# So this starts `flutter run` with its stdin redirected to a pipe THIS script
# holds, then watches a trigger file and forwards whatever lands in it. Anyone
# who can write a file can now hot reload:
#
#   echo r > .dev\trigger      # hot reload   — most edits, keeps your screen
#   echo R > .dev\trigger      # hot restart  — resets state, no rebuild
#   echo q > .dev\trigger      # quit
#
# The trigger file is watched by modification time rather than existence, so the
# same command works twice in a row.
#
# IF YOU ARE A HUMAN: you do not need this. Press F5 in VS Code and use the ⚡ and
# ⟳ buttons in the debug toolbar — same speed, no file involved. This is for the
# case where nobody is at the keyboard.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app  = Join-Path $root 'app'
$dev  = Join-Path $root '.dev'
$trigger = Join-Path $dev 'trigger'
$log     = Join-Path $dev 'run.log'

if (-not (Test-Path $dev)) { New-Item -ItemType Directory -Path $dev | Out-Null }
if (Test-Path $trigger) { Remove-Item $trigger -Force }
if (Test-Path $log) { Remove-Item $log -Force }

# The same dart-defines run_emulator.bat passes. They are NOT secrets — the anon
# key ships inside every build and the database enforces every rule regardless.
# Keep in step with run_emulator.bat and .vscode/launch.json.
$defines = @(
  '--dart-define=SUPABASE_URL=https://wvryyidbjvvomurvfhpw.supabase.co',
  '--dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind2cnl5aWRianZ2b211cnZmaHB3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3MjgzMzgsImV4cCI6MjEwMjMwNDMzOH0.ZvppQmbFK_mU-XWocTFqc9zIUW0CTb9lctD_9yuZ8nk',
  # DEV_LOGIN removed on 2026-08-22 - see .vscode/launch.json. The account it
  # named was the only admin and its password was public in this repository.
  # Sign in with Google.
  '--dart-define=GOOGLE_SERVER_CLIENT_ID=891008495666-6bl9gctfge1rku7fd79421auqjikor12.apps.googleusercontent.com'
)

# flutter is flutter.bat on Windows, so the process to start is cmd.exe. Starting
# flutter.bat directly gives a process whose stdin the batch interpreter owns
# rather than the dart tool, and the keystrokes go nowhere.
#
# ONLY stdin is redirected through .NET. cmd redirects its own stdout and stderr
# to the log file instead, which matters: redirecting them here too means this
# script has to drain both pipes or the child blocks once a pipe buffer fills,
# and draining them synchronously would block the trigger loop below — a hot
# reload that never fires. The first version used Start-Job to drain them and
# silently wrote nothing at all, because a live Process object cannot cross a
# PowerShell runspace boundary.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName  = "$env:COMSPEC"
$psi.Arguments = '/c flutter run ' + ($defines -join ' ') + " 1> `"$log`" 2>&1"
$psi.WorkingDirectory = $app
$psi.UseShellExecute = $false
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError  = $false

$proc = [System.Diagnostics.Process]::Start($psi)

Write-Host "flutter run started (pid $($proc.Id))."
Write-Host "  log:     $log"
Write-Host "  trigger: $trigger    (write r | R | q into it)"

$lastWrite = [DateTime]::MinValue
while (-not $proc.HasExited) {
  Start-Sleep -Milliseconds 250
  if (-not (Test-Path $trigger)) { continue }
  $stamp = (Get-Item $trigger).LastWriteTimeUtc
  if ($stamp -le $lastWrite) { continue }
  $lastWrite = $stamp

  $key = (Get-Content $trigger -Raw).Trim()
  if ([string]::IsNullOrEmpty($key)) { continue }
  # One character only. `r` and `R` differ by case and mean different things, so
  # the value is passed through untouched rather than normalised.
  $key = $key.Substring(0, 1)
  Write-Host "  -> sending '$key'"
  $proc.StandardInput.WriteLine($key)
  $proc.StandardInput.Flush()
  if ($key -eq 'q') { break }
}

if ($outJob) { Stop-Job $outJob -ErrorAction SilentlyContinue; Remove-Job $outJob -Force -ErrorAction SilentlyContinue }
Write-Host 'dev_run.ps1 finished.'
