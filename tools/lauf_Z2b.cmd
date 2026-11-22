@echo off
rem Z2b Windstau als Mittel (Werkbuch HalligHooge 157; F250 A): Steuerhaus (Gezeitentafel mit zwei Pegeln des Windstaus,
rem Gezeitenrechnung schreibt Wittduen als bezug2 und den Fehler des Mittels; Landunteruhr laedt beide Pegel, zeigt den
rem Windstau beider und ihr Mittel; Layout fuer kleine Fenster; SteuerhausCheck 6m, LandunterCheck 6-9 angepasst),
rem HalligHooge bauen; SteuerhausCheck; Konstanten neu rechnen (Ausgabe --gezeiten; nach src\szenen\Hooge.gezeiten);
rem GezeitenCheck; LandunterCheck; App mit der Uhr (45 s); Abbild 2.1.0.
rem Erwartet: alles in Ordnung (LandunterCheck 4 Pruefsteine, 0 Verstoesse).
rem Ausgaben: HalligHooge\docs\status\Status_Z2b_*.txt, Z2_Landunter_*.png, Z2b_Landunter_klein.png, Landunter_Uhr_*.png
rem Erwartete Dauer: rund 2 min (Lauf Z2: 1 min 45 s). Das Fenster der App oeffnet sich einmal von selbst. Fuer PEGELONLINE braucht es das Netz.
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
set "UE=%ST%\Status_Z2b_.txt"
set "L1=%ST%\Status_Z2b_1.txt"
set "L3=%ST%\Status_Z2b_3.txt"
set "L4=%ST%\Status_Z2b_4.txt"
set "L5=%ST%\Status_Z2b_5.txt"
set "L6=%ST%\Status_Z2b_6.txt"
set "L7=%ST%\Status_Z2b_7.txt"
set "L8=%ST%\Status_Z2b_8.txt"
set "E=0"
>"%UE%" echo Lauf Z2b (Windstau als Mittel), gestartet %DATE% %TIME%
>"%L1%" echo Status_Z2b_1: Steuerhaus, HalligHooge bauen
>"%L3%" echo Status_Z2b_3: SteuerhausCheck
>"%L4%" echo Status_Z2b_4: Konstanten rechnen (Ausgabe --gezeiten)
>"%L5%" echo Status_Z2b_5: GezeitenCheck
>"%L6%" echo Status_Z2b_6: LandunterCheck
>"%L7%" echo Status_Z2b_7: App mit der Landunter-Uhr
>"%L8%" echo Status_Z2b_8: Abbild

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
set "N=3 SteuerhausCheck (bis Z2b, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E3=%E%"
set "E=0"

rem ---------------------------------------------------------------- 4 Konstanten
set "L=%L4%"
set "N=4 Ausgabe --gezeiten (dazu Wittduen als zweiter Pegel und der Fehler des Mittels; nach src\szenen\Hooge.gezeiten)"
set "C=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus --gezeiten"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 5 GezeitenCheck
set "L=%L5%"
set "N=5 GezeitenCheck (Z1 unveraendert: Analyse, Kennwerte, Zeiten, Uebertragung, Bild)"
set "C=%J% com.dan.steuerhaus.demo.GezeitenCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 6 LandunterCheck
set "L=%L6%"
set "N=6 LandunterCheck (zwei Pegel, Windstau als Mittel, Mittel gegen jeden Pegel, Badewanne seegang und xaver, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.LandunterCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 7 App mit der Landunter-Uhr
set "L=%L7%"
set "N=7 App: Landunter-Uhr oeffnen, beide Pegel laden, jede Wahl, eigener Wert, Bild sichern, 45 s"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario ruhig --landunter --sekunden 45 --einstellungen docs\status\Z2b_einstellungen.properties"
call :lauf
set "E=0"
move /y "docs\fotos\Landunter_Uhr_*.png" "%ST%\" >>"%L7%" 2>&1

rem ---------------------------------------------------------------- 8 Abbild
if not "%E3%"=="0" goto :ende
set "L=%L8%"
set "N=8 Abbild 2.1.0 (dist\abbild\HalligHooge)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 2.1.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: App, Menue Begleiter - Landunter-Uhr (Strg Umschalt U); docs\status\Z2_Landunter_*.png, Z2b_Landunter_klein.png
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
