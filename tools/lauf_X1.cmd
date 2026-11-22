@echo off
rem X1 Startseite und Atlas (Werkbuch HalligHooge 145): Renderer (lauf.Karte), Steuerhaus (atlas, tafel, Startseite),
rem HalligHooge bauen; den Atlas einmal aus Gebiet und Archiven rechnen (src\szenen\atlas); SteuerhausCheck mit Bildern;
rem Abbild neu. Seit X1 liegen die Laeufe der App in HalligHooge\tools (nicht mehr im Steuerhaus).
rem Ausgaben: HalligHooge\docs\status\Status_X1_*.txt, X1_Startseite_*.png
rem Erwartete Dauer: rund 15-20 min (davon der Atlas rund 10 min). Kein Fenster der App.
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
set "UE=%ST%\Status_X1_.txt"
set "L1=%ST%\Status_X1_1.txt"
set "L4=%ST%\Status_X1_4.txt"
set "L5=%ST%\Status_X1_5.txt"
set "L6=%ST%\Status_X1_6.txt"
set "E=0"
>"%UE%" echo Lauf X1 (Startseite und Atlas), gestartet %DATE% %TIME%
>"%L1%" echo Status_X1_1: Renderer, Steuerhaus, HalligHooge bauen
>"%L4%" echo Status_X1_4: Atlas rechnen
>"%L5%" echo Status_X1_5: SteuerhausCheck mit Bildern
>"%L6%" echo Status_X1_6: Abbild

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
set "N=4 Atlas rechnen (--atlas; Gebiet und Archive auf D:)"
set "C=%J% com.dan.hallighooge.HalligHooge --atlas"
call :lauf
set "E4=%E%"
set "E=0"
dir "%HH%\src\szenen\atlas" >>"%L4%" 2>&1

rem ---------------------------------------------------------------- 5 SteuerhausCheck
set "L=%L5%"
set "N=5 SteuerhausCheck (X1 Pruefsteine 1-5, Bilder der Startseite)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 6 Abbild
if not "%E4%"=="0" goto :ende
set "L=%L6%"
set "N=6 Abbild mit Startseite (dist\abbild\HalligHooge)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 1.1.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: HalligHooge.cmd ohne Szenario starten - die Startseite kommt.
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
