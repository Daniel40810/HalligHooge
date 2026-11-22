@echo off
rem DB4 Antrieb gegen Messung (Werkbuch HalligHooge 173, F272-F275 A): Steuerhaus (Kern Guete mit Wind und Mittelwasser;
rem ausgabe.Modellauszug liest den Wind des Archivs an List und Helgoland; messung.Guetebau: HH_MODELL_WIND, HH_GUETE_WIND,
rem Mittelwasser und Tidemittel in HH_GUETE, Kennzahlen des Winds; Gueteansicht mit Umschalter Wasserstand / Wind; MessungCheck 16,
rem GueteCheck 8-9) und HalligHooge (Schema Stufe 4, guete.wind*, guete.mittelwasser.tage, Fassung 2.6) bauen; MessungCheck;
rem Schema auf Stufe 4; die Archive mit dem Wind lesen (alle Laeufe bekommen eine neue Kennung); Sammler --guete (Laeufe ersetzt,
rem Kennzahlen mit Wind und Mittelwasser, src\szenen\Hooge.guete); noch einmal (erwartet: unveraendert); Abbild 2.6.0;
rem GueteCheck mit Bildern; SteuerhausCheck; Bericht; die Aufgabe mit den neuen Jars erneuern.
rem Erwartet: MessungCheck 17, Einrichten "alles in Ordnung" (Stufe 4), GueteCheck 9 ohne Verstoss, SteuerhausCheck wie DB3.
rem Ausgaben: HalligHooge\docs\status\Status_DB4_*.txt, DB4_Guete_Labor.png, DB4_Guete_Nautik.png, DB4_Guete_Xaver.png, DB4_Guete_Wind.png.
rem Erwartete Dauer: rund 2 bis 5 min (10 Archive mit Wasser und Wind, je Stand nur die Zellen).
rem Netz: keins. Die Oracle-Datenbank muss laufen.
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
set "UE=%ST%\Status_DB4_.txt"
set "L1=%ST%\Status_DB4_1.txt"
set "L3=%ST%\Status_DB4_3.txt"
set "L4=%ST%\Status_DB4_4.txt"
set "L6=%ST%\Status_DB4_6.txt"
set "L7=%ST%\Status_DB4_7.txt"
set "L9=%ST%\Status_DB4_9.txt"
set "L10=%ST%\Status_DB4_10.txt"
set "L12=%ST%\Status_DB4_12.txt"
set "L13=%ST%\Status_DB4_13.txt"
set "L14=%ST%\Status_DB4_14.txt"
set "E=0"
set "E4=-" & set "E6=-" & set "E7=-" & set "E10=-" & set "E12=-" & set "E14=-"
>"%UE%" echo Lauf DB4 (Antrieb gegen Messung), gestartet %DATE% %TIME%
>"%L1%" echo Status_DB4_1: Steuerhaus und HalligHooge bauen
>"%L3%" echo Status_DB4_3: MessungCheck (ohne Datenbank)
>"%L4%" echo Status_DB4_4: Schema auf Stufe 4
>"%L6%" echo Status_DB4_6: Ausgabe --guete (Archive mit dem Wind lesen)
>"%L7%" echo Status_DB4_7: Sammler --guete (Messarchiv, Kennzahlen, Hooge.guete), noch einmal
>"%L9%" echo Status_DB4_9: Abbild 2.6.0
>"%L10%" echo Status_DB4_10: GueteCheck (Bilder)
>"%L12%" echo Status_DB4_12: SteuerhausCheck (Bilder)
>"%L13%" echo Status_DB4_13: Bericht
>"%L14%" echo Status_DB4_14: Aufgabe mit den neuen Jars

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
set "N=3 MessungCheck (mit 12-16: Datei, Kennzahlen, Raster, Schluessel, Wind)"
set "C=java %U% -cp dist\HalligHooge.jar com.dan.steuerhaus.demo.MessungCheck --manifest src\szenen\Hooge.steuerhaus --gebiet daten\gebiet --quellen ..\Steuerhaus\src"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 4-5 Schema, Bestand
set "L=%L4%"
set "N=4 Schema auf Stufe 4 (HH_MODELL_WIND, HH_GUETE_WIND, Mittelwasser in HH_GUETE; drei Sichten)"
set "C=%SAM% --einrichten"
call :lauf
set "E4=%E%"
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 6 Archive lesen
set "L=%L6%"
set "N=6 Ausgabe --guete (10 Archive, 7 Pegel, Wind an List und Helgoland, daten\guete\Hooge.modell)"
set "C=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus --guete"
call :lauf
set "E6=%E%"
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 7-8 Sammler --guete
set "L=%L7%"
set "N=7 Sammler --guete (Laeufe ersetzt, Kennzahlen mit Wind und Mittelwasser, src\szenen\Hooge.guete)"
set "C=%SAM% --guete"
call :lauf
set "E7=%E%"
if not "%E%"=="0" goto :abbruch
set "N=8 Sammler --guete noch einmal (erwartet: Laeufe und Datei unveraendert)"
set "C=%SAM% --guete"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 9 Abbild
set "L=%L9%"
set "N=9 Abbild 2.6.0 (dist\abbild\HalligHooge, mit Hooge.guete in app\szenen)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 2.6.0"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 10-12 Pruefungen mit Bildern
set "L=%L10%"
set "N=10 GueteCheck (mit 8 Wind und 9 Mittelwasser; Bilder DB4_Guete_*.png)"
set "C=%J% com.dan.steuerhaus.demo.GueteCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E10=%E%"
set "E=0"
set "L=%L12%"
set "N=12 SteuerhausCheck (Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E12=%E%"
set "E=0"

rem ---------------------------------------------------------------- 13 Bericht
set "L=%L13%"
set "N=13 Bericht (mit Wind und Mittelwasser je Lauf)"
set "C=%SAM% --bericht"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 14 Aufgabe
set "L=%L14%"
set "N=14 Aufgabe HalligHooge Messarchiv mit den neuen Jars"
set "C=call "%~dp0sammler_aufgabe.cmd""
call :lauf
set "E14=%E%"
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo Exit: Einrichten %E4%, Ausgabe %E6%, Sammler %E7%, GueteCheck %E10%, SteuerhausCheck %E12%, Aufgabe %E14%
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: HalligHooge.cmd, Menue Labor ^> Modell gegen Messung (Strg Umschalt M): oben links "Wind", Lauf
echo "Sturmflut, 25.10.2026", List und Helgoland; zurueck auf "Wasserstand" mit den Linien des Mittelwassers; Bilder DB4_Guete_*.png.
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
