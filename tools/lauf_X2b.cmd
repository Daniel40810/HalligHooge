@echo off
rem X2b (Werkbuch HalligHooge 147): Vordergrund beim Verlassen der Startseite. Steuerhaus und HalligHooge bauen, Abbild 1.2.0.
rem Danach von Hand: HalligHooge.cmd ohne Szenario - Startseite, Kachel oder "Zur Szene" klicken.
rem Erwartete Dauer: rund 2 min. Kein Fenster der App.
set "JDK="
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."
set "P=C:\Users\Dan40810\Documents\NetBeansProjects"
set "SH=%P%\Steuerhaus"
set "HH=%P%\HalligHooge"
set "ST=%HH%\docs\status"
set "ANT=ant"
where ant >nul 2>nul || set "ANT=C:\Program Files\Apache NetBeans\extide\ant\bin\ant.bat"
if not exist "%ST%" mkdir "%ST%"
set "L=%ST%\Status_X2b.txt"
>"%L%" echo Lauf X2b, gestartet %DATE% %TIME%
pushd "%SH%"
echo [%TIME%] 1 Steuerhaus bauen
call "%ANT%" -f build.xml clean jar >>"%L%" 2>&1 || goto :abbruch
popd
echo [%TIME%] 2 HalligHooge bauen
call "%ANT%" -f build.xml clean jar >>"%L%" 2>&1 || goto :abbruch
echo [%TIME%] 3 Abbild 1.2.0
call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 1.2.0 >>"%L%" 2>&1
>>"%L%" echo FERTIG %DATE% %TIME%
echo Fertig. Jetzt HalligHooge.cmd ohne Szenario starten.
timeout /t 20 >nul
goto :eof
:abbruch
>>"%L%" echo ABBRUCH %DATE% %TIME%
echo Abbruch - siehe %L%
timeout /t 60 >nul
exit /b 1
