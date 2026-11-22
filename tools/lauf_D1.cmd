@echo off
rem D1 Daten in die App (Werkbuch HalligHooge 162, F252-F255 A): Renderer (core.archiv: gepackte Ablage Packung,
rem Packer; Archiv liest gepackt, Vorleser entpackt in einen Vorrat; lauf: Archivquelle ohne water.eta des Nachlaufs,
rem Buehne zaehlt das Warten auf Staende; demo.DatenUmzug, demo.DatenCheck; CoreCheck 10b), Steuerhaus (Probe meldet
rem das Warten), HalligHooge bauen; CoreCheck; die Daten von D: nach HalligHooge\daten umziehen (Archive verlustfrei
rem gepackt, Gebiet kopiert, jeder Stand und jede Datei geprueft, dann daten = umgestellt); DatenCheck (neu gegen D:);
rem Mappe des Jahrs neu (Kennung mit dem neuen Ort), JahrCheck; App mit jedem Szenario 20 s aus HalligHooge\daten;
rem SteuerhausCheck; Abbild 2.3.0.
rem Erwartet: alles in Ordnung (CoreCheck 125, DatenCheck 31 Pruefsteine, JahrCheck wie Y3, SteuerhausCheck 81).
rem Ausgaben: HalligHooge\docs\status\Status_D1_*.txt, D1_Daten.md; die Daten in HalligHooge\daten (rund 16,5 GB).
rem Erwartete Dauer: rund 35 bis 45 min (das Packen liest 41 GB von D:). D: muss angeschlossen sein; C: braucht rund 22 GB frei.
rem Das Fenster der App oeffnet sich 14-mal von selbst. D: bleibt unveraendert. Rueckweg: tools\daten_zurueck.cmd.
rem Anhalten zwischen zwei Schritten: eine Datei STOPP.txt neben dieses Skript legen. Ein neuer Aufruf packt nur, was fehlt.
rem Findet abbild.cmd kein JDK fuer jpackage: hier den Pfad eintragen, etwa  set "JDK=C:\Program Files\Java\jdk-21"
set "JDK="
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

set "P=C:\Users\Dan40810\Documents\NetBeansProjects"
set "RE=%P%\Renderer"
set "SH=%P%\Steuerhaus"
set "HH=%P%\HalligHooge"
set "ST=%HH%\docs\status"
set "U=-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"
set "J=java %U% --enable-native-access=ALL-UNNAMED -Xmx12g -cp dist\HalligHooge.jar"
set "ANT=ant"
where ant >nul 2>nul || set "ANT=C:\Program Files\Apache NetBeans\extide\ant\bin\ant.bat"

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_D1_.txt"
set "L1=%ST%\Status_D1_1.txt"
set "L4=%ST%\Status_D1_4.txt"
set "L5=%ST%\Status_D1_5.txt"
set "L6=%ST%\Status_D1_6.txt"
set "L7=%ST%\Status_D1_7.txt"
set "L8=%ST%\Status_D1_8.txt"
set "L9=%ST%\Status_D1_9.txt"
set "L10=%ST%\Status_D1_10.txt"
set "E=0"
>"%UE%" echo Lauf D1 (Daten in die App), gestartet %DATE% %TIME%
>"%L1%" echo Status_D1_1: Renderer, Steuerhaus, HalligHooge bauen
>"%L4%" echo Status_D1_4: CoreCheck
>"%L5%" echo Status_D1_5: Daten umziehen (DatenUmzug)
>"%L6%" echo Status_D1_6: DatenCheck (neu gegen D:)
>"%L7%" echo Status_D1_7: Mappe des Jahrs (Ausgabe --jahr) und JahrCheck
>"%L8%" echo Status_D1_8: App mit jedem Szenario aus HalligHooge\daten
>"%L9%" echo Status_D1_9: SteuerhausCheck
>"%L10%" echo Status_D1_10: Abbild

if not exist "D:\Daten\HalligHooge\gebiet\gebiet.txt" (
  >>"%UE%" echo D:\Daten\HalligHooge\gebiet\gebiet.txt fehlt - ist D: angeschlossen?
  echo D:\Daten\HalligHooge\gebiet\gebiet.txt fehlt - ist D: angeschlossen?
  set "N=0 D: pruefen"
  goto :abbruch
)

rem ---------------------------------------------------------------- 1-3 Bauen
set "L=%L1%"
pushd "%RE%"
set "N=1 Renderer bauen (clean jar; check-packages, spirv)"
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

rem ---------------------------------------------------------------- 4 CoreCheck
set "L=%L4%"
set "N=4 CoreCheck (mit 10b: gepackt gleich ungepackt, Vorrat, Pruefsumme)"
set "C=%J% com.dan.core.demo.CoreCheck"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 5 Daten umziehen
set "L=%L5%"
set "N=5 Daten umziehen: Archive packen, Gebiet kopieren, alles pruefen, daten = umstellen (rund 15 bis 25 min)"
set "C=%J% com.dan.lauf.demo.DatenUmzug --szenen src\szenen\Hooge.szenen --nach daten --ohne "gebiet\quellen\topography_2021_ger.tif;gebiet\geschlossen" --umstellen "src\szenen\Hooge.szenen;build\classes\szenen\Hooge.szenen;dist\abbild\HalligHooge\app\szenen\Hooge.szenen" --einstellungen "%USERPROFILE%\.steuerhaus\HalligHooge\einstellungen.properties" --sicherung _to_delete\vorD1 --reserve 5"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 6 DatenCheck
set "L=%L6%"
set "N=6 DatenCheck (je Archiv neu gegen D:, Sonde, Abspielen mit Zeitraffer 1 800, Groesse)"
set "C=%J% com.dan.lauf.demo.DatenCheck --neu daten --alt D:\Daten\HalligHooge"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 7 Jahr
set "L=%L7%"
set "N=7a Ausgabe --jahr (Archive m1a, m1b, m2 aus HalligHooge\daten; nach docs\jahr)"
set "C=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus --jahr"
call :lauf
set "N=7b JahrCheck"
set "C=%J% com.dan.steuerhaus.demo.JahrCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E7=%E%"
set "E=0"

rem ---------------------------------------------------------------- 8 App mit jedem Szenario
set "L=%L8%"
for %%S in (ruhig sturm seegang ruhigsee sediment ruhigsed xaver morpho morpho2 morphosturm kimmung flugsand live livesed) do (
  set "N=8 App: Szenario %%S, 20 s"
  set "C=%J% com.dan.hallighooge.HalligHooge --szenario %%S --sekunden 20 --einstellungen docs\status\D1_einstellungen.properties"
  call :lauf
)
set "E=0"

rem ---------------------------------------------------------------- 9 SteuerhausCheck
set "L=%L9%"
set "N=9 SteuerhausCheck (Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E9=%E%"
set "E=0"

rem ---------------------------------------------------------------- 10 Abbild
set "L=%L10%"
set "N=10 Abbild 2.3.0 (dist\abbild\HalligHooge; liest die Daten aus HalligHooge\daten)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 2.3.0"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: D: abziehen, dist\abbild\HalligHooge\HalligHooge.exe starten, ein paar Szenarien und eine Sonde.
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
