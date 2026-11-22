@echo off
rem Y2 Regler im Live-Lauf (Werkbuch HalligHooge 153): Renderer (Antrieb 0.5: Wind mal Faktor und gedreht; HydroModul 0.7
rem und Einseitig: Aufschlag am Rand von G2; Buehne.regler, reglerIst; demo.ReglerCheck), Steuerhaus (Paket regler:
rem Reglerwerte, Reglerpult; Arbeitsbereich Labor, Strg 5; Eingriffe in der Zeitleiste; Spieler des Vergleichs liest
rem voraus), HalligHooge bauen; SteuerhausCheck; ReglerCheck (drei Laeufe wie live, je 7 h Modellzeit, auf der Karte);
rem App live mit Reglern (120 s); App mit dem Vergleich (Abspielen messen, 40 s); Abbild 1.7.0.
rem Ausgaben: HalligHooge\docs\status\Status_Y2_*.txt, Y2_Regler.md, Y2_Reglerpult_*.png
rem Erwartete Dauer: rund 20 min. Das Fenster der App oeffnet sich zweimal von selbst.
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
set "GB=D:\Daten\HalligHooge\gebiet"
set "ST=%HH%\docs\status"
set "U=-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"
set "J=java %U% --enable-native-access=ALL-UNNAMED -Xmx12g -cp dist\HalligHooge.jar"
set "ANT=ant"
where ant >nul 2>nul || set "ANT=C:\Program Files\Apache NetBeans\extide\ant\bin\ant.bat"

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_Y2_.txt"
set "L1=%ST%\Status_Y2_1.txt"
set "L4=%ST%\Status_Y2_4.txt"
set "L5=%ST%\Status_Y2_5.txt"
set "L6=%ST%\Status_Y2_6.txt"
set "L7=%ST%\Status_Y2_7.txt"
set "L8=%ST%\Status_Y2_8.txt"
set "E=0"
>"%UE%" echo Lauf Y2 (Regler im Live-Lauf), gestartet %DATE% %TIME%
>"%L1%" echo Status_Y2_1: Renderer, Steuerhaus, HalligHooge bauen
>"%L4%" echo Status_Y2_4: SteuerhausCheck
>"%L5%" echo Status_Y2_5: ReglerCheck
>"%L6%" echo Status_Y2_6: App live mit Reglern
>"%L7%" echo Status_Y2_7: App mit dem Vergleich
>"%L8%" echo Status_Y2_8: Abbild

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

rem ---------------------------------------------------------------- 4 SteuerhausCheck
set "L=%L4%"
set "N=4 SteuerhausCheck (bis Y2, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E4=%E%"
set "E=0"

rem ---------------------------------------------------------------- 5 ReglerCheck
set "L=%L5%"
set "N=5 ReglerCheck (drei Laeufe wie live, je 7 h, Karte)"
set "C=%J% com.dan.lauf.demo.ReglerCheck --gebiet %GB%"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 6 App live mit Reglern
set "L=%L6%"
set "N=6 App: live, Regler Wind x2 +30 Grad, Aufschlag +1,5 m, Meeresspiegel +0,5 m, 120 s"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario live --arbeitsbereich labor --regler "wind=2;drehung=30;aufschlag=1.5;meer=0.5" --sekunden 120 --einstellungen docs\status\Y2_einstellungen.properties"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 7 App mit dem Vergleich
set "L=%L7%"
set "N=7 App: Vergleich Ruhiger Tag und Sturmflut abspielen, 40 s"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario ruhig --vergleich ruhig_sturm --sekunden 40 --einstellungen docs\status\Y2_einstellungen.properties"
call :lauf
set "E=0"
move /y "docs\fotos\Vergleich_ruhig_sturm_*.png" "%ST%\" >>"%L7%" 2>&1

rem ---------------------------------------------------------------- 8 Abbild
if not "%E4%"=="0" goto :ende
set "L=%L8%"
set "N=8 Abbild 1.7.0 (dist\abbild\HalligHooge)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 1.7.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: App, Arbeitsbereich Labor (Strg 5), Live-Lauf, Regler ziehen; docs\status\Y2_Reglerpult_*.png
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
