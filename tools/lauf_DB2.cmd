@echo off
rem DB2 Chronik der Hochwasser (Werkbuch HalligHooge 169, F266 A, F267 A): Steuerhaus (Kern: Chronik; messung: Chronikbau,
rem Sammler --chronik, --wind-nachladen, --fach-weg; neues Paket chronik: Abdeckung, Chronikansicht, Chronikfenster;
rem Szenenapp: Menue Labor > Chronik der Hochwasser (Strg Umschalt H), Kachel auf der Startseite, Landunter-Uhr mit der Zeile
rem der Chronik und dem gemessenen Windstau zur Wahl; demo.ChronikCheck) und HalligHooge (chronik.* im Manifest, Fassung 2.4,
rem HH_FUELLSTAND_V je Tabelle, Stufe 2) bauen; MessungCheck; Schema auf Stufe 2; das Fach 2009 der Mittel weg (4 Werte vom
rem 31.12.2009); Wind 2020 bis 2025 aus den historischen Dateien des DWD nachladen; Abruf (schreibt Hooge.chronik); die Chronik
rem noch einmal (erwartet: unveraendert); Abbild 2.4.0 (mit der Chronik); ChronikCheck mit Bildern; SteuerhausCheck;
rem Bericht; die Aufgabe mit den neuen Jars erneuern.
rem Erwartet: MessungCheck 12, Einrichten "alles in Ordnung" (Stufe 2), ChronikCheck 5 ohne Verstoss, SteuerhausCheck wie D1.
rem Ausgaben: HalligHooge\docs\status\Status_DB2_*.txt, DB2_Chronik_Labor.png, DB2_Chronik_Nautik.png, DB2_Landunter.png.
rem Erwartete Dauer: rund 10 bis 20 min (Wind: zwei ZIP des DWD, rund 1,3 Mio. Werte; Abbild; SteuerhausCheck).
rem Netz: PEGELONLINE und opendata.dwd.de. Die Oracle-Datenbank muss laufen.
rem Anhalten zwischen zwei Schritten: eine Datei STOPP.txt neben dieses Skript legen.
rem Findet abbild.cmd kein JDK fuer jpackage: hier den Pfad eintragen, etwa  set "JDK=C:\Program Files\Java\jdk-21"
set "JDK="
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

for %%a in ("%~dp0..\..") do set "P=%%~fa"
set "SH=%P%\Steuerhaus"
set "HH=%P%\HalligHooge"
set "ST=%HH%\docs\status"
set "U=-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"
set "J=java %U% --enable-native-access=ALL-UNNAMED -Xmx12g -cp dist\HalligHooge.jar"
set "SAM=java %U% -cp dist\HalligHooge.jar com.dan.steuerhaus.messung.Sammler --manifest src\szenen\Hooge.steuerhaus"
set "ANT=ant"
where ant >nul 2>nul || set "ANT=C:\Program Files\Apache NetBeans\extide\ant\bin\ant.bat"

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_DB2_.txt"
set "L1=%ST%\Status_DB2_1.txt"
set "L3=%ST%\Status_DB2_3.txt"
set "L4=%ST%\Status_DB2_4.txt"
set "L5=%ST%\Status_DB2_5.txt"
set "L7=%ST%\Status_DB2_7.txt"
set "L9=%ST%\Status_DB2_9.txt"
set "L10=%ST%\Status_DB2_10.txt"
set "L11=%ST%\Status_DB2_11.txt"
set "L12=%ST%\Status_DB2_12.txt"
set "L13=%ST%\Status_DB2_13.txt"
set "E=0"
set "E4=-" & set "E10=-" & set "E11=-" & set "E13=-"
>"%UE%" echo Lauf DB2 (Chronik der Hochwasser), gestartet %DATE% %TIME%
>"%L1%" echo Status_DB2_1: Steuerhaus und HalligHooge bauen
>"%L3%" echo Status_DB2_3: MessungCheck (ohne Datenbank)
>"%L4%" echo Status_DB2_4: Schema auf Stufe 2
>"%L5%" echo Status_DB2_5: Fach 2009 weg, Wind 2020 bis 2025 nachladen
>"%L7%" echo Status_DB2_7: Abruf mit Chronik, Chronik noch einmal
>"%L9%" echo Status_DB2_9: Abbild 2.4.0
>"%L10%" echo Status_DB2_10: ChronikCheck (Bilder)
>"%L11%" echo Status_DB2_11: SteuerhausCheck (Bilder)
>"%L12%" echo Status_DB2_12: Bericht
>"%L13%" echo Status_DB2_13: Aufgabe mit den neuen Jars

