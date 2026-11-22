@echo off
rem X4 Postkarte (Werkbuch HalligHooge 150): Steuerhaus (ausgabe.Postkarte, Ausgabe --postkarte, Datei > Postkarte),
rem HalligHooge bauen; SteuerhausCheck mit Bildern (X4_Postkarte_1-4: Vorlagen mit gemaltem Bild); vier Postkarten aus der
rem Ausgabe (A6 Goldkante, Quadrat Weiss, 4K randlos, A6 Landunter); Abbild 1.4.0.
rem Ausgaben: HalligHooge\docs\status\Status_X4_*.txt, X4_Karte_*.png (die echten Karten), X4_Postkarte_*.png
rem Erwartete Dauer: rund 8 min. Kein Fenster oeffnet sich.
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
set "UE=%ST%\Status_X4_.txt"
set "L1=%ST%\Status_X4_1.txt"
set "L4=%ST%\Status_X4_4.txt"
set "L5=%ST%\Status_X4_5.txt"
set "L6=%ST%\Status_X4_6.txt"
set "E=0"
>"%UE%" echo Lauf X4 (Postkarte), gestartet %DATE% %TIME%
>"%L1%" echo Status_X4_1: Steuerhaus, HalligHooge bauen
>"%L4%" echo Status_X4_4: SteuerhausCheck mit Bildern
>"%L5%" echo Status_X4_5: vier Postkarten aus der Ausgabe
set "L7=%ST%\Status_X4_7.txt"
>"%L7%" echo Status_X4_7: Abbild

rem ---------------------------------------------------------------- 1-3 Bauen
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
set "N=4 SteuerhausCheck (X1 bis X4, Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E4=%E%"
set "E=0"

rem ---------------------------------------------------------------- 5 Postkarten
set "L=%L5%"
set "A=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus"
set "N=5a Postkarte A6, Goldkante: Hanswarft nach Westen, 30.10. 16:20"
set "C=%A% --postkarte a6 --vorlage 1 --blick "ruhig;2026-10-30T15:20:00Z;470900 6046615 7.65 270 -2 55" --ziel %ST%\X4_Karte_1_A6_Gold.png"
call :lauf
set "E=0"
set "N=5b Postkarte Quadrat, weiss: Deich an der Westspitze, 30.10. 12:50"
set "C=%A% --postkarte quadrat --vorlage 2 --blick "ruhig;2026-10-30T11:50:00Z;468290 6047690 4.68 259 -2 55" --ziel %ST%\X4_Karte_2_Quadrat_Weiss.png"
call :lauf
set "E=0"
set "N=5c Postkarte 4K, randlos: Vogelblick, 30.10. 14:00"
set "C=%A% --postkarte 4k --vorlage 3 --blick "ruhig;2026-10-30T13:00:00Z;470400 6044300 300 20 -30 60" --ziel %ST%\X4_Karte_3_4K_Randlos.png"
call :lauf
set "E=0"
set "N=5d Postkarte A6, Landunter: Hanswarft 25.10. 23:30"
set "C=%A% --postkarte a6 --vorlage 4 --lesezeichen "Hanswarft, Landunter 23:30" --ziel %ST%\X4_Karte_4_A6_Landunter.png"
call :lauf
set "E=0"
dir "%ST%\X4_*" >>"%L5%" 2>&1

rem ---------------------------------------------------------------- 7 Abbild
if not "%E4%"=="0" goto :ende
set "L=%L7%"
set "N=7 Abbild 1.4.0 (dist\abbild\HalligHooge)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 1.4.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: docs\status\X4_Karte_*.png ansehen; in der App Datei - Postkarte (Strg P).
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
