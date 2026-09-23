@echo off
setlocal EnableExtensions DisableDelayedExpansion
title TrustTunnel Windows Client Setup

echo ============================================================
echo   TrustTunnel Windows Client - automatic setup
echo ============================================================
echo.
echo This script will:
echo   1. Check the TrustTunnel Client folder.
echo   2. Import a tt:// deep-link.
echo   3. Generate trusttunnel_client.toml.
echo   4. Check the endpoint TCP port.
echo   5. Create START_TrustTunnel.bat.
echo.

:ASK_FOLDER
set "CLIENT_DIR="
set /p "CLIENT_DIR=Path to the TrustTunnel Client folder: "
if not defined CLIENT_DIR (
    echo [ERROR] Folder path is empty.
    echo.
    goto ASK_FOLDER
)

set "CLIENT_DIR=%CLIENT_DIR:"=%"
if not exist "%CLIENT_DIR%\" (
    echo [ERROR] Folder does not exist:
    echo         %CLIENT_DIR%
    echo.
    goto ASK_FOLDER
)

for %%I in ("%CLIENT_DIR%") do set "CLIENT_DIR=%%~fI"

echo.
echo [INFO] Checking files in:
echo        %CLIENT_DIR%

if not exist "%CLIENT_DIR%\trusttunnel_client.exe" (
    echo [ERROR] trusttunnel_client.exe was not found.
    goto FAILED
)

if not exist "%CLIENT_DIR%\setup_wizard.exe" (
    echo [ERROR] setup_wizard.exe was not found.
    goto FAILED
)

if exist "%CLIENT_DIR%\wintun.dll" (
    echo [OK] wintun.dll found in the client folder.
) else (
    where /q wintun.dll
    if errorlevel 1 (
        echo [ERROR] wintun.dll was not found in the client folder or PATH.
        echo.
        echo The official TrustTunnel CLI client needs Wintun for TUN mode on Windows.
        echo Put the correct wintun.dll next to trusttunnel_client.exe and run this setup again.
        echo Official Wintun: https://www.wintun.net/
        goto FAILED
    ) else (
        echo [OK] wintun.dll found in PATH.
    )
)

"%CLIENT_DIR%\trusttunnel_client.exe" --help >nul 2>&1
if errorlevel 1 (
    echo [ERROR] trusttunnel_client.exe could not be started.
    goto FAILED
)
echo [OK] trusttunnel_client.exe starts correctly.

"%CLIENT_DIR%\setup_wizard.exe" --help 2>&1 | findstr /I /C:"--deeplink" >nul
if errorlevel 1 (
    echo [ERROR] This setup_wizard.exe does not support --deeplink.
    echo         Update TrustTunnel Client to a current version.
    goto FAILED
)
echo [OK] setup_wizard.exe supports tt:// deep-link import.

echo.
:ASK_LINK
set "TT_LINK="
set /p "TT_LINK=Paste the tt:// link: "
if not defined TT_LINK (
    echo [ERROR] The link is empty.
    echo.
    goto ASK_LINK
)

if /I not "%TT_LINK:~0,6%"=="tt://?" (
    echo [ERROR] The value does not start with tt://?
    echo.
    goto ASK_LINK
)

echo.
echo [INFO] Generating the client configuration...

pushd "%CLIENT_DIR%" >nul
setup_wizard.exe --mode non-interactive --deeplink "%TT_LINK%" --settings "trusttunnel_client.toml"
set "WIZARD_RC=%ERRORLEVEL%"
popd >nul

if not "%WIZARD_RC%"=="0" (
    echo [ERROR] setup_wizard.exe failed with exit code %WIZARD_RC%.
    goto FAILED
)

set "CONFIG_FILE=%CLIENT_DIR%\trusttunnel_client.toml"

if not exist "%CONFIG_FILE%" (
    echo [ERROR] Configuration file was not created:
    echo         %CONFIG_FILE%
    goto FAILED
)

for %%I in ("%CONFIG_FILE%") do if %%~zI LSS 20 (
    echo [ERROR] Configuration file looks empty or damaged.
    goto FAILED
)

findstr /L /C:"[endpoint]" "%CONFIG_FILE%" >nul
if errorlevel 1 (
    echo [ERROR] The generated config has no [endpoint] section.
    goto FAILED
)

findstr /L /C:"[listener.tun]" "%CONFIG_FILE%" >nul
if errorlevel 1 (
    echo [ERROR] The generated config has no [listener.tun] section.
    goto FAILED
)

