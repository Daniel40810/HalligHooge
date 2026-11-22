@echo off
rem HalligHooge - die Szenendateien wieder auf D: stellen (Rueckweg zu daten_umziehen.cmd, Werkbuch HalligHooge 162).
rem Holt die Sicherungen aus _to_delete\vorD1 zurueck (1_ src\szenen, 2_ build\classes\szenen, 3_ Abbild) und die
rem Einstellungen. Der Ordner daten bleibt liegen; die App liest danach wieder von D:.
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."
set "S=_to_delete\vorD1"
if not exist "%S%\1_Hooge.szenen" (
  echo %S%\1_Hooge.szenen fehlt - es gibt nichts zurueckzuholen.
  pause
  exit /b 1
)
copy /y "%S%\1_Hooge.szenen" "src\szenen\Hooge.szenen"
if exist "%S%\2_Hooge.szenen" if exist "build\classes\szenen" copy /y "%S%\2_Hooge.szenen" "build\classes\szenen\Hooge.szenen"
if exist "%S%\3_Hooge.szenen" if exist "dist\abbild\HalligHooge\app\szenen" copy /y "%S%\3_Hooge.szenen" "dist\abbild\HalligHooge\app\szenen\Hooge.szenen"
if exist "%S%\einstellungen.properties" copy /y "%S%\einstellungen.properties" "%USERPROFILE%\.steuerhaus\HalligHooge\einstellungen.properties"
echo Die App liest wieder von D:.
pause
