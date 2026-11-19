@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 (
    echo Fehler: Das App-Verzeichnis konnte nicht geoeffnet werden.
    pause
    exit /b 1
)

if not exist "%~dp0server.ps1" (
    echo Fehler: server.ps1 wurde neben Start-App.bat nicht gefunden.
    pause
    exit /b 1
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo Fehler: Windows PowerShell wurde nicht gefunden.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $client = New-Object System.Net.Sockets.TcpClient; try { $client.Connect('127.0.0.1', 8765); $client.Close(); try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/health' -TimeoutSec 3; if ($health.ready -eq $true -and $health.source -eq 'OEKOBAUDAT-CSV-Export, EN 15804+A2, Modul A1-A3') { Write-Host 'Die lokale App laeuft bereits. Oeffne sie im Browser.'; Start-Process 'http://127.0.0.1:8765/'; exit 1 }; Write-Host 'Fehler: Port 8765 wird von einem anderen Dienst verwendet. Dieser Dienst bleibt unveraendert.'; exit 2 } catch { Write-Host 'Fehler: Port 8765 ist belegt, aber die lokale App konnte nicht bestaetigt werden. Der vorhandene Dienst bleibt unveraendert.'; exit 2 } } catch [System.Net.Sockets.SocketException] { $client.Close(); if ($_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::ConnectionRefused) { exit 0 }; Write-Host 'Fehler: Port 8765 konnte nicht sicher geprueft werden. Es wird kein weiterer Server gestartet.'; exit 2 }"
set "PREFLIGHT=%ERRORLEVEL%"
if "%PREFLIGHT%"=="1" exit /b 0
if not "%PREFLIGHT%"=="0" (
    echo Die App wurde nicht gestartet. Siehe Meldung oben.
    pause
    exit /b 1
)

echo Starte die lokale App. Dieses Fenster offen lassen; Strg+C beendet den Server.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
if errorlevel 1 (
    echo Fehler: Die lokale App konnte nicht gestartet werden.
    pause
    exit /b 1
)
