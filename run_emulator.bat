@echo off
REM ============================================================================
REM  run_emulator.bat - run the app on an Android emulator against Supabase.
REM
REM    run_emulator.bat                    use a running emulator, or start the
REM                                        first AVD found
REM    run_emulator.bat Pixel_4_API_30     start that AVD specifically
REM    run_emulator.bat --list             show the AVDs on this machine
REM    run_emulator.bat --release          release build
REM
REM ----------------------------------------------------------------------------
REM  FOUR WINDOWS-BATCH TRAPS THIS FILE AVOIDS. All four were hit while writing
REM  it, and every one failed silently or misleadingly.
REM
REM  1. `call flutter`, never bare `flutter`. On Windows flutter is flutter.bat,
REM     and invoking a .bat from a .bat WITHOUT `call` transfers control instead
REM     of calling it - the rest of the script simply never runs.
REM
REM  2. Capture output through a TEMP FILE, not
REM     `for /f ... in ('"C:\path\adb.exe" devices ^| findstr ...')`.
REM     When the command inside for /f begins with a quote, cmd's quote-stripping
REM     mangles the pipeline: it printed "The system cannot find the path
REM     specified" and returned nothing, so a running emulator looked absent.
REM
REM  3. No `$` anchors in findstr patterns. adb and flutter emit CRLF, so a piped
REM     line ends with a carriage return and `device$` matches nothing.
REM
REM  4. ASCII ONLY, with CRLF line endings. cmd parses a .bat in the console's OEM
REM     codepage, so UTF-8 text decodes to bytes that can include & and |, which
REM     splits the line and makes cmd run the following words as commands
REM     ("'the' is not recognized as an internal or external command").
REM ----------------------------------------------------------------------------
REM
REM  The URL and anon key below are NOT secrets. They ship inside every build of
REM  this app and can be read straight out of the APK. The database design assumes
REM  exactly that: every rule is enforced by RLS, CHECK constraints, triggers and
REM  SECURITY DEFINER functions, so a hostile holder of this key can do nothing an
REM  honest one could not.
REM
REM  The SERVICE ROLE key bypasses RLS and must never appear in this file.
REM
REM  There is no 10.0.2.2 here. That alias was for reaching a Node API on the host
REM  machine's loopback. Supabase is a public HTTPS host, so the emulator reaches
REM  it the way a real phone does - which also means the emulator needs working
REM  internet, and a cold-booted AVD sometimes has none for the first few seconds.
REM ============================================================================
setlocal EnableDelayedExpansion

cd /d "%~dp0app"
if errorlevel 1 (
  echo Could not find the app folder next to this script.
  exit /b 1
)

set "SUPABASE_URL=https://wvryyidbjvvomurvfhpw.supabase.co"
set "SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind2cnl5aWRianZ2b211cnZmaHB3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3MjgzMzgsImV4cCI6MjEwMjMwNDMzOH0.ZvppQmbFK_mU-XWocTFqc9zIUW0CTb9lctD_9yuZ8nk"

REM Development sign-in: an ordinary email/password account with NO special
REM privilege. Its role still comes from public.profiles like everyone else's. It
REM exists so the app is testable before the Google provider is switched on.
set "DEV_LOGIN_EMAIL=admin@adayl.test"
set "DEV_LOGIN_PASSWORD=Adayl-Dev-7Kq2mXe4Rt"

REM ---------------------------------------------------------------------------
REM  Google sign-in. Paste the WEB client ID here - the web one on Android too.
REM  Leave it empty and the Google button stays disabled; the dev button still
REM  works, so an unconfigured checkout is not a broken checkout.
REM
REM  This is the ID, NOT the secret. The secret goes in the Supabase dashboard
REM  (Authentication - Providers - Google) and must never appear in this file:
REM  anything here ships inside the APK.
REM
REM  Why the WEB client ID and not the Android one: the app signs in with
REM  signInWithIdToken, so Google must issue a token whose AUDIENCE is the
REM  backend that will verify it - Supabase - and Supabase identifies itself by
REM  the web client ID. The Android OAuth client still has to EXIST in the same
REM  Google Cloud project, registered against the package name and the signing
REM  SHA-1, or Google refuses to issue a token at all. It is just never named
REM  here. A token minted for the Android client verifies on the device and is
REM  then rejected by Supabase, which is the commonest way this fails.
REM ---------------------------------------------------------------------------
set "GOOGLE_SERVER_CLIENT_ID=891008495666-6bl9gctfge1rku7fd79421auqjikor12.apps.googleusercontent.com"

