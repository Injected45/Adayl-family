@echo off
REM ============================================================================
REM  build_apk.bat - build an Android APK for the family app, against Supabase.
REM
REM    build_apk.bat                 release APK (default)
REM    build_apk.bat --debug         debug APK
REM    build_apk.bat --profile       profile APK
REM    build_apk.bat --split         one smaller APK per ABI (arm, arm64, x86_64)
REM    build_apk.bat --no-dev-login  build WITHOUT the baked-in dev sign-in
REM    build_apk.bat --help          show this help
REM
REM ----------------------------------------------------------------------------
REM  Same Windows-batch rules as run_emulator.bat: use `call flutter`, never a
REM  bare `flutter` (it is flutter.bat, and invoking a .bat from a .bat without
REM  `call` transfers control instead of returning, so the rest never runs). This
REM  file is ASCII-only with CRLF endings so cmd cannot mis-split a line on a
REM  stray UTF-8 byte.
REM
REM  The SUPABASE_URL and SUPABASE_ANON_KEY below are NOT secrets - they ship in
REM  every build and can be read straight out of the APK. Every rule is enforced
REM  in the database by RLS and SECURITY DEFINER functions, so a hostile holder
REM  of this key can do nothing an honest one could not. The service_role key
REM  bypasses RLS and must NEVER appear here.
REM
REM  DEV LOGIN: by default this bakes the dev email/password into the APK so the
REM  app can sign in before the Google provider is enabled in Supabase. That
REM  account is an approved ADMIN, so the compiled APK then embeds an admin
REM  password - the same exposure run_emulator.bat already has, and the reason
REM  the README says to treat that password as compromised and rotate it. Pass
REM  --no-dev-login for a build without it (sign-in then needs Google set up).
REM ============================================================================
setlocal EnableDelayedExpansion

cd /d "%~dp0app"
if errorlevel 1 (
  echo Could not find the app folder next to this script.
  exit /b 1
)

set "SUPABASE_URL=https://YOUR-PROJECT-REF.supabase.co"
set "SUPABASE_ANON_KEY="

REM Development sign-in: an ordinary email/password account with NO special
REM privilege of its own - its role still comes from public.profiles. It exists
REM so the app is usable before the Google provider is switched on.
set "DEV_LOGIN_EMAIL=admin@fam.test"
set "DEV_LOGIN_PASSWORD="

REM ---- Google sign-in --------------------------------------------------------
REM Fill GOOGLE_SERVER_CLIENT_ID with the WEB client ID from Google Cloud - the
REM SAME one entered in Supabase's Google provider. It is called "server" because
REM it names the backend the ID token is destined for, and it is required on
REM Android too: without it a token verifies on the device and is then rejected
REM by Supabase, which looks like a Google failure and is not one.
REM
REM NOT a secret. It ships inside every app that offers Google sign-in, exactly
REM like the anon key above. The client SECRET is a different string and must
REM NEVER appear in this file - it belongs only in the Supabase dashboard.
REM
REM Leave it empty and the app hides the Google button rather than offering one
REM that cannot work. Android needs no GOOGLE_CLIENT_ID: it is derived from the
REM signing certificate registered in the Google Cloud console.
set "GOOGLE_SERVER_CLIENT_ID="
set "GOOGLE_CLIENT_ID="

set "MODE=--release"
set "MODENAME=release"
set "SPLIT="
set "DEVLOGIN=1"

:parse
if "%~1"=="" goto after_parse
if /i "%~1"=="--help" goto help
if /i "%~1"=="-h" goto help
if /i "%~1"=="/?" goto help
if /i "%~1"=="--debug" (
  set "MODE=--debug"
  set "MODENAME=debug"
  shift
  goto parse
)
if /i "%~1"=="--profile" (
  set "MODE=--profile"
  set "MODENAME=profile"
  shift
  goto parse
)
if /i "%~1"=="--split" (
  set "SPLIT=--split-per-abi"
  shift
  goto parse
)
if /i "%~1"=="--no-dev-login" (
  set "DEVLOGIN="
  shift
  goto parse
)
echo.
echo   Unknown argument: %~1
goto help
:after_parse

where flutter >nul 2>&1
if errorlevel 1 (
  echo.
  echo   flutter is not on PATH. Open a terminal where "flutter --version" works,
  echo   or add Flutter's bin folder to PATH.
  exit /b 1
)

REM ---- Assemble the build-time --dart-define values -------------------------
REM Built as one variable and expanded on the command line so cmd word-splits it
REM back into separate arguments. The anon key contains no cmd metacharacters, so
REM delayed expansion is safe here.
set "DEFINES=--dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%"
if defined DEVLOGIN (
  set "DEFINES=!DEFINES! --dart-define=DEV_LOGIN=true --dart-define=DEV_LOGIN_EMAIL=%DEV_LOGIN_EMAIL% --dart-define=DEV_LOGIN_PASSWORD=%DEV_LOGIN_PASSWORD%"
  set "DEVNOTE=included - admin dev account is baked into the APK"
) else (
  set "DEVNOTE=omitted - sign-in needs the Google provider enabled"
)

REM Only passed when set. An empty --dart-define would still make
REM AppConfig.isGoogleConfigured false, but passing nothing keeps the command
REM line honest about what this build actually carries.
if defined GOOGLE_SERVER_CLIENT_ID (
  set "DEFINES=!DEFINES! --dart-define=GOOGLE_SERVER_CLIENT_ID=%GOOGLE_SERVER_CLIENT_ID%"
  set "GNOTE=configured"
) else (
  set "GNOTE=NOT configured - the Google button will be hidden"
)
if defined GOOGLE_CLIENT_ID (
  set "DEFINES=!DEFINES! --dart-define=GOOGLE_CLIENT_ID=%GOOGLE_CLIENT_ID%"
)

echo.
echo   ============================================================
echo    build      apk (!MODENAME!) !SPLIT!
echo    project    %SUPABASE_URL%
echo    dev login  !DEVNOTE!
echo    google     !GNOTE!
echo   ============================================================
echo.
echo   Compiling. A clean release build can take a few minutes.
echo.

call flutter build apk %MODE% !SPLIT! !DEFINES!
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo   flutter build apk exited with %RC%.
  echo   If it complains about a missing Android SDK or licences, run:
  echo     flutter doctor
  endlocal & exit /b %RC%
)

set "OUTDIR=%CD%\build\app\outputs\flutter-apk"
echo.
echo   Build finished. APK(s) produced:
echo.
for %%F in ("%OUTDIR%\*%MODENAME%*.apk") do echo     %%~fF   (%%~zF bytes)
echo.
echo   Install on a connected device or running emulator with:
echo     adb install -r "%OUTDIR%\app-%MODENAME%.apk"
echo.
endlocal & exit /b 0

:help
echo.
echo   build_apk.bat - build an Android APK for the family app
echo.
echo     build_apk.bat                 release APK (default)
echo     build_apk.bat --debug         debug APK
echo     build_apk.bat --profile       profile APK
echo     build_apk.bat --split         one smaller APK per ABI
echo     build_apk.bat --no-dev-login  build without the baked-in dev sign-in
echo     build_apk.bat --help          this help
echo.
endlocal & exit /b 0
