@echo off
rem DB1 Messarchiv (Werkbuch HalligHooge 167, F261-F265 A): Steuerhaus (neues Paket messung: Sammler, Messarchiv,
rem Uebernahme, Scheitelsuche, Ausreisser, Aufbewahrung, Abruf; demo.MessungCheck) und HalligHooge (db\sql, messung.* im
rem Manifest) bauen; MessungCheck ohne Datenbank; Probe der Quellen PEGELONLINE und DWD; Verbindung zum Schema
rem HALLIGHOOGE (fragt einmal nach dem Passwort, wenn db.properties keins hat); Schema einrichten; den Bestand aus
rem daten\gebiet uebernehmen (zweimal: der zweite Lauf fuegt nichts ein); erster Abruf (PEGELONLINE seit dem 11.11.,
rem Wind des DWD); Pruefsteine DB1; Bericht; die stuendliche Aufgabe "HalligHooge Messarchiv" anlegen, einmal starten,
rem nach 2 min der Bericht mit ihrem Lauf.
rem Vorher einmal (nur wenn es das Schema HALLIGHOOGE noch nicht gibt): db\USER.sql als Admin in SQL Developer ausfuehren
rem (Vorlage db\USER.sql.example), dazu  GRANT CREATE TABLE, CREATE SEQUENCE TO HALLIGHOOGE;  (fuer die raeumlichen Indizes).
rem Der Renderer bleibt unveraendert (HalligHooge\lib\Renderer.jar traegt com.dan.store schon).
rem Erwartet: MessungCheck 8, Einrichten "alles in Ordnung", Pruefsteine DB1 10 ohne Verstoss, die Aufgabe im Bericht.
rem Ausgaben: HalligHooge\docs\status\Status_DB1_*.txt; Protokoll des Sammlers in %USERPROFILE%\.steuerhaus\HalligHooge\sammler.log.
rem Erwartete Dauer: rund 10 bis 15 min. Netz: PEGELONLINE und opendata.dwd.de. Die Oracle-Datenbank muss laufen.
rem Anhalten zwischen zwei Schritten: eine Datei STOPP.txt neben dieses Skript legen.
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

for %%a in ("%~dp0..\..") do set "P=%%~fa"
set "SH=%P%\Steuerhaus"
set "HH=%P%\HalligHooge"
set "ST=%HH%\docs\status"
set "U=-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"
set "SAM=java %U% -cp dist\HalligHooge.jar com.dan.steuerhaus.messung.Sammler --manifest src\szenen\Hooge.steuerhaus"
set "ANT=ant"
where ant >nul 2>nul || set "ANT=C:\Program Files\Apache NetBeans\extide\ant\bin\ant.bat"

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_DB1_.txt"
set "L1=%ST%\Status_DB1_1.txt"
set "L3=%ST%\Status_DB1_3.txt"
set "L4=%ST%\Status_DB1_4.txt"
set "L5=%ST%\Status_DB1_5.txt"
set "L6=%ST%\Status_DB1_6.txt"
set "L7=%ST%\Status_DB1_7.txt"
set "L9=%ST%\Status_DB1_9.txt"
set "L10=%ST%\Status_DB1_10.txt"
set "L11=%ST%\Status_DB1_11.txt"
set "L12=%ST%\Status_DB1_12.txt"
set "E=0"
>"%UE%" echo Lauf DB1 (Messarchiv), gestartet %DATE% %TIME%
>"%L1%" echo Status_DB1_1: Steuerhaus und HalligHooge bauen
>"%L3%" echo Status_DB1_3: MessungCheck (ohne Datenbank)
>"%L4%" echo Status_DB1_4: Probe der Quellen (PEGELONLINE, DWD)
>"%L5%" echo Status_DB1_5: Verbindung
>"%L6%" echo Status_DB1_6: Schema einrichten
>"%L7%" echo Status_DB1_7: Bestand uebernehmen (zweimal)
>"%L9%" echo Status_DB1_9: erster Abruf
>"%L10%" echo Status_DB1_10: Pruefsteine DB1
>"%L11%" echo Status_DB1_11: Bericht
>"%L12%" echo Status_DB1_12: Aufgabe anlegen, einmal starten, Bericht

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
set "N=3 MessungCheck (Skripte, Scheitel, Ausreisser, Aufbewahrung, Lesen, Schluessel, Importregel)"
set "C=java %U% -cp dist\HalligHooge.jar com.dan.steuerhaus.demo.MessungCheck --manifest src\szenen\Hooge.steuerhaus --gebiet daten\gebiet --quellen ..\Steuerhaus\src"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 4 Probe
set "L=%L4%"
set "N=4 Probe: PEGELONLINE (Pellworm Anleger, 2 h) und DWD (Helgoland), ohne Datenbank"
set "C=%SAM% --probe"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 5 Verbindung (in der Konsole: fragt einmal nach dem Passwort)
set "L=%L5%"
echo.
echo [%DATE% %TIME%] Start  5 Verbindung zum Schema HALLIGHOOGE (fragt hier nach dem Passwort, wenn db\db.properties keins hat)
>>"%UE%" echo [%DATE% %TIME%] Start  5 Verbindung
%SAM% --verbinden
set "E=%ERRORLEVEL%"
>>"%UE%" echo [%DATE% %TIME%] Ende   5 Verbindung - Exit %E%
if not "%E%"=="0" (
  echo.
  echo Keine Verbindung. Gibt es das Schema HALLIGHOOGE? Sonst db\USER.sql als Admin ausfuehren ^(Vorlage USER.sql.example^),
  echo dazu GRANT CREATE TABLE, CREATE SEQUENCE TO HALLIGHOOGE; und den Lauf neu starten.
  >>"%UE%" echo Keine Verbindung - Schema HALLIGHOOGE anlegen ^(db\USER.sql^) oder Passwort pruefen.
  set "N=5 Verbindung"
  goto :abbruch
)
set "N=5 Verbindung (zum Protokoll)"
set "C=%SAM% --verbinden"
call :lauf