REM ---- Refuse to run half-configured ----------------------------------------
REM This project is a COPY of the Rhalla app with its credentials removed, so a
REM fresh clone has nothing to talk to. Without this guard the app builds, runs,
REM shows the sign-in screen and fails every call with a network error that says
REM nothing about the cause.
if "%SUPABASE_ANON_KEY%"=="" goto not_configured
echo %SUPABASE_URL% | findstr /c:"YOUR-PROJECT" >nul
if not errorlevel 1 goto not_configured
goto configured

:not_configured
echo.
echo   This checkout is not pointed at a Supabase project yet.
echo.
echo   Open this file and fill in, near the top:
echo     SUPABASE_URL       your project URL   ^(dashboard - Settings - API^)
echo     SUPABASE_ANON_KEY  the anon/public key from the same page
echo.
echo   Then, to enable Google sign-in, GOOGLE_SERVER_CLIENT_ID - see
echo   docs\GOOGLE_SIGNIN.md. Schema first: docs\SUPABASE_SETUP.md.
exit /b 1

:configured
set "MODE=--debug"
set "AVD="
set "TMPD=%TEMP%\family_app_run"
set "DEVLIST=%TMPD%\devices.txt"
set "AVDLIST=%TMPD%\avds.txt"
if not exist "%TMPD%" mkdir "%TMPD%" >nul 2>&1

:parse
if "%~1"=="" goto after_parse
if /i "%~1"=="--list" goto list_avds
if /i "%~1"=="--release" (
  set "MODE=--release"
  shift
  goto parse
)
if /i "%~1"=="--profile" (
  set "MODE=--profile"
  shift
  goto parse
)
set "AVD=%~1"
shift
goto parse
:after_parse

where flutter >nul 2>&1
if errorlevel 1 (
  echo.
  echo   flutter is not on PATH. Open a terminal where "flutter --version" works,
  echo   or add Flutter's bin folder to PATH.
  exit /b 1
)

REM ---- Find adb -------------------------------------------------------------
set "ADB="
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not defined ADB if exist "%ANDROID_HOME%\platform-tools\adb.exe" set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
if not defined ADB if exist "%ANDROID_SDK_ROOT%\platform-tools\adb.exe" set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
if not defined ADB (
  where adb >nul 2>&1
  if not errorlevel 1 set "ADB=adb"
)
if not defined ADB (
  echo.
  echo   Could not find adb.exe. Looked in:
  echo     %LOCALAPPDATA%\Android\Sdk\platform-tools\
  echo     ANDROID_HOME\platform-tools\ and ANDROID_SDK_ROOT\platform-tools\
  echo   Install Android Studio's platform-tools, or set ANDROID_HOME.
  exit /b 1
)
echo   adb: %ADB%

REM ---- Is an emulator already up? -------------------------------------------
call :find_device
if defined DEVICE (
  echo   Using the emulator already running: !DEVICE!
  goto have_device
)

