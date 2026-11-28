@echo off
rem K3 (Werkbuch HalligHooge 181): Pferdebusse auf Hooge - die drei Projekte bauen (mit Abbild), die Strecken rechnen
rem (--kutschen: OSM-Wege und Gelaende auf D:), GespanneCheck (Strecken, ein Tag nach der Physik, Wasser, auf Hooge mit
rem Bildern und den Vorschaubildern der drei neuen Ansichten), SteuerhausCheck.
rem Ausgaben: HalligHooge\docs\status\Status_K3_*.txt, K3_Kutschen.md, K3_*.png; src\szenen\Hooge.kutschen;
rem src\szenen\vorschau\ansicht_kutschen_anleger.png, ansicht_kutschen_hanswarft.png, ansicht_bock.png
rem Erwartete Dauer: rund 15 min. Kein Fenster der App. Netz: keins. Datenbank: nicht noetig.
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
set "UE=%ST%\Status_K3_.txt"
set "L1=%ST%\Status_K3_1.txt"
set "L2=%ST%\Status_K3_2.txt"
set "L3=%ST%\Status_K3_3.txt"
set "L4=%ST%\Status_K3_4.txt"
set "E=0"
>"%UE%" echo Lauf K3 (Pferdebusse auf Hooge), gestartet %DATE% %TIME%
>"%L1%" echo Status_K3_1: Renderer, Steuerhaus, HalligHooge bauen (tools\bauen.cmd, mit Abbild)
>"%L2%" echo Status_K3_2: Strecken der Pferdebusse rechnen (--kutschen)
>"%L3%" echo Status_K3_3: GespanneCheck
>"%L4%" echo Status_K3_4: SteuerhausCheck

rem ---------------------------------------------------------------- 1 Bauen
set "L=%L1%"
set "N=1 Bauen (Renderer, Steuerhaus, HalligHooge, Abbild)"
set "C=call "%HH%\tools\bauen.cmd" "%P%""
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 2 Strecken
set "L=%L2%"
set "N=2 Strecken der Pferdebusse (--kutschen)"
set "C=%J% com.dan.hallighooge.HalligHooge --kutschen"
call :lauf
if not "%E%"=="0" goto :abbruch
>>"%L2%" echo.
>>"%L2%" echo ---- Kopf von src\szenen\Hooge.kutschen
findstr /v /c:"achse" /c:"    " "%HH%\src\szenen\Hooge.kutschen" >>"%L2%" 2>nul

rem ---------------------------------------------------------------- 3 GespanneCheck
set "L=%L3%"
set "N=3 GespanneCheck (mit Bildern und Vorschau)"
pushd "%RE%"
set "C=%R% com.dan.lauf.demo.GespanneCheck --szenen "%HH%\src\szenen\Hooge.szenen" --vorschau "%HH%\src\szenen\vorschau""
call :lauf
popd
set "E3=%E%"
set "E=0"
if exist "%RE%\docs\status\K3_Kutschen.md" copy /y "%RE%\docs\status\K3_Kutschen.md" "%ST%\K3_Kutschen.md" >nul
for %%F in ("%RE%\docs\status\K3_*.png") do copy /y "%%F" "%ST%\" >nul

rem ---------------------------------------------------------------- 4 SteuerhausCheck
set "L=%L4%"
set "N=4 SteuerhausCheck (Manifest, Katalog, Pakete)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E4=%E%"
set "E=0"

>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME% (GespanneCheck Exit %E3%, SteuerhausCheck Exit %E4%)
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: HalligHooge.cmd - Katalog, Gruppe Kutschen; Szenario "Ruhiger Tag", Ansicht "Auf dem Bock" um 12:40 UTC.
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
