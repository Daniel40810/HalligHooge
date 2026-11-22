@echo off
rem X5 Ton (Werkbuch HalligHooge 151): Renderer (Buehne.tonWerte), Steuerhaus (ton: Klang, Tonwerte, Ausgang, WavDatei;
rem App: Ton an/aus Strg M; Video mit Ton), HalligHooge bauen; SteuerhausCheck mit Hoerproben (X5_Ton_*.wav);
rem App zweimal (ruhiger Tag 60 s, Sturm mit Seegang 45 s; das Protokoll nennt die Werte des Tons); zwei Videos mit Ton
rem (je 10 s, 1080p); Abbild 1.5.0.
rem Ausgaben: HalligHooge\docs\status\Status_X5_*.txt, X5_Ton_ruhig.wav, X5_Ton_sturm.wav, X5_Video_*.mp4
rem Erwartete Dauer: rund 15 min. Das Fenster der App oeffnet sich zweimal von selbst (Lautsprecher an!).
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
set "UE=%ST%\Status_X5_.txt"
set "L1=%ST%\Status_X5_1.txt"
set "L4=%ST%\Status_X5_4.txt"
set "L5=%ST%\Status_X5_5.txt"
set "L6=%ST%\Status_X5_6.txt"
set "E=0"
>"%UE%" echo Lauf X5 (Ton), gestartet %DATE% %TIME%
>"%L1%" echo Status_X5_1: Renderer, Steuerhaus, HalligHooge bauen
>"%L4%" echo Status_X5_4: SteuerhausCheck mit Hoerproben
>"%L5%" echo Status_X5_5: Videos mit Ton
>"%L6%" echo Status_X5_6: App zweimal mit Ton
set "L7=%ST%\Status_X5_7.txt"
>"%L7%" echo Status_X5_7: Abbild

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
set "N=4 SteuerhausCheck (X1 bis X5, Bilder, Hoerproben)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E4=%E%"
set "E=0"

rem ---------------------------------------------------------------- 5 Videos mit Ton
set "L=%L5%"
set "A=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus --groesse 1080p --teilbilder 2 --bis 240"
set "N=5a Video mit Ton: Landunter an der Hanswarft, 10 s"
set "C=%A% --regie "Landunter an der Hanswarft" --ziel %ST%\X5_Video_Landunter.mp4"
call :lauf
set "E=0"
set "N=5b Video mit Ton: Ein Tag auf Hooge, 10 s"
set "C=%A% --regie "Ein Tag auf Hooge" --ziel %ST%\X5_Video_Tag.mp4"
call :lauf
set "E=0"
dir "%ST%\X5_*" >>"%L5%" 2>&1

rem ---------------------------------------------------------------- 6 App mit Ton
set "L=%L6%"
set "N=6a App: ruhiger Tag, 60 s, mit Ton"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario ruhig --sekunden 60 --einstellungen docs\status\X5_einstellungen.properties"
call :lauf
set "E=0"
set "N=6b App: Sturmflut mit Seegang, 45 s, mit Ton"
set "C=%J% com.dan.hallighooge.HalligHooge --szenario seegang --sekunden 45 --einstellungen docs\status\X5_einstellungen.properties"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 7 Abbild
if not "%E4%"=="0" goto :ende
set "L=%L7%"
set "N=7 Abbild 1.5.0 (dist\abbild\HalligHooge)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 1.5.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Hoerpruefung: docs\status\X5_Ton_*.wav und X5_Video_*.mp4; in der App Strg M (Ton an/aus).
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
