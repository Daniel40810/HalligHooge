@echo off
rem K4b (Werkbuch HalligHooge 183): Nachlauf zu K4 nach den Befunden aus Lauf K4 - Halteplaetze im Gelaende (Suche 80 m),
rem PferdebusCheck mit der Flotte je Bild, SteuerhausCheck kennt Rundgaenge auf dem Bock. Schritte: 1 bauen (mit Abbild);
rem 5 GespanneCheck (mit Bildern und Vorschau); 6 PferdebusCheck (Rundgang, Weiter ohne Sprung, Postkarte A6); 7 SteuerhausCheck.
rem Ausgaben: HalligHooge\docs\status\Status_K4b_*.txt, K3_Kutschen.md, K3_*.png, K4_Postkarte_vom_Bock.png
rem Erwartete Dauer: rund 18 min. Kein Fenster. Netz: keins.
rem Anhalten zwischen zwei Schritten: eine Datei STOPP.txt neben dieses Skript legen.
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

set "P=C:\Users\Dan40810\Documents\NetBeansProjects"
set "SH=%P%\Steuerhaus"
set "HH=%P%\HalligHooge"
set "RE=%P%\Renderer"
set "ST=%HH%\docs\status"
set "U=-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"
set "J=java %U% --enable-native-access=ALL-UNNAMED -Xmx12g -cp dist\HalligHooge.jar"
set "R=java %U% --enable-native-access=ALL-UNNAMED -Xmx12g -cp dist\Renderer.jar"

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_K4b_.txt"
set "E=0"
>"%UE%" echo Lauf K4b (Nachlauf Pferdebusse), gestartet %DATE% %TIME%
for %%N in (1 5 6 7) do >"%ST%\Status_K4b_%%N.txt" echo Status_K4b_%%N

rem ---------------------------------------------------------------- 1 Bauen
set "L=%ST%\Status_K4b_1.txt"
set "N=1 Bauen (Renderer, Steuerhaus, HalligHooge, Abbild)"
set "C=call "%HH%\tools\bauen.cmd" "%P%""
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 5 GespanneCheck
set "L=%ST%\Status_K4b_5.txt"
set "N=5 GespanneCheck (mit Bildern und Vorschau)"
pushd "%RE%"
set "C=%R% com.dan.lauf.demo.GespanneCheck --szenen "%HH%\src\szenen\Hooge.szenen" --vorschau "%HH%\src\szenen\vorschau""
call :lauf
popd
set "E5=%E%"
set "E=0"
if exist "%RE%\docs\status\K3_Kutschen.md" copy /y "%RE%\docs\status\K3_Kutschen.md" "%ST%\K3_Kutschen.md" >nul
for %%F in ("%RE%\docs\status\K3_*.png") do copy /y "%%F" "%ST%\" >nul

rem ---------------------------------------------------------------- 6 PferdebusCheck
set "L=%ST%\Status_K4b_6.txt"
set "N=6 PferdebusCheck (Rundgang, Weiter ohne Sprung, Postkarte A6)"
set "C=%J% com.dan.steuerhaus.demo.PferdebusCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E6=%E%"
set "E=0"

rem ---------------------------------------------------------------- 7 SteuerhausCheck
set "L=%ST%\Status_K4b_7.txt"
set "N=7 SteuerhausCheck (Manifest, Katalog, Rundgaenge, Pakete)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E7=%E%"
set "E=0"

>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME% (Gespanne %E5%, Pferdebus %E6%, Steuerhaus %E7%)
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: docs\status\K4_Postkarte_vom_Bock.png
timeout /t 30 >nul
goto :eof

:abbruch
>>"%UE%" echo.
>>"%UE%" echo ABBRUCH %DATE% %TIME% nach: %N%
echo.
echo Abbruch nach: %N%  - siehe %L%
timeout /t 60 >nul
exit /b 1

:lauf
if not exist "%~dp0STOPP.txt" goto :lauf2
echo [%DATE% %TIME%] STOPP  %N%
>>"%UE%" echo [%DATE% %TIME%] STOPP  %N%  - uebersprungen
set "E=99"
goto :eof
:lauf2
echo [%DATE% %TIME%] Start  %N%
>>"%UE%" echo [%DATE% %TIME%] Start  %N%
>>"%L%" echo.
>>"%L%" echo ^>%C%
%C% >>"%L%" 2>&1
set "E=%ERRORLEVEL%"
echo [%DATE% %TIME%] Ende   %N%  - Exit %E%
>>"%UE%" echo [%DATE% %TIME%] Ende   %N%  - Exit %E%
goto :eof
