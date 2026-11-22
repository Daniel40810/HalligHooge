@echo off
rem X3 Rundgang (Werkbuch HalligHooge 148): Renderer (Wegenetz), Steuerhaus (rundgang, Regisseur: umsehen, unterwegs),
rem HalligHooge bauen; Wege der Rundgaenge rechnen (--wege: OSM und Gelaende auf D:); SteuerhausCheck mit Bildern;
rem App zweimal: Rundgang "Von Warft zu Warft" 150 s und "Landunter mit dem Boot" 100 s (alle 12 s weiter); Abbild 1.3.0.
rem Ausgaben: HalligHooge\docs\status\Status_X3_*.txt, HalligHooge\src\szenen\rundgang\*.weg
rem Erwartete Dauer: rund 12 min. Das Fenster der App oeffnet sich zweimal von selbst (rund 3 und 2 min).
rem Anhalten zwischen zwei Schritten: eine Datei STOPP.txt neben dieses Skript legen.
rem Findet abbild.cmd kein JDK fuer jpackage: hier den Pfad eintragen, etwa  set "JDK=C:\Program Files\Java\jdk-21"
set "JDK="
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
set "ANT=ant"
where ant >nul 2>nul || set "ANT=C:\Program Files\Apache NetBeans\extide\ant\bin\ant.bat"

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_X3_.txt"
set "L1=%ST%\Status_X3_1.txt"
set "L4=%ST%\Status_X3_4.txt"
set "L5=%ST%\Status_X3_5.txt"
set "L6=%ST%\Status_X3_6.txt"
set "E=0"
>"%UE%" echo Lauf X3 (Rundgang), gestartet %DATE% %TIME%
>"%L1%" echo Status_X3_1: Renderer, Steuerhaus, HalligHooge bauen
>"%L4%" echo Status_X3_4: Wege der Rundgaenge rechnen
>"%L5%" echo Status_X3_5: SteuerhausCheck mit Bildern
>"%L6%" echo Status_X3_6: App mit zwei Rundgaengen
set "L7=%ST%\Status_X3_7.txt"
>"%L7%" echo Status_X3_7: Abbild

rem ---------------------------------------------------------------- 1-3 Bauen
set "L=%L1%"
pushd "%RE%"
set "N=1 Renderer bauen (clean jar; check-packages)"
set "C=call "%ANT%" -f build.xml clean jar"
call :lauf
popd
if not "%E%"=="0" goto :abbruch
copy /y "%RE%\dist\Renderer.jar" "%SH%\lib\Renderer.jar" >>"%L1%" 2>&1
copy /y "%RE%\dist\Renderer.jar" "%HH%\lib\Renderer.jar" >>"%L1%" 2>&1
pushd "%SH%"
set "N=2 Steuerhaus bauen (clean jar)"
set "C=call "%ANT%" -f build.xml clean jar"
call :lauf
popd
if not "%E%"=="0" goto :abbruch
set "N=3 HalligHooge bauen (clean jar; ImportPruefung)"
set "C=call "%ANT%" -f build.xml clean jar"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 4 Atlas rechnen
set "L=%L4%"
set "N=4 Wege der Rundgaenge rechnen (--wege)"
set "C=%J% com.dan.hallighooge.HalligHooge --wege"
call :lauf
set "E4=%E%"
set "E=0"
dir "%HH%\src\szenen\rundgang" >>"%L4%" 2>&1
for %%W in ("%HH%\src\szenen\rundgang\*.weg") do (
  >>"%L4%" echo.
  >>"%L4%" echo ---- %%~nxW: Kopf und Zeilen
  findstr /v /r "^[0-9]*:[0-9.]* [0-9][0-9][0-9][0-9][0-9][0-9]" "%%W" >>"%L4%" 2>nul
)

rem ---------------------------------------------------------------- 5 SteuerhausCheck
set "L=%L5%"
set "N=5 SteuerhausCheck (X1, X2, X3, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 6 App mit Kapitel 1
set "L=%L6%"
set "N=6a App: Rundgang Von Warft zu Warft, 150 s, alle 12 s weiter"
if exist "%ST%\protokoll.txt" del /q "%ST%\protokoll.txt"
set "C=%J% com.dan.hallighooge.HalligHooge --rundgang warften --sekunden 150 --einstellungen docs\status\X3_einstellungen.properties"
call :lauf
set "E=0"
set "N=6b App: Rundgang Landunter mit dem Boot, 100 s, alle 12 s weiter"
set "C=%J% com.dan.hallighooge.HalligHooge --rundgang landunter --sekunden 100 --einstellungen docs\status\X3_einstellungen.properties"
call :lauf
set "E=0"
if exist "%ST%\protokoll.txt" (
  >>"%L6%" echo Protokoll:
  type "%ST%\protokoll.txt" >>"%L6%" 2>nul
)

rem ---------------------------------------------------------------- 7 Abbild
if not "%E4%"=="0" goto :ende
set "L=%L7%"
set "N=7 Abbild 1.3.0 (dist\abbild\HalligHooge)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 1.3.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: HalligHooge.cmd - Startseite, Gruppe Rundgaenge, einen Rundgang gehen, unterwegs mit der Maus umsehen.
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