echo [OK] trusttunnel_client.toml was generated and basic sections are present.

echo.
echo [INFO] Checking the endpoint TCP port from the generated config...
set "TT_CONFIG_FILE=%CONFIG_FILE%"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$line = Get-Content -LiteralPath $env:TT_CONFIG_FILE ^| Where-Object { $_ -match '^\s*addresses\s*=' } ^| Select-Object -First 1; " ^
  "if (-not $line) { Write-Host '[WARN] Could not read endpoint address from config.'; exit 2 }; " ^
  "if ($line -notmatch '"([^"]+)"') { Write-Host '[WARN] Could not parse endpoint address.'; exit 2 }; " ^
  "$ep = $matches[1]; " ^
  "if ($ep -match '^\[(.+)\]:(\d+)$') { $h=$matches[1]; $p=[int]$matches[2] } elseif ($ep -match '^(.+):(\d+)$') { $h=$matches[1]; $p=[int]$matches[2] } else { Write-Host ('[WARN] Unknown endpoint format: ' + $ep); exit 2 }; " ^
  "Write-Host ('[INFO] Testing ' + $h + ':' + $p + ' ...'); " ^
  "$r = Test-NetConnection -ComputerName $h -Port $p -WarningAction SilentlyContinue; " ^
  "if ($r.TcpTestSucceeded) { Write-Host '[OK] Endpoint TCP port is reachable.'; exit 0 } else { Write-Host '[ERROR] Endpoint TCP port is not reachable.'; exit 1 }"

set "NET_RC=%ERRORLEVEL%"
if "%NET_RC%"=="1" (
    echo.
    echo [ERROR] Server connectivity check failed.
    echo         The config was created, but the server cannot be reached over TCP.
    goto FAILED
)
if "%NET_RC%"=="2" (
    echo [WARN] Endpoint address could not be parsed automatically.
    echo        The setup will continue because the official wizard accepted the tt:// link.
)

set "START_BAT=%CLIENT_DIR%\START_TrustTunnel.bat"

> "%START_BAT%" echo @echo off
>> "%START_BAT%" echo setlocal EnableExtensions
>> "%START_BAT%" echo title TrustTunnel Client
>> "%START_BAT%" echo cd /d "%%~dp0"
>> "%START_BAT%" echo.
>> "%START_BAT%" echo fltmc ^>nul 2^>^&1
>> "%START_BAT%" echo if errorlevel 1 ^(
>> "%START_BAT%" echo     echo Requesting Administrator privileges...
>> "%START_BAT%" echo     powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%%~f0' -Verb RunAs"
>> "%START_BAT%" echo     exit /b
>> "%START_BAT%" echo ^)
>> "%START_BAT%" echo.
>> "%START_BAT%" echo echo ============================================================
>> "%START_BAT%" echo echo   TrustTunnel Client
>> "%START_BAT%" echo echo ============================================================
>> "%START_BAT%" echo echo.
>> "%START_BAT%" echo echo TrustTunnel is running.
>> "%START_BAT%" echo echo Close this window or press Ctrl+C to stop it.
>> "%START_BAT%" echo echo.
>> "%START_BAT%" echo trusttunnel_client.exe --config "trusttunnel_client.toml"
>> "%START_BAT%" echo set "RC=%%ERRORLEVEL%%"
>> "%START_BAT%" echo echo.
>> "%START_BAT%" echo echo TrustTunnel stopped. Exit code: %%RC%%
>> "%START_BAT%" echo pause

if not exist "%START_BAT%" (
    echo [ERROR] Failed to create START_TrustTunnel.bat.
    goto FAILED
)

echo.
echo ============================================================
echo   SETUP COMPLETE
echo ============================================================
echo.
echo [OK] Client folder:
echo      %CLIENT_DIR%
echo.
echo [OK] Config:
echo      %CONFIG_FILE%
echo.
echo [OK] Launcher:
echo      %START_BAT%
echo.
echo Run START_TrustTunnel.bat whenever you want to connect.
echo It will request Administrator privileges automatically.
echo The console will stay open while TrustTunnel is running.
echo Closing it or pressing Ctrl+C stops the client.
echo.
pause
exit /b 0

:FAILED
echo.
echo ============================================================
echo   SETUP FAILED
echo ============================================================
echo.
echo Fix the error shown above and run this BAT again.
echo.
pause
exit /b 1
