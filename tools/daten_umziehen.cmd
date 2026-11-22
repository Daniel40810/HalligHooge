@echo off
rem HalligHooge - die Daten der App von D: in das Projekt umziehen (Werkbuch HalligHooge 162, D1; ersetzt Datei 143).
rem Liest aus src\szenen\Hooge.szenen, was die App ueber ${daten} braucht (Gebiet und die Archive der Szenarien),
rem packt die Archive verlustfrei (ohne die Spuren, die die App nicht liest) und kopiert das Gebiet (ohne die rohe
rem TrilaWatt-Datei und geschlossen\, die nur die Aufbereitung braucht) nach HalligHooge\daten. Jede Datei und jeder
rem Stand wird gegen das Original geprueft; erst dann werden die Szenendateien umgestellt (Sicherung in
rem _to_delete\vorD1). D: bleibt unveraendert. Ein abgebrochener Umzug macht beim naechsten Aufruf weiter.
rem Dauer: rund 10 bis 20 min (fast alles Lesen von D:). Vorher die App schliessen und bauen (dist\HalligHooge.jar).
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."
if not exist dist\HalligHooge.jar (
  echo dist\HalligHooge.jar fehlt - bitte erst bauen.
  pause
  exit /b 1
)
java -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 -Xmx12g -cp dist\HalligHooge.jar com.dan.lauf.demo.DatenUmzug ^
  --szenen src\szenen\Hooge.szenen --nach daten ^
  --ohne "gebiet\quellen\topography_2021_ger.tif;gebiet\geschlossen" ^
  --umstellen "src\szenen\Hooge.szenen;build\classes\szenen\Hooge.szenen;dist\abbild\HalligHooge\app\szenen\Hooge.szenen" ^
  --einstellungen "%USERPROFILE%\.steuerhaus\HalligHooge\einstellungen.properties" ^
  --sicherung _to_delete\vorD1 --reserve 5
set "E=%ERRORLEVEL%"
echo.
if "%E%"=="0" (
  echo Fertig. Probe ohne D::  HalligHooge.cmd --szenario sturm   oder   dist\abbild\HalligHooge\HalligHooge.exe
  echo Zurueck auf D::  tools\daten_zurueck.cmd
) else (
  echo Abbruch ^(Exit %E%^) - die Szenendateien sind unveraendert. Ein neuer Aufruf macht weiter.
)
pause
exit /b %E%