REM ---- Otherwise start one --------------------------------------------------
if not defined AVD (
  call flutter emulators > "%AVDLIST%" 2>nul
  REM Pick the first Android AVD. `flutter emulators` prints rows as
  REM   <id> * <name> * <manufacturer> * android
  REM ( * is a bullet ) and the platform column is preceded by a SINGLE space.
  REM The old pattern "  android" (two spaces) matched nothing after a flutter
  REM update, so no AVD was ever chosen and this script wrongly reported that
  REM none existed. Anchor on a row that STARTS with an id token and lists the
  REM android platform, which also skips the header, blanks and the help URLs.
  REM Prefer an AVD whose name says it is for testing this app. The stock
  REM Medium_Phone AVD sorts first and ships a 6 GB data partition, which a
  REM ~160 MB Flutter DEBUG apk fills - the install then dies with
  REM   java.io.IOException: Requested internal only, but not enough space
  REM which names neither the emulator nor the partition.
  REM
  REM Matched by pattern rather than one fixed name so this works on any machine.
  REM If nothing matches, the free-space check further down still catches a full
  REM emulator and says so in words.
  for /f "tokens=1" %%A in ('findstr /r /c:"^[A-Za-z0-9_]*_Test_[A-Za-z0-9_]* .* android" "%AVDLIST%"') do (
    if not defined AVD set "AVD=%%A"
  )
  if not defined AVD (
    for /f "tokens=1" %%A in ('findstr /r /c:"^[A-Za-z0-9_].* android" "%AVDLIST%"') do (
      if not defined AVD set "AVD=%%A"
    )
  )
)
if not defined AVD (
  echo.
  echo   No Android emulator is running and no AVD was found.
  echo   What adb sees:
  if exist "%DEVLIST%" type "%DEVLIST%"
  echo   Create one:   flutter emulators --create
  echo   Or list them: run_emulator.bat --list
  exit /b 1
)

echo   Starting emulator: !AVD!
start "" cmd /c flutter emulators --launch !AVD!

echo   Waiting for it to come up. A cold boot can take a minute.
"%ADB%" wait-for-device
REM wait-for-device returns as soon as adb can SEE the device, well before Android
REM has finished booting. Installing an APK before sys.boot_completed fails with a
REM confusing INSTALL_FAILED, so poll for the real signal.
set /a TRIES=0
:wait_boot
set /a TRIES+=1
set "BOOTED="
"%ADB%" shell getprop sys.boot_completed > "%TMPD%\boot.txt" 2>nul
for /f "usebackq tokens=1" %%B in ("%TMPD%\boot.txt") do set "BOOTED=%%B"
if "!BOOTED!"=="1" goto booted
if !TRIES! GEQ 90 (
  echo.
  echo   The emulator did not finish booting after about 3 minutes. Start it from
  echo   Android Studio's Device Manager, then run this script again.
  exit /b 1
)
timeout /t 2 /nobreak >nul
goto wait_boot
:booted
echo   Emulator booted.
call :find_device

:have_device
if not defined DEVICE (
  echo   Could not identify the emulator device id. What adb sees:
  if exist "%DEVLIST%" type "%DEVLIST%"
  exit /b 1
)

REM ---- A cold-booted emulator often has no DNS for a few seconds ------------
REM Checked because that failure is otherwise silent and looks like a bad key:
REM the app starts, the sign-in button works, and every request times out.
REM ---- Enough room to install? ----------------------------------------------
REM A Flutter debug apk is ~150 MB and the installer needs roughly double that
REM while it streams and optimises. Below ~500 MB free the install fails with an
REM IOException that mentions neither the emulator nor the partition, so say it
REM plainly here instead.
REM
REM ⚠ `df /data` IS NOT USED, AND THAT IS THE FIX FOR A REAL BUG.
REM On API 36 `df /data` prints the header and NO DATA ROW, so `skip=1 tokens=4`
REM matched nothing, FREEKB stayed empty... except the old code then treated the
REM empty value as 0 and reported "Only 0 MB free" on an emulator with 5 GB. The
REM install was refused for days while the actual cause was this parse. Bare `df`
REM plus a filter on the mount point does produce the row.
set "FREEKB="
"%ADB%" -s !DEVICE! shell df > "%TMPD%\df.txt" 2>nul
for /f "tokens=4" %%K in ('findstr /r /c:" /data$" "%TMPD%\df.txt"') do if not defined FREEKB set "FREEKB=%%K"
REM No reading is NOT a reading of zero. If the row cannot be found on some future
REM image, say so and carry on rather than blocking an install that would work —
REM a false refusal costs more than a genuine INSTALL_FAILED, which at least names
REM itself.
if not defined FREEKB echo   Could not read free space - continuing anyway.
if defined FREEKB (
  set /a FREEMB=!FREEKB!/1024
  if !FREEMB! LSS 500 (
    echo.
    echo   Only !FREEMB! MB free on the emulator - an install needs about 500 MB.
    echo.
    echo   Free some up:
    echo     "%ADB%" shell pm uninstall ly.adayl.family_app
    echo     "%ADB%" shell pm trim-caches 999G
    echo   Or run on a roomier AVD - see which exist with:
    echo     run_emulator.bat --list
    echo   then:  run_emulator.bat ^<avd name^>
    echo   Or wipe it: Device Manager - the AVD's menu - Wipe Data.
    exit /b 1
  )
  echo   Free space on the emulator: !FREEMB! MB
)

