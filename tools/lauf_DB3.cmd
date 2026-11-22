@echo off
rem DB3 Modell gegen Messung (Werkbuch HalligHooge 171, F268-F271 A): Steuerhaus (Kern: Guete; ausgabe: Modellauszug,
rem Ausgabe --guete; messung: Guetebau, Sammler --guete, HThw bei der Uebernahme, Schema Stufe 3; neues Paket guete:
rem Gueteansicht, Guetefenster; Szenenapp: Menue Labor > Modell gegen Messung (Strg Umschalt M), Kachel auf der Startseite;
rem demo.GueteCheck, MessungCheck 12-15) und HalligHooge (guete.* im Manifest, Fassung 2.5; HH_LAUF, HH_MODELL,
rem HH_MODELL_SCHEITEL, HH_GUETE, HH_STATION.HTHW; Sichten HH_VERGLEICH_V, HH_SCHEITEL_PAAR_V, HH_GUETE_V) bauen;
rem MessungCheck; Schema auf Stufe 3; Bestand neu uebernehmen (HThw der Pegel); die Archive der Szenarien lesen
rem (daten\guete\Hooge.modell); Sammler --guete (Laeufe ins Messarchiv, Kennzahlen, src\szenen\Hooge.guete); noch einmal
rem (erwartet: unveraendert); Abbild 2.5.0; GueteCheck mit Bildern; ChronikCheck; SteuerhausCheck; Bericht; die Aufgabe
rem mit den neuen Jars erneuern.
rem Erwartet: MessungCheck 16, Einrichten "alles in Ordnung" (Stufe 3), GueteCheck 7 ohne Verstoss, ChronikCheck 6, SteuerhausCheck wie DB2.
rem Ausgaben: HalligHooge\docs\status\Status_DB3_*.txt, DB3_Guete_Labor.png, DB3_Guete_Nautik.png, DB3_Guete_Xaver.png.
rem Erwartete Dauer: rund 5 bis 10 min (10 Archive, je Stand nur die Zellen der 7 Pegel; rund 30 000 Werte in die Datenbank).
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
set "UE=%ST%\Status_DB3_.txt"
set "L1=%ST%\Status_DB3_1.txt"
set "L3=%ST%\Status_DB3_3.txt"
set "L4=%ST%\Status_DB3_4.txt"
set "L6=%ST%\Status_DB3_6.txt"
set "L7=%ST%\Status_DB3_7.txt"
set "L9=%ST%\Status_DB3_9.txt"
set "L10=%ST%\Status_DB3_10.txt"
set "L11=%ST%\Status_DB3_11.txt"
set "L12=%ST%\Status_DB3_12.txt"
set "L13=%ST%\Status_DB3_13.txt"
set "L14=%ST%\Status_DB3_14.txt"
set "E=0"
set "E4=-" & set "E6=-" & set "E7=-" & set "E10=-" & set "E11=-" & set "E12=-" & set "E14=-"
>"%UE%" echo Lauf DB3 (Modell gegen Messung), gestartet %DATE% %TIME%
>"%L1%" echo Status_DB3_1: Steuerhaus und HalligHooge bauen
>"%L3%" echo Status_DB3_3: MessungCheck (ohne Datenbank)
>"%L4%" echo Status_DB3_4: Schema auf Stufe 3, Bestand mit HThw
>"%L6%" echo Status_DB3_6: Ausgabe --guete (Archive der Szenarien lesen)
>"%L7%" echo Status_DB3_7: Sammler --guete (Messarchiv, Kennzahlen, Hooge.guete), noch einmal
>"%L9%" echo Status_DB3_9: Abbild 2.5.0
>"%L10%" echo Status_DB3_10: GueteCheck (Bilder)
>"%L11%" echo Status_DB3_11: ChronikCheck (Bilder)
>"%L12%" echo Status_DB3_12: SteuerhausCheck (Bilder)
>"%L13%" echo Status_DB3_13: Bericht
>"%L14%" echo Status_DB3_14: Aufgabe mit den neuen Jars

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
set "N=3 MessungCheck (mit 12-15: Datei, Kennzahlen, Raster, Schluessel guete.*)"
set "C=java %U% -cp dist\HalligHooge.jar com.dan.steuerhaus.demo.MessungCheck --manifest src\szenen\Hooge.steuerhaus --gebiet daten\gebiet --quellen ..\Steuerhaus\src"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 4-5 Schema, Bestand
set "L=%L4%"
set "N=4 Schema auf Stufe 3 (HH_LAUF, HH_MODELL, HH_MODELL_SCHEITEL, HH_GUETE, HTHW; drei Sichten)"
set "C=%SAM% --einrichten"
call :lauf
set "E4=%E%"
if not "%E%"=="0" goto :abbruch
set "N=5 Bestand neu uebernehmen (HThw und sein Tag je Pegel)"
set "C=%SAM% --uebernehmen --gebiet daten\gebiet"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 6 Archive lesen
set "L=%L6%"
set "N=6 Ausgabe --guete (10 Archive, 7 Pegel, daten\guete\Hooge.modell)"
set "C=%J% com.dan.steuerhaus.ausgabe.Ausgabe --manifest src\szenen\Hooge.steuerhaus --guete"
call :lauf
set "E6=%E%"
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 7-8 Sammler --guete
set "L=%L7%"
set "N=7 Sammler --guete (Laeufe ins Messarchiv, Kennzahlen, src\szenen\Hooge.guete)"
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
set "N=9 Abbild 2.5.0 (dist\abbild\HalligHooge, mit Hooge.guete in app\szenen)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 2.5.0"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 10-12 Pruefungen mit Bildern
set "L=%L10%"
set "N=10 GueteCheck (Datei, Laeufe, Messung, Xaver, Ansicht in beiden Themen, Menue, Kopie im Abbild)"
set "C=%J% com.dan.steuerhaus.demo.GueteCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E10=%E%"
set "E=0"
set "L=%L11%"
set "N=11 ChronikCheck (unveraendert seit DB2)"
set "C=%J% com.dan.steuerhaus.demo.ChronikCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E11=%E%"
set "E=0"
set "L=%L12%"
set "N=12 SteuerhausCheck (Bilder)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E12=%E%"
set "E=0"

rem ---------------------------------------------------------------- 13 Bericht
set "L=%L13%"
set "N=13 Bericht (mit Modell gegen Messung je Lauf und Pegel)"
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
>>"%UE%" echo Exit: Einrichten %E4%, Ausgabe %E6%, Sammler %E7%, GueteCheck %E10%, ChronikCheck %E11%, SteuerhausCheck %E12%, Aufgabe %E14%
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: HalligHooge.cmd, Menue Labor ^> Modell gegen Messung (Strg Umschalt M): Lauf "Sturmflut, 25.10.2026",
echo die Pegel durchklicken, dann Lauf "Sturmflut Xaver" (HThw); Knopf "Ansehen"; dazu die Bilder DB3_Guete_*.png in docs\status.
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
