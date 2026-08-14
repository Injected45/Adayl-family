# ============================================================================
#  open_app.ps1 - bring the app up on the emulator, from any starting state.
#
#    .\open_app.ps1              use whatever APK was last built (builds if none)
#    .\open_app.ps1 -Build       rebuild first
#    .\open_app.ps1 -DebugBuild  debug APK instead of release
#    .\open_app.ps1 -Shot out.png   save a screenshot when it is up
#
#  -DebugBuild, not -Debug: [CmdletBinding()] reserves -Debug as a common
#  parameter, and redefining it makes every invocation fail to bind before the
#  script body ever runs.
#
#  ---------------------------------------------------------------------------
#  WHY THIS EXISTS ALONGSIDE run_emulator.bat
#
#  run_emulator.bat is correct when a human runs it in a console window, and it
#  cannot be run any other way: its boot-wait loop calls `timeout /t 2`, which
#  refuses to run when stdin is redirected and prints
#
#      ERROR: Input redirection is not supported, exiting the process immediately
#
#  thousands of times before the script gives up - having built nothing. Anything
#  that shells out to it (an agent, CI, a scheduled task) hits that. PowerShell's
#  Start-Sleep has no such dependency, so this script works from a console AND
#  from a tool call.
#
#  THE TWO BLACK-SCREEN CAUSES, BOTH HANDLED HERE
#
#   1. The emulator hangs in adb state `offline`. Seen once for seven minutes
#      with qemu burning CPU the whole time, so it was not slowness. The cure is
#      a cold boot; Wait-Booted below gives up after -OfflineLimit seconds and
#      relaunches with -no-snapshot-load, which is NOT a wipe and took 215s.
#
#   2. Android turns the display off on idle. adb then screenshots pure black,
#      the app is fine, and it looks exactly like a crash. Keep-Awake sets
#      screen_off_timeout to its maximum and `svc power stayon true` - the
#      emulator always reports itself on AC, so the screen simply never sleeps
#      again for the life of the AVD.
#
#  The Supabase URL and anon key are NOT secrets: they ship inside every build
#  and can be read out of the APK. Every rule is enforced in the database. The
#  service_role key bypasses RLS and must NEVER appear here.
# ============================================================================
[CmdletBinding()]
param(
  [switch]$Build,
  [switch]$DebugBuild,
  [string]$Avd = '',
  [string]$Shot = '',
  [int]$BootLimit = 420,
  [int]$OfflineLimit = 180
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkg  = 'ly.adayl.family_app'

$SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co'
$SUPABASE_ANON_KEY = ''
# An ordinary email/password account. Its role still comes from public.profiles
# like everyone else's; it exists so the app is usable before Google sign-in is
# switched on. It is an approved admin, so this APK embeds an admin password.
$DEV_EMAIL = 'admin@fam.test'
$DEV_PASS  = ''

# The WEB client ID from Google Cloud - the SAME one entered in Supabase's Google
# provider. Required on Android too: without it a token verifies on the device
# and is then rejected by Supabase, which looks like a Google failure and is not.
# NOT a secret; it ships in every app offering Google sign-in. The client SECRET
# is a different string and belongs only in the Supabase dashboard.
# Empty => the app hides the Google button rather than offering a broken one.
$GOOGLE_SERVER_CLIENT_ID = ''

function Say($m) { Write-Host "  $m" }

# ---- Locate the SDK -------------------------------------------------------
function Find-Tool($relative) {
  # The parentheses around the first element are load-bearing. In PowerShell `,`
  # binds TIGHTER than `+`, so the unparenthesised form parses as
  #   $env:LOCALAPPDATA + @('\Android\Sdk', $env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
  # - one mangled string instead of three candidate paths, and adb is "not
  # found" on a machine where it plainly exists.
  $bases = @(($env:LOCALAPPDATA + '\Android\Sdk'), $env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
  foreach ($base in $bases) {
    if ([string]::IsNullOrEmpty($base)) { continue }
    $p = Join-Path $base $relative
    if (Test-Path $p) { return $p }
  }
  return ''
}

$adb = Find-Tool 'platform-tools\adb.exe'
$emu = Find-Tool 'emulator\emulator.exe'
if ([string]::IsNullOrEmpty($adb)) { throw 'adb.exe not found. Install Android Studio platform-tools, or set ANDROID_HOME.' }
if ([string]::IsNullOrEmpty($emu)) { throw 'emulator.exe not found. Install the Android emulator package.' }

# ---- Emulator state -------------------------------------------------------
function Get-State {
  # `adb get-state` writes to stderr and returns non-zero when nothing is
  # attached, which -ErrorAction cannot suppress for a native exe. Parse
  # `adb devices` instead: it always exits 0 and always prints a table.
  $lines = & $adb devices 2>$null
  foreach ($line in $lines) {
    if ($line -match '^(emulator-\d+)\s+(\S+)') { return $Matches[2] }
  }
  return 'none'
}

function Wait-Booted([int]$limit, [int]$offlineLimit) {
  $t = 0
  $offline = 0
  while ($t -lt $limit) {
    $state = Get-State
    if ($state -eq 'device') {
      $booted = (& $adb shell getprop sys.boot_completed 2>$null) -join ''
      if ($booted.Trim() -eq '1') { return $true }
    }
    if ($state -eq 'offline') {
      $offline += 3
      # Cause 1. Not slowness - a hang. Cold boot is the documented cure.
      if ($offline -ge $offlineLimit) {
        Say "stuck offline for ${offline}s - cold booting"
        & $adb emu kill 2>$null | Out-Null
        Get-Process -Name qemu-system-x86_64, emulator -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 3
        Start-Process -FilePath $emu -ArgumentList '-avd', $script:avdName, '-no-snapshot-load', '-netdelay', 'none', '-netspeed', 'full'
        $offline = 0
      }
    } else {
      $offline = 0
    }
    Start-Sleep -Seconds 3
    $t += 3
  }
  return $false
}

# ---- 1. Emulator up -------------------------------------------------------
if ((Get-State) -eq 'device') {
  Say 'emulator already running'
  $script:avdName = ''
} else {
  $script:avdName = $Avd
  if ([string]::IsNullOrEmpty($script:avdName)) {
    $avds = & $emu -list-avds 2>$null | Where-Object { $_.Trim() -ne '' }
    if (-not $avds) { throw 'No AVD exists. Create one in Android Studio Device Manager, or: flutter emulators --create' }
    $script:avdName = ($avds | Select-Object -First 1).Trim()
  }
  Say "starting emulator: $($script:avdName)"
  Start-Process -FilePath $emu -ArgumentList '-avd', $script:avdName, '-netdelay', 'none', '-netspeed', 'full'
}

Say 'waiting for boot'
if (-not (Wait-Booted $BootLimit $OfflineLimit)) {
  throw "emulator did not finish booting within ${BootLimit}s (state: $(Get-State))"
}
Say 'booted'

# ---- 2. Keep the screen on, permanently -----------------------------------
# Cause 2. Without this the display sleeps on idle and every later screenshot is
# pure black - indistinguishable from a crashed app. Persists in the AVD, so it
# only has to be set once, but re-applying is free and survives a wipe.
& $adb shell settings put system screen_off_timeout 2147483647 2>$null | Out-Null
& $adb shell svc power stayon true 2>$null | Out-Null
& $adb shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null
& $adb shell wm dismiss-keyguard 2>$null | Out-Null
Say 'screen kept awake'

# ---- 3. APK ---------------------------------------------------------------
if ($DebugBuild) { $mode = 'debug' } else { $mode = 'release' }
$apk = Join-Path $root "app\build\app\outputs\flutter-apk\app-$mode.apk"

if ($Build -or -not (Test-Path $apk)) {
  Say "building $mode APK (a clean release build takes a few minutes)"
  Push-Location (Join-Path $root 'app')
  try {
    $defines = @(
      "--dart-define=SUPABASE_URL=$SUPABASE_URL",
      "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY",
      '--dart-define=DEV_LOGIN=true',
      "--dart-define=DEV_LOGIN_EMAIL=$DEV_EMAIL",
      "--dart-define=DEV_LOGIN_PASSWORD=$DEV_PASS"
    )
    if (-not [string]::IsNullOrEmpty($GOOGLE_SERVER_CLIENT_ID)) {
      $defines += "--dart-define=GOOGLE_SERVER_CLIENT_ID=$GOOGLE_SERVER_CLIENT_ID"
      Say 'google sign-in: configured'
    } else {
      Say 'google sign-in: NOT configured - the Google button will be hidden'
    }
    & flutter build apk "--$mode" @defines
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk exited with $LASTEXITCODE" }
  } finally { Pop-Location }
}
if (-not (Test-Path $apk)) { throw "APK not found at $apk" }

# ---- 4. Install and launch ------------------------------------------------
Say "installing $mode APK"
$out = & $adb install -r $apk 2>&1 | Out-String
if ($out -notmatch 'Success') {
  # debug and release are signed with different keys, so switching between them
  # fails with INSTALL_FAILED_UPDATE_INCOMPATIBLE until the old one is removed.
  Say 'reinstall refused (signature mismatch) - removing the old install'
  & $adb uninstall $pkg 2>$null | Out-Null
  $out = & $adb install -r $apk 2>&1 | Out-String
  if ($out -notmatch 'Success') { throw "install failed:`n$out" }
}

& $adb shell am start -n "$pkg/.MainActivity" | Out-Null
Start-Sleep -Seconds 8

$pid_ = ((& $adb shell pidof $pkg 2>$null) -join '').Trim()
if ([string]::IsNullOrEmpty($pid_)) {
  Say 'app is not running - last crash lines:'
  & $adb logcat -d -b crash 2>$null | Select-Object -Last 20
  throw 'the app did not start'
}

if (-not [string]::IsNullOrEmpty($Shot)) {
  # Captured on the device and pulled, NOT `adb exec-out screencap -p > file`.
  # PowerShell's `>` is a text redirection: it decodes the byte stream and
  # re-encodes it with a BOM, so the PNG arrives corrupt (it starts ef bb bf)
  # and every image viewer rejects it. `adb pull` copies bytes.
  #
  # No `2>&1` on these. adb reports "1 file pulled" on STDERR, and in Windows
  # PowerShell 5.1 redirecting a native command's stderr wraps each line in an
  # ErrorRecord and clears $?, which $ErrorActionPreference='Stop' turns into a
  # thrown NativeCommandError - on a command that succeeded.
  & $adb shell screencap -p /sdcard/_shot.png | Out-Null
  & $adb pull /sdcard/_shot.png $Shot | Out-Null
  & $adb shell rm -f /sdcard/_shot.png | Out-Null
  if (Test-Path $Shot) { Say "screenshot: $Shot" } else { Say 'screenshot failed' }
}

Write-Host ''
Say "READY - $mode build running on $(Get-State), pid $pid_"
Say "sign in with the second button (dev account $DEV_EMAIL)"
Write-Host ''