echo   Checking the emulator can reach Supabase...
set /a NET=0
:wait_net
set /a NET+=1
"%ADB%" -s !DEVICE! shell ping -c 1 -W 2 wvryyidbjvvomurvfhpw.supabase.co >nul 2>&1
if not errorlevel 1 goto online
if !NET! GEQ 10 (
  echo   WARNING: the emulator could not resolve the Supabase host.
  echo            Running anyway. If every call fails, check the emulator's
  echo            network: cold boot it, or Extended Controls then Cellular.
  goto online
)
timeout /t 2 /nobreak >nul
goto wait_net
:online

echo.
REM Dev sign-in is an ordinary email/password account with no privilege of its
REM own - its role still comes from public.profiles. Offered only when a password
REM is set, because DEV_LOGIN=true with an empty one shows a button that cannot
REM work and reports DEV_LOGIN_NOT_CONFIGURED when tapped.
set "DEVDEFINES="
set "DEVNOTE=off - no DEV_LOGIN_PASSWORD set in this script"
if not "%DEV_LOGIN_PASSWORD%"=="" (
  set "DEVDEFINES=--dart-define=DEV_LOGIN=true --dart-define=DEV_LOGIN_EMAIL=%DEV_LOGIN_EMAIL% --dart-define=DEV_LOGIN_PASSWORD=%DEV_LOGIN_PASSWORD%"
  set "DEVNOTE=%DEV_LOGIN_EMAIL%"
)

echo   ============================================================
echo    device   !DEVICE!
echo    mode     !MODE!
echo    project  %SUPABASE_URL%
echo    dev user !DEVNOTE!
echo   ============================================================
echo.
echo    On the sign-in screen use the SECOND button - the outlined one below
echo    "Sign in with Google" - for the dev account. The Google button needs
echo    GOOGLE_SERVER_CLIENT_ID set at the top of this script AND the provider
echo    enabled in the Supabase dashboard. See docs/GOOGLE_SIGNIN.md.
echo.
echo    In the console below: r = hot reload, R = hot restart, q = quit.
echo.

call flutter run %MODE% -d !DEVICE! ^
  --dart-define=SUPABASE_URL=%SUPABASE_URL% ^
  --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY% ^
  %DEVDEFINES% ^
  --dart-define=GOOGLE_SERVER_CLIENT_ID=%GOOGLE_SERVER_CLIENT_ID%

set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo   flutter run exited with %RC%.
  echo   If that was an INSTALL_FAILED, the emulator may be out of space:
  echo     adb shell pm uninstall ly.adayl.family_app
  echo   then try again.
)
endlocal & exit /b %RC%

REM ---------------------------------------------------------------------------
REM  Writes the first running emulator's id into DEVICE.
REM
REM  Through a temp file on purpose - see trap 2 in the header. Piping adb's
REM  quoted path inside for /f returns nothing and prints a path error.
:find_device
set "DEVICE="
"%ADB%" devices > "%DEVLIST%" 2>nul
for /f "tokens=1" %%D in ('findstr /r /c:"^emulator-.*device" "%DEVLIST%"') do (
  if not defined DEVICE set "DEVICE=%%D"
)
exit /b 0

:list_avds
echo.
call flutter emulators
echo.
echo   Pass one of the Ids above as the first argument, e.g.
echo     run_emulator.bat Pixel_4_API_30
endlocal & exit /b 0