rem ---------------------------------------------------------------- 1-2 Bauen
set "L=%L1%"
pushd "%SH%"
set "N=1 Steuerhaus bauen (clean jar)"
set "C=call "%ANT%" -f build.xml clean jar"
call :lauf
popd
if not "%E%"=="0" goto :abbruch
copy /y "%SH%\dist\Steuerhaus.jar" "%HH%\lib\Steuerhaus.jar" >>"%L1%" 2>&1
set "N=2 HalligHooge bauen (clean jar; ImportPruefung)"
set "C=call "%ANT%" -f build.xml clean jar"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 3 MessungCheck
set "L=%L3%"
set "N=3 MessungCheck (mit 8-11: Chronik, Ereignisse, Liste des DWD, Abdeckung)"
set "C=java %U% -cp dist\HalligHooge.jar com.dan.steuerhaus.demo.MessungCheck --manifest src\szenen\Hooge.steuerhaus --gebiet daten\gebiet --quellen ..\Steuerhaus\src"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 4 Schema
set "L=%L4%"
set "N=4 Schema auf Stufe 2 (HH_FUELLSTAND_V je Tabelle)"
set "C=%SAM% --einrichten"
call :lauf
set "E4=%E%"
set "E=0"

rem ---------------------------------------------------------------- 5-6 Fach 2009, Wind
set "L=%L5%"
set "N=5 Fach 2009 der Mittel weg (4 Windwerte vom 31.12.2009)"
set "C=%SAM% --fach-weg MITTEL 2009-01-01"
call :lauf
set "E=0"
set "N=6 Wind 2020 bis 2025 aus den historischen Dateien des DWD nachladen"
set "C=%SAM% --wind-nachladen"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 7-8 Abruf, Chronik
set "L=%L7%"
set "N=7 Abruf (schreibt die Chronik Hooge.chronik)"
set "C=%SAM% --abruf"
call :lauf
set "E=0"
set "N=8 Chronik noch einmal (erwartet: unveraendert)"
set "C=%SAM% --chronik"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 9 Abbild
set "L=%L9%"
set "N=9 Abbild 2.4.0 (dist\abbild\HalligHooge, mit der Chronik in app\szenen)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 2.4.0"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 10-11 Pruefungen mit Bildern
set "L=%L10%"
set "N=10 ChronikCheck (Chronik, Abdeckung, Ansicht in beiden Themen, Landunter-Uhr, Kopie im Abbild)"
set "C=%J% com.dan.steuerhaus.demo.ChronikCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E10=%E%"
set "E=0"
set "L=%L11%"
set "N=11 SteuerhausCheck (Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E11=%E%"
set "E=0"

rem ---------------------------------------------------------------- 12 Bericht
set "L=%L12%"
set "N=12 Bericht (Fuellstand je Tabelle, Faecher, Abrufe)"
set "C=%SAM% --bericht"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 13 Aufgabe
set "L=%L13%"
set "N=13 Aufgabe HalligHooge Messarchiv mit den neuen Jars"
set "C=call "%~dp0sammler_aufgabe.cmd""
call :lauf
set "E13=%E%"
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo Exit: Einrichten %E4%, ChronikCheck %E10%, SteuerhausCheck %E11%, Aufgabe %E13%
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: HalligHooge.cmd, Menue Labor ^> Chronik der Hochwasser (Strg Umschalt H), Knopf "Ansehen" beim Landunter;
echo dazu die Landunter-Uhr (Strg Umschalt U) mit der Zeile "Zuletzt Landunter ..." und die Bilder DB2_*.png in docs\status.
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
