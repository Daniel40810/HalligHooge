@echo off
rem HalligHooge - die App als Abbild mit eigener Java-Laufzeit (HalligHooge.exe) und gleich eine Verknuepfung auf dem
rem Desktop (Seegang Werkbuch 116; Daniel 28.11.2026: das Werkzeug gehoert ins Projekt, die Verknuepfung sofort dazu).
rem Aufruf:  tools\abbild.cmd [Version] [still]     Doppelklick: Version VER_VORGABE (unten), am Ende kurz warten.
rem   1 Abbild aus dist\HalligHooge.jar, dist\lib und src\szenen mit ..\Steuerhaus\tools\abbild.cmd (jpackage, JDK 21)
rem     nach dist\abbild\HalligHooge (die exe, app\ mit den Jars und szenen, runtime\);
rem   2 Verknuepfung "HalligHooge" auf dem Desktop auf die exe (Arbeitsordner der Ordner des Abbilds, Symbol aus der exe);
rem     eine vorhandene Verknuepfung gleichen Namens wird ersetzt.
rem Vorher bauen: tools\bauen.cmd (baut alle drei Projekte und ruft danach dieses Skript) oder Clean and Build in
rem NetBeans (das loescht dist\abbild; danach dieses Skript doppelklicken). Die App muss geschlossen sein.
rem Protokoll: docs\status\Status_Abbild.txt. Dauer rund 10 s.
rem Findet abbild.cmd kein JDK fuer jpackage, vorher setzen:  set "JDK=C:\Program Files\Java\jdk-21"
setlocal EnableExtensions
set "VER_VORGABE=2.8.1"
set "VER=%~1"
if "%VER%"=="" set "VER=%VER_VORGABE%"
set "STILL="
if /i "%~2"=="still" set "STILL=1"
for %%a in ("%~dp0..") do set "HH=%%~fa"
for %%a in ("%HH%\..") do set "P=%%~fa"
set "SH=%P%\Steuerhaus"
set "AB=%HH%\dist\abbild\HalligHooge"
set "EXE=%AB%\HalligHooge.exe"
if not defined JDK if defined JDK21 set "JDK=%JDK21%"
if not defined JDK if exist "C:\Program Files\Java\jdk-21\bin\jpackage.exe" set "JDK=C:\Program Files\Java\jdk-21"
if not exist "%HH%\docs\status" mkdir "%HH%\docs\status"
set "L=%HH%\docs\status\Status_Abbild.txt"
>"%L%" echo Abbild HalligHooge %VER% mit Verknuepfung auf dem Desktop, gestartet %DATE% %TIME%

if not exist "%SH%\tools\abbild.cmd" (
  call :meldung "%SH%\tools\abbild.cmd fehlt - Steuerhaus gehoert neben HalligHooge."
  goto :abbruch
)
if not exist "%HH%\dist\HalligHooge.jar" (
  call :meldung "dist\HalligHooge.jar fehlt - bitte erst bauen: tools\bauen.cmd"
  goto :abbruch
)
tasklist /fi "imagename eq HalligHooge.exe" 2>nul | find /i "HalligHooge.exe" >nul
if not errorlevel 1 (
  call :meldung "Die App HalligHooge.exe laeuft noch - bitte schliessen und noch einmal starten."
  goto :abbruch
)

echo [%TIME%] 1 Abbild %VER% ...
>>"%L%" echo [%DATE% %TIME%] Start 1 Abbild %VER%
call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge %VER% >>"%L%" 2>&1
set "E=%ERRORLEVEL%"
>>"%L%" echo [%DATE% %TIME%] Ende 1 Abbild - Exit %E%
if not "%E%"=="0" (
  call :meldung "Abbild fehlgeschlagen - Exit %E%"
  goto :abbruch
)
if not exist "%EXE%" (
  call :meldung "HalligHooge.exe fehlt nach dem Abbild"
  goto :abbruch
)

echo [%TIME%] 2 Verknuepfung auf dem Desktop ...
>>"%L%" echo [%DATE% %TIME%] Start 2 Verknuepfung
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d=[Environment]::GetFolderPath('Desktop'); $f=Join-Path $d 'HalligHooge.lnk'; $s=(New-Object -ComObject WScript.Shell).CreateShortcut($f); $s.TargetPath='%EXE%'; $s.WorkingDirectory='%AB%'; $s.IconLocation='%EXE%,0'; $s.Description='HalligHooge %VER%'; $s.WindowStyle=1; $s.Save(); if (-not (Test-Path $f)) { exit 2 }; 'Verknuepfung: ' + $f" >>"%L%" 2>&1
set "E=%ERRORLEVEL%"
>>"%L%" echo [%DATE% %TIME%] Ende 2 Verknuepfung - Exit %E%
if not "%E%"=="0" (
  call :meldung "Verknuepfung fehlgeschlagen - Exit %E%"
  goto :abbruch
)
>>"%L%" echo FERTIG %DATE% %TIME%
echo [%TIME%] Fertig: %EXE%
echo            Verknuepfung "HalligHooge" auf dem Desktop.
if not defined STILL timeout /t 5 >nul
exit /b 0

:meldung
echo %~1
>>"%L%" echo %~1
goto :eof

:abbruch
>>"%L%" echo ABBRUCH %DATE% %TIME%
echo Abbruch - siehe %L%
if not defined STILL pause
exit /b 1
