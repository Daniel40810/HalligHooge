@echo off
rem DB5 Gezeiten wachsen mit (Werkbuch HalligHooge 176, F276-F282 A): Renderer (core.astro.Partialtide mit L2, M3 und den
rem Flachwassertiden 2SM2, MK3, MO3, S4, 2MS6, 2MN6, MSN6, M8, 3MS8), Steuerhaus (gezeiten.Gezeitenanalyse, messung.Gezeitenbau,
rem Sammler --gezeiten und monatlich im Abruf, Herkunft im Tidenkalender, DB4b in Guetebau; MessungCheck 17-20, GezeitenCheck 11)
rem und HalligHooge (Schema Stufe 5, gezeiten.wachsen, gezeiten.kopie, Fassung 2.7) bauen; MessungCheck; Schema auf Stufe 5;
rem Sammler --gezeiten (je Pegel ein Kandidat aus den Tagen vor der Pruefzeit, geprueft an den Tagen seit dem 11.11.; der Kalender
rem mit und ohne Faktor gegen die Tafel; Mittelwasser je Monat); noch einmal (erwartet: uebersprungen oder dieselbe Entscheidung);
rem Sammler --guete (Mittelwasser ohne Windstau); Abbild 2.7.0; GezeitenCheck und GueteCheck mit Bildern; SteuerhausCheck;
rem Bericht; die Aufgabe mit den neuen Jars erneuern.
rem Erwartet: MessungCheck 21, Einrichten "alles in Ordnung" (Stufe 5), GezeitenCheck und GueteCheck ohne Verstoss.
rem Ausgaben: HalligHooge\docs\status\Status_DB5_*.txt, DB5_Kalender_Herkunft.png, Z1_Kalender_Hooge.png, DB4_Guete_*.png.
rem Veraendert vielleicht: src\szenen\Hooge.gezeiten (nur, wenn der Kandidat besser trifft) - dann bitte wie gewohnt pushen.
rem Erwartete Dauer: rund 4 bis 6 min (der Renderer wird mitgebaut).
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
set "RE=%P%\Renderer"
set "ST=%HH%\docs\status"
set "U=-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"
set "J=java %U% --enable-native-access=ALL-UNNAMED -Xmx12g -cp dist\HalligHooge.jar"
set "SAM=java %U% -cp dist\HalligHooge.jar com.dan.steuerhaus.messung.Sammler --manifest src\szenen\Hooge.steuerhaus"
set "ANT=ant"
where ant >nul 2>nul || set "ANT=C:\Program Files\Apache NetBeans\extide\ant\bin\ant.bat"

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_DB5_.txt"
set "L1=%ST%\Status_DB5_1.txt"
set "L3=%ST%\Status_DB5_3.txt"
set "L4=%ST%\Status_DB5_4.txt"
set "L7=%ST%\Status_DB5_7.txt"
set "L9=%ST%\Status_DB5_9.txt"
set "L10=%ST%\Status_DB5_10.txt"
set "L5=%ST%\Status_DB5_5.txt"
set "L12=%ST%\Status_DB5_12.txt"
set "L13=%ST%\Status_DB5_13.txt"
set "L14=%ST%\Status_DB5_14.txt"
set "E=0"
set "E4=-" & set "E5=-" & set "E7=-" & set "E10=-" & set "E11=-" & set "E12=-" & set "E14=-"
>"%UE%" echo Lauf DB5 (Gezeiten wachsen mit), gestartet %DATE% %TIME%
>"%L1%" echo Status_DB5_1: Renderer, Steuerhaus und HalligHooge bauen
>"%L3%" echo Status_DB5_3: MessungCheck (ohne Datenbank)
>"%L4%" echo Status_DB5_4: Schema auf Stufe 5
>"%L5%" echo Status_DB5_5: Sammler --gezeiten, noch einmal
>"%L7%" echo Status_DB5_7: Sammler --guete (Mittelwasser ohne Windstau)
>"%L9%" echo Status_DB5_9: Abbild 2.7.0
>"%L10%" echo Status_DB5_10: GezeitenCheck und GueteCheck (Bilder)
>"%L12%" echo Status_DB5_12: SteuerhausCheck (Bilder)
>"%L13%" echo Status_DB5_13: Bericht
>"%L14%" echo Status_DB5_14: Aufgabe mit den neuen Jars

