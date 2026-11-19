@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 (
    echo Fehler: Das App-Verzeichnis konnte nicht geoeffnet werden.
    pause
    exit /b 1
)

where git.exe >nul 2>nul
if errorlevel 1 (
    echo Fehler: Git wurde nicht gefunden. Die App wird nicht gestartet.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$repo = (Get-Location).Path; & git -C $repo rev-parse --show-toplevel 2>$null | Out-Null; if ($LASTEXITCODE -ne 0) { Write-Host 'Fehler: Dieses Verzeichnis ist kein Git-Repository. Die App wird nicht gestartet.'; exit 10 }; $branch = & git -C $repo branch --show-current 2>$null; if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { Write-Host ('Fehler: Automatische Aktualisierungen sind nur auf main erlaubt (aktuell: ' + $branch + '). Die App wird nicht gestartet.'); exit 11 }; $changes = & git -C $repo status --porcelain --untracked-files=all 2>$null; if ($LASTEXITCODE -ne 0) { Write-Host 'Fehler: Der Git-Arbeitsbaum konnte nicht geprueft werden. Die App wird nicht gestartet.'; exit 12 }; if ($changes) { Write-Host 'Fehler: Lokale Aenderungen gefunden. Es wurde nichts aktualisiert, damit keine Arbeit ueberschrieben wird. Bitte Aenderungen sichern und erneut starten.'; exit 13 }; Write-Host 'Suche nach einer neueren Version...'; & git -C $repo fetch --quiet origin main 2>$null; if ($LASTEXITCODE -ne 0) { Write-Host 'Fehler: git fetch origin main ist fehlgeschlagen. Kein aktueller Stand ist garantiert; die App wird nicht gestartet.'; exit 14 }; & git -C $repo merge --quiet --ff-only origin/main 2>$null; if ($LASTEXITCODE -ne 0) { Write-Host 'Fehler: main konnte nicht sicher per Fast-Forward aktualisiert werden. Es wurde nichts erzwungen; die App wird nicht gestartet.'; exit 15 }; Write-Host 'Die lokale App ist auf dem neuesten Stand.'; exit 0"
if errorlevel 1 (
    echo Die App wurde nicht gestartet. Siehe Meldung oben.
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

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $client = New-Object System.Net.Sockets.TcpClient; try { $client.Connect('127.0.0.1', 8765); $client.Close(); try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/health' -TimeoutSec 3; if ($health.ready -eq $true -and $health.datasetLoaded -eq $true) { Write-Host 'Die lokale App laeuft bereits. Oeffne sie im Browser.'; Start-Process 'http://127.0.0.1:8765/'; exit 1 }; Write-Host 'Fehler: Port 8765 wird von einem anderen Dienst verwendet. Dieser Dienst bleibt unveraendert.'; exit 2 } catch { Write-Host 'Fehler: Port 8765 ist belegt, aber die lokale App konnte nicht bestaetigt werden. Der vorhandene Dienst bleibt unveraendert.'; exit 2 } } catch [System.Net.Sockets.SocketException] { $client.Close(); if ($_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::ConnectionRefused) { exit 0 }; Write-Host 'Fehler: Port 8765 konnte nicht sicher geprueft werden. Es wird kein weiterer Server gestartet.'; exit 2 }"
set "PREFLIGHT=%ERRORLEVEL%"
rem Preflight exit 1 means a valid app is already running; 0 means start it.
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
