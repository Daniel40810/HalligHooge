@echo off
rem Z3 Watt-Fenster (Werkbuch HalligHooge 158): Steuerhaus (Wattauftrag, Watttafel, Watt, Windstaumessung, Wattansicht,
rem Wattfenster; Ausgabe --watt mit Wattrechnung; App: Menue Begleiter - Watt-Fenster, Strg Umschalt W, Kachel der
rem Startseite, --wattfenster; SteuerhausCheck 6n, WattCheck 6-9), HalligHooge bauen; SteuerhausCheck; Weg und Schwellen
rem rechnen (Ausgabe --watt; nach src\szenen\Hooge.watt und src\szenen\watt\); WattCheck; App mit dem Watt-Fenster (45 s);
rem Abbild 2.2.0.
rem Erwartet: alles in Ordnung (SteuerhausCheck 81 Pruefsteine, WattCheck 4 Pruefsteine, je 0 Verstoesse).
rem Ausgaben: HalligHooge\docs\status\Status_Z3_*.txt, Z3_Watt_*.png, Watt_Fenster_*.png
rem Erwartete Dauer: rund 2 bis 3 min (Lauf Z2b: rund 2 min). Das Fenster der App oeffnet sich einmal von selbst. Fuer PEGELONLINE braucht es das Netz.
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
set "UE=%ST%\Status_Z3_.txt"
set "L1=%ST%\Status_Z3_1.txt"
set "L3=%ST%\Status_Z3_3.txt"
set "L4=%ST%\Status_Z3_4.txt"
set "L5=%ST%\Status_Z3_5.txt"
set "L6=%ST%\Status_Z3_6.txt"
set "L7=%ST%\Status_Z3_7.txt"
set "E=0"
>"%UE%" echo Lauf Z3 (Watt-Fenster), gestartet %DATE% %TIME%
>"%L1%" echo Status_Z3_1: Steuerhaus, HalligHooge bauen
>"%L3%" echo Status_Z3_3: SteuerhausCheck
>"%L4%" echo Status_Z3_4: Weg und Schwellen rechnen (Ausgabe --watt)
>"%L5%" echo Status_Z3_5: WattCheck
>"%L6%" echo Status_Z3_6: App mit dem Watt-Fenster
>"%L7%" echo Status_Z3_7: Abbild

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
set "N=3 SteuerhausCheck (bis Z3, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E3=%E%"
set "E=0"

rem ---------------------------------------------------------------- 4 Weg und Schwellen
set "L=%L4%"
set "N=4 Ausgabe --watt (Gelaende, Sattel, Weg, Schwellen aus morpho, morpho2, ruhig; nach src\szenen\Hooge.watt und watt\)"
set "C=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus --watt"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 5 WattCheck
set "L=%L5%"
set "N=5 WattCheck (Weg und Sattel, Schwellen, je Lauf mit den anderen, Fenster der Woche, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.WattCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 6 App mit dem Watt-Fenster
set "L=%L6%"
set "N=6 App: Watt-Fenster oeffnen, Woche, Niedrigwasser, Messung, eigener Wert, Bild sichern, 45 s"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario ruhig --wattfenster --sekunden 45 --einstellungen docs\status\Z3_einstellungen.properties"
call :lauf
set "E=0"
move /y "docs\fotos\Watt_Fenster_*.png" "%ST%\" >>"%L6%" 2>&1

rem ---------------------------------------------------------------- 7 Abbild
if not "%E3%"=="0" goto :ende
set "L=%L7%"
set "N=7 Abbild 2.2.0 (dist\abbild\HalligHooge; mit Hooge.watt und watt\)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 2.2.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: App, Menue Begleiter - Watt-Fenster (Strg Umschalt W); docs\status\Z3_Watt_*.png, Watt_Fenster_*.png
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