rem ---------------------------------------------------------------- 6 Einrichten
set "L=%L6%"
set "N=6 Schema einrichten (db\sql 01-04, com.dan.store.Einrichter)"
set "C=%SAM% --einrichten"
call :lauf
set "E6=%E%"
set "E=0"

rem ---------------------------------------------------------------- 7-8 Bestand
set "L=%L7%"
set "N=7 Bestand uebernehmen (22 Pegel, 2 Windstationen seit 2010, Orte, Ort Hooge; dann Mittel, Scheitel, Schaetzung)"
set "C=%SAM% --uebernehmen --gebiet daten\gebiet"
call :lauf
if not "%E%"=="0" goto :abbruch
set "N=8 Bestand noch einmal (erwartet: 0 Minutenwerte, 0 Mittel)"
set "C=%SAM% --uebernehmen --gebiet daten\gebiet"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 9 Abruf
set "L=%L9%"
set "N=9 erster Abruf (PEGELONLINE seit dem Bestand, Wind des DWD, Pflege)"
set "C=%SAM% --abruf"
call :lauf
set "E9=%E%"
set "E=0"

rem ---------------------------------------------------------------- 10-11 Pruefen, Bericht
set "L=%L10%"
set "N=10 Pruefsteine DB1"
set "C=%SAM% --pruefen --gebiet daten\gebiet"
call :lauf
set "E10=%E%"
set "E=0"
set "L=%L11%"
set "N=11 Bericht"
set "C=%SAM% --bericht"
call :lauf
set "E=0"

rem ---------------------------------------------------------------- 12 Aufgabe
set "L=%L12%"
set "N=12a Aufgabe HalligHooge Messarchiv anlegen und einmal starten"
set "C=call "%~dp0sammler_aufgabe.cmd""
call :lauf
set "E12=%E%"
echo [%DATE% %TIME%] warte 120 s auf den ersten Lauf der Aufgabe ...
timeout /t 120 >nul
set "N=12b Bericht nach dem Lauf der Aufgabe"
set "C=%SAM% --bericht"
call :lauf
set "E=0"

:ende
>>"%UE%" echo.
>>"%UE%" echo Exit: Einrichten %E6%, Abruf %E9%, Pruefsteine %E10%, Aufgabe %E12%
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: in SQL Developer als HALLIGHOOGE  SELECT * FROM HH_SCHAETZUNG_V ORDER BY ZEIT DESC;  und die Aufgabe in der Aufgabenplanung.
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