rem ---------------------------------------------------------------- 0-2 Bauen
set "L=%L1%"
pushd "%RE%"
set "N=0 Renderer bauen (clean jar; neue Partialtiden)"
set "C=call "%ANT%" -f build.xml clean jar"
call :lauf
popd
if not "%E%"=="0" goto :abbruch
copy /y "%RE%\dist\Renderer.jar" "%SH%\lib\Renderer.jar" >>"%L1%" 2>&1
copy /y "%RE%\dist\Renderer.jar" "%HH%\lib\Renderer.jar" >>"%L1%" 2>&1
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
set "N=3 MessungCheck (mit 17-20: neue Tiden, Pruefzeit und Annahme, Mittelwasser, Umzug der Analyse)"
set "C=java %U% -cp dist\HalligHooge.jar com.dan.steuerhaus.demo.MessungCheck --manifest src\szenen\Hooge.steuerhaus --gebiet daten\gebiet --quellen ..\Steuerhaus\src"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 4-5 Schema, Bestand
set "L=%L4%"
set "N=4 Schema auf Stufe 5 (HH_ANALYSE, HH_ANALYSE_TIDE, HH_MITTELWASSER, Spalten in HH_SCHEITEL und HH_GUETE; drei Sichten)"
set "C=%SAM% --einrichten"
call :lauf
set "E4=%E%"
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 5-6 Gezeiten
set "L=%L5%"
set "N=5 Sammler --gezeiten (Kandidaten je Pegel, Pruefung seit dem 11.11., Kalender mit und ohne Faktor, Mittelwasser je Monat)"
set "C=%SAM% --gezeiten"
call :lauf
set "E5=%E%"
if not "%E%"=="0" goto :abbruch
set "N=6 Sammler --gezeiten noch einmal (erwartet: uebersprungen - keine neuen Tage - oder dieselbe Entscheidung)"
set "C=%SAM% --gezeiten"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 7 Sammler --guete
set "L=%L7%"
set "N=7 Sammler --guete (DB4b: Mittelwasser ohne Windstau je Lauf und Pegel; Hooge.guete unveraendert)"
set "C=%SAM% --guete"
call :lauf
set "E7=%E%"
set "E=0"

rem ---------------------------------------------------------------- 9 Abbild
set "L=%L9%"
set "N=9 Abbild 2.7.0 (dist\abbild\HalligHooge, mit Hooge.gezeiten in app\szenen)"
set "C=call "%SH%\tools\abbild.cmd" "%HH%" HalligHooge 2.7.0"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 10-12 Pruefungen mit Bildern
set "L=%L10%"
set "N=10 GezeitenCheck (6-11, mit der Herkunft; Bilder Z1_Kalender_Hooge.png, DB5_Kalender_Herkunft.png)"
set "C=%J% com.dan.steuerhaus.demo.GezeitenCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E11=%E%"
set "E=0"
set "N=11 GueteCheck (9 Pruefsteine; Bilder DB4_Guete_*.png)"
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
set "N=13 Bericht (mit den Analysen der Gezeit und dem Mittelwasser je Monat)"
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
>>"%UE%" echo Exit: Einrichten %E4%, Gezeiten %E5%, Guete %E7%, GezeitenCheck %E11%, GueteCheck %E10%, SteuerhausCheck %E12%, Aufgabe %E14%
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: HalligHooge.cmd, Menue Begleiter ^> Tidenkalender (Strg Umschalt T): unten die Zeile "Gezeit aus ... Tagen
echo Messung ..." (nur, wenn der Kandidat besser war), Knopf "Herkunft" (Taste H); Bild DB5_Kalender_Herkunft.png.
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
