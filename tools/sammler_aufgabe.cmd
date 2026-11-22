@echo off
rem HalligHooge - die stuendliche Aufgabe des Messarchivs anlegen oder entfernen (DB1, Werkbuch HalligHooge 167).
rem   tools\sammler_aufgabe.cmd       anlegen oder erneuern und einmal starten (nach jedem neuen Bau des Steuerhauses wieder aufrufen)
rem   tools\sammler_aufgabe.cmd aus   entfernen (die Datenbank bleibt, wie sie ist)
rem Ohne javaw im PATH vorher den JDK setzen, etwa:  set "JDK21=C:\Program Files\Java\jdk-21"
setlocal
if /i "%~1"=="aus" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sammler_aufgabe.ps1" -Aus
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sammler_aufgabe.ps1"
)
exit /b %ERRORLEVEL%
