@echo off
rem Y1 Vergleich mit Schieber (Werkbuch HalligHooge 152): Steuerhaus (Paket vergleich: Vergleich, Mappe, Vergleichsansicht,
rem Spieler; Ausgabe --vergleichsfolge; Labor-Menue, Kacheln "Vergleiche"), HalligHooge (Hooge.vergleiche) bauen;
rem SteuerhausCheck (Y1 Pruefsteine 1-4); die drei Vergleiche der Datei rechnen (Bildfolgen 1080p nach docs\vergleich);
rem VergleichCheck (Pruefsteine 5-9, mit Karte und Archiv); App mit dem Spieler (spielt, drei Darstellungen); Abbild 1.6.0.
rem Der Renderer bleibt unveraendert (Renderer.jar aus Lauf X5).
rem Ausgaben: HalligHooge\docs\status\Status_Y1_*.txt, Y1_Spieler_*.png, Vergleich_*.png; docs\vergleich\<Vergleich>\
rem Erwartete Dauer: rund 20 min. Das Fenster der App oeffnet sich einmal von selbst (mit dem Vergleich).
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
set "UE=%ST%\Status_Y1_.txt"
set "L1=%ST%\Status_Y1_1.txt"
set "L4=%ST%\Status_Y1_4.txt"
set "L5=%ST%\Status_Y1_5.txt"
set "L6=%ST%\Status_Y1_6.txt"
set "L7=%ST%\Status_Y1_7.txt"
set "L8=%ST%\Status_Y1_8.txt"
set "E=0"
>"%UE%" echo Lauf Y1 (Vergleich mit Schieber), gestartet %DATE% %TIME%
>"%L1%" echo Status_Y1_1: Steuerhaus, HalligHooge bauen
>"%L4%" echo Status_Y1_4: SteuerhausCheck
>"%L5%" echo Status_Y1_5: drei Vergleiche rechnen
>"%L6%" echo Status_Y1_6: VergleichCheck
>"%L7%" echo Status_Y1_7: App mit dem Spieler
>"%L8%" echo Status_Y1_8: Abbild

rem ---------------------------------------------------------------- 2-3 Bauen
set "L=%L1%"
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

rem ---------------------------------------------------------------- 4 SteuerhausCheck
set "L=%L4%"
set "N=4 SteuerhausCheck (bis Y1, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E4=%E%"
set "E=0"

rem ---------------------------------------------------------------- 5 Vergleiche rechnen
set "L=%L5%"
set "A=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus --groesse 1080p"
set "N=5a Vergleich: Ruhiger Tag und Sturmflut (Warften von oben)"
set "C=%A% --vergleichsfolge ruhig_sturm"
call :lauf
set "E=0"
set "N=5b Vergleich: Sturmflut ohne und mit Seegang (Westspitze)"
set "C=%A% --vergleichsfolge sturm_seegang"
call :lauf
set "E=0"
set "N=5c Vergleich: Sturmflut 2026 und Xaver 2013 (Hanswarft im Landunter)"
set "C=%A% --vergleichsfolge sturm_xaver"
call :lauf
set "E=0"
dir /s "docs\vergleich\*.txt" >>"%L5%" 2>&1

rem ---------------------------------------------------------------- 6 VergleichCheck
set "L=%L6%"
set "N=6 VergleichCheck (Pruefsteine 5-9, Spieler mit den echten Bildern)"
set "C=%J% com.dan.steuerhaus.demo.VergleichCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 7 App mit dem Spieler
set "L=%L7%"
set "N=7 App: Vergleich Ruhiger Tag und Sturmflut im Spieler, 45 s"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario ruhig --vergleich ruhig_sturm --sekunden 45 --einstellungen docs\status\Y1_einstellungen.properties"
call :lauf
set "E=0"
move /y "docs\fotos\Vergleich_ruhig_sturm_*.png" "%ST%\" >>"%L7%" 2>&1

rem ---------------------------------------------------------------- 8 Abbild
if not "%E4%"=="0" goto :ende
set "L=%L8%"
set "N=8 Abbild 1.6.0 (dist\abbild\HalligHooge)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 1.6.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: in der App Menue Labor oder Startseite, Gruppe "Vergleiche"; Bilder docs\status\Y1_Spieler_*.png
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
