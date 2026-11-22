@echo off
rem Z1 Tidenkalender (Werkbuch HalligHooge 155): Steuerhaus (Paket gezeiten: Gezeitenauftrag, Gezeitentafel, Vorhersage,
rem Mond, Kalenderansicht, Kalenderfenster; Ausgabe --gezeiten: Gezeitenrechnung; Menue Begleiter, Startseite;
rem demo.GezeitenCheck), HalligHooge bauen; SteuerhausCheck; die Konstanten rechnen (Ausgabe --gezeiten: Pegel Pellworm
rem Anleger und Wittduen aus gebiet\pegel, Archive morpho, morpho2, ruhig; nach src\szenen\Hooge.gezeiten); GezeitenCheck;
rem App mit dem Kalender (blaettert, sichert Bild und Liste, 40 s); Abbild 1.9.0. Der Renderer bleibt wie nach Y2.
rem Ausgaben: HalligHooge\docs\status\Status_Z1_*.txt, Z1_Kalender_*.png, Tidenkalender_*.png und .csv; src\szenen\Hooge.gezeiten
rem Erwartete Dauer: rund 7 min. Das Fenster der App oeffnet sich einmal von selbst.
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
set "UE=%ST%\Status_Z1_.txt"
set "L1=%ST%\Status_Z1_1.txt"
set "L3=%ST%\Status_Z1_3.txt"
set "L4=%ST%\Status_Z1_4.txt"
set "L5=%ST%\Status_Z1_5.txt"
set "L6=%ST%\Status_Z1_6.txt"
set "L7=%ST%\Status_Z1_7.txt"
set "E=0"
>"%UE%" echo Lauf Z1 (Tidenkalender), gestartet %DATE% %TIME%
>"%L1%" echo Status_Z1_1: Steuerhaus, HalligHooge bauen
>"%L3%" echo Status_Z1_3: SteuerhausCheck
>"%L4%" echo Status_Z1_4: Konstanten rechnen (Ausgabe --gezeiten)
>"%L5%" echo Status_Z1_5: GezeitenCheck
>"%L6%" echo Status_Z1_6: App mit dem Kalender
>"%L7%" echo Status_Z1_7: Abbild

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
set "N=3 SteuerhausCheck (bis Z1, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E3=%E%"
set "E=0"

rem ---------------------------------------------------------------- 4 Konstanten
set "L=%L4%"
set "N=4 Ausgabe --gezeiten (Pellworm Anleger, Wittduen; Archive morpho, morpho2, ruhig; nach src\szenen\Hooge.gezeiten)"
set "C=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus --gezeiten"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 5 GezeitenCheck
set "L=%L5%"
set "N=5 GezeitenCheck (Analyse, Kennwerte, Zeiten am Bezug, Uebertragung an Wittduen, Bild)"
set "C=%J% com.dan.steuerhaus.demo.GezeitenCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E5=%E%"
set "E=0"

rem ---------------------------------------------------------------- 6 App mit dem Kalender
set "L=%L6%"
set "N=6 App: Tidenkalender oeffnen, acht Wochen blaettern, Bild und Liste sichern, 40 s"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario ruhig --kalender --sekunden 40 --einstellungen docs\status\Z1_einstellungen.properties"
call :lauf
set "E=0"
move /y "docs\fotos\Tidenkalender_*.*" "%ST%\" >>"%L6%" 2>&1

rem ---------------------------------------------------------------- 7 Abbild
if not "%E3%"=="0" goto :ende
set "L=%L7%"
set "N=7 Abbild 1.9.0 (dist\abbild\HalligHooge)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 1.9.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: App, Menue Begleiter - Tidenkalender (Strg Umschalt T); docs\status\Z1_Kalender_*.png
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
