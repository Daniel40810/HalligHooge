@echo off
rem Y3 Ein Jahr in einer Minute (Werkbuch HalligHooge 154): Steuerhaus (Paket jahr: Jahresauftrag, Jahresmappe, Zeitplan,
rem Jahresbild, Jahresansicht, Jahresfenster; Ausgabe --jahr: Jahresrechnung; Menue Labor, Startseite; Knoepfe des
rem Vergleichs lesbar; demo.JahrCheck), HalligHooge bauen; SteuerhausCheck; die Mappe des Jahrs rechnen (Ausgabe --jahr,
rem Archive und Gebiet auf D:); JahrCheck; App mit dem Jahr (spielt einmal durch, 120 s); App mit dem Vergleich (Abspielen
rem ab Bild 1 messen, 40 s); Abbild 1.8.0. Der Renderer bleibt wie nach Y2 (keine Aenderung).
rem Ausgaben: HalligHooge\docs\status\Status_Y3_*.txt, Y3_Jahr_*.png, Jahr_Tag*.png; die Mappe in HalligHooge\docs\jahr
rem Erwartete Dauer: rund 10 min. Das Fenster der App oeffnet sich zweimal von selbst.
rem Anhalten zwischen zwei Schritten: eine Datei STOPP.txt neben dieses Skript legen.
rem Findet abbild.cmd kein JDK fuer jpackage: hier den Pfad eintragen, etwa  set "JDK=C:\Program Files\Java\jdk-21"
set "JDK="
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

set "P=C:\Users\Dan40810\Documents\NetBeansProjects"
set "SH=%P%\Steuerhaus"
set "HH=%P%\HalligHooge"
set "ST=%HH%\docs\status"
set "U=-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"
set "J=java %U% --enable-native-access=ALL-UNNAMED -Xmx12g -cp dist\HalligHooge.jar"
set "ANT=ant"
where ant >nul 2>nul || set "ANT=C:\Program Files\Apache NetBeans\extide\ant\bin\ant.bat"

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_Y3_.txt"
set "L1=%ST%\Status_Y3_1.txt"
set "L3=%ST%\Status_Y3_3.txt"
set "L4=%ST%\Status_Y3_4.txt"
set "L5=%ST%\Status_Y3_5.txt"
set "L6=%ST%\Status_Y3_6.txt"
set "L7=%ST%\Status_Y3_7.txt"
set "L8=%ST%\Status_Y3_8.txt"
set "E=0"
>"%UE%" echo Lauf Y3 (Ein Jahr in einer Minute), gestartet %DATE% %TIME%
>"%L1%" echo Status_Y3_1: Steuerhaus, HalligHooge bauen
>"%L3%" echo Status_Y3_3: SteuerhausCheck
>"%L4%" echo Status_Y3_4: Mappe des Jahrs rechnen (Ausgabe --jahr)
>"%L5%" echo Status_Y3_5: JahrCheck
>"%L6%" echo Status_Y3_6: App mit dem Jahr
>"%L7%" echo Status_Y3_7: App mit dem Vergleich
>"%L8%" echo Status_Y3_8: Abbild

rem ---------------------------------------------------------------- 1-2 Bauen
set "L=%L1%"
pushd "%SH%"
set "N=1 Steuerhaus bauen (clean jar)"
set "C=call "%ANT%" -f build.xml clean jar"
call :lauf
popd
if not "%E%"=="0" goto :abbruch
set "N=2 HalligHooge bauen (clean jar; ImportPruefung)"
set "C=call "%ANT%" -f build.xml clean jar"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 3 SteuerhausCheck
set "L=%L3%"
set "N=3 SteuerhausCheck (bis Y3, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E3=%E%"
set "E=0"

rem ---------------------------------------------------------------- 4 Mappe des Jahrs
set "L=%L4%"
set "N=4 Ausgabe --jahr (Archive m1a, m1b, m2; Gebiet; nach docs\jahr)"
set "C=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus --jahr"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 5 JahrCheck
set "L=%L5%"
set "N=5 JahrCheck (Mappe gegen Archive und Packung, Japsand wie P9c, Zeit je Bild, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.JahrCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E5=%E%"
set "E=0"

rem ---------------------------------------------------------------- 6 App mit dem Jahr
set "L=%L6%"
set "N=6 App: Ein Jahr in einer Minute einmal abspielen und messen, 120 s"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario morpho --jahr --sekunden 120 --einstellungen docs\status\Y3_einstellungen.properties"
call :lauf
set "E=0"
move /y "docs\fotos\Jahr_Tag*.png" "%ST%\" >>"%L6%" 2>&1

rem ---------------------------------------------------------------- 7 App mit dem Vergleich
set "L=%L7%"
set "N=7 App: Vergleich Ruhiger Tag und Sturmflut ab Bild 1 abspielen, 40 s"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario ruhig --vergleich ruhig_sturm --sekunden 40 --einstellungen docs\status\Y3_einstellungen.properties"
call :lauf
set "E=0"
move /y "docs\fotos\Vergleich_ruhig_sturm_*.png" "%ST%\" >>"%L7%" 2>&1

rem ---------------------------------------------------------------- 8 Abbild
if not "%E3%"=="0" goto :ende
set "L=%L8%"
set "N=8 Abbild 1.8.0 (dist\abbild\HalligHooge)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 1.8.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: App, Menue Labor - Ein Jahr in einer Minute (Strg Umschalt J); docs\status\Y3_Jahr_*.png
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
