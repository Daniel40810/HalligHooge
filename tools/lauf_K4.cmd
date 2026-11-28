@echo off
rem K4 (Werkbuch HalligHooge 183): Pferdebusse in der Ausstellung - Rundgang "Mit dem Pferdebus", Postkarte vom Bock,
rem Hufschlag. Schritte: 1 bauen (mit Abbild); 2 Strecken mit Belag (--kutschen); 3 Wege der Rundgaenge (--wege, auch
rem pferdebus.weg); 4 SoundscapeCheck (Hufe und Raeder); 5 GespanneCheck (mit Bildern und Vorschau); 6 PferdebusCheck
rem (Rundgang, Weiter ohne Sprung, Postkarte A6); 7 SteuerhausCheck; 8 App: Rundgang "Mit dem Pferdebus" 60 s.
rem Ausgaben: HalligHooge\docs\status\Status_K4_*.txt, K3_Kutschen.md, K3_*.png, K4_Postkarte_vom_Bock.png;
rem src\szenen\Hooge.kutschen, src\szenen\rundgang\*.weg
rem Erwartete Dauer: rund 25 min. Das Fenster der App oeffnet sich einmal von selbst (rund 1 min). Netz: keins.
rem Anhalten zwischen zwei Schritten: eine Datei STOPP.txt neben dieses Skript legen.
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
set "R=java %U% --enable-native-access=ALL-UNNAMED -Xmx12g -cp dist\Renderer.jar"

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_K4_.txt"
set "E=0"
>"%UE%" echo Lauf K4 (Pferdebusse in der Ausstellung), gestartet %DATE% %TIME%
for %%N in (1 2 3 4 5 6 7 8) do >"%ST%\Status_K4_%%N.txt" echo Status_K4_%%N

rem ---------------------------------------------------------------- 1 Bauen
set "L=%ST%\Status_K4_1.txt"
set "N=1 Bauen (Renderer, Steuerhaus, HalligHooge, Abbild)"
set "C=call "%HH%\tools\bauen.cmd" "%P%""
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 2 Strecken
set "L=%ST%\Status_K4_2.txt"
set "N=2 Strecken der Pferdebusse mit Belag (--kutschen)"
set "C=%J% com.dan.hallighooge.HalligHooge --kutschen"
call :lauf
if not "%E%"=="0" goto :abbruch
findstr /c:"Belag" /c:"halt" /c:"laenge" "%HH%\src\szenen\Hooge.kutschen" >>"%L%" 2>nul

rem ---------------------------------------------------------------- 3 Wege der Rundgaenge
set "L=%ST%\Status_K4_3.txt"
set "N=3 Wege der Rundgaenge (--wege)"
set "C=%J% com.dan.hallighooge.HalligHooge --wege"
call :lauf
set "E=0"
>>"%L%" echo.
>>"%L%" echo ---- pferdebus.weg
type "%HH%\src\szenen\rundgang\pferdebus.weg" >>"%L%" 2>nul

rem ---------------------------------------------------------------- 4 SoundscapeCheck
set "L=%ST%\Status_K4_4.txt"
set "N=4 SoundscapeCheck (Hufe und Raeder)"
pushd "%RE%"
set "C=%R% com.dan.soundscape.demo.SoundscapeCheck"
call :lauf
popd
set "E4=%E%"
set "E=0"

rem ---------------------------------------------------------------- 5 GespanneCheck
set "L=%ST%\Status_K4_5.txt"
set "N=5 GespanneCheck (mit Bildern und Vorschau)"
pushd "%RE%"
set "C=%R% com.dan.lauf.demo.GespanneCheck --szenen "%HH%\src\szenen\Hooge.szenen" --vorschau "%HH%\src\szenen\vorschau""
call :lauf
popd
set "E5=%E%"
set "E=0"
if exist "%RE%\docs\status\K3_Kutschen.md" copy /y "%RE%\docs\status\K3_Kutschen.md" "%ST%\K3_Kutschen.md" >nul
for %%F in ("%RE%\docs\status\K3_*.png") do copy /y "%%F" "%ST%\" >nul

rem ---------------------------------------------------------------- 6 PferdebusCheck
set "L=%ST%\Status_K4_6.txt"
set "N=6 PferdebusCheck (Rundgang, Weiter ohne Sprung, Postkarte A6)"
set "C=%J% com.dan.steuerhaus.demo.PferdebusCheck --manifest src\szenen\Hooge.steuerhaus --bilder docs\status"
call :lauf
set "E6=%E%"
set "E=0"

rem ---------------------------------------------------------------- 7 SteuerhausCheck
set "L=%ST%\Status_K4_7.txt"
set "N=7 SteuerhausCheck (Manifest, Katalog, Rundgaenge, Pakete)"
set "C=%J% com.dan.steuerhaus.demo.SteuerhausCheck --manifest src\szenen\Hooge.steuerhaus --quellen ..\Steuerhaus\src --bilder docs\status"
call :lauf
set "E7=%E%"
set "E=0"

rem ---------------------------------------------------------------- 8 App
set "L=%ST%\Status_K4_8.txt"
set "N=8 App: Rundgang Mit dem Pferdebus, 60 s, alle 12 s weiter"
if exist "%ST%\protokoll.txt" del /q "%ST%\protokoll.txt"
set "C=%J% com.dan.hallighooge.HalligHooge --rundgang pferdebus --sekunden 60 --einstellungen docs\status\X3_einstellungen.properties"
call :lauf
set "E=0"
if exist "%ST%\protokoll.txt" (
  >>"%L%" echo Protokoll:
  type "%ST%\protokoll.txt" >>"%L%" 2>nul
)

>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME% (Soundscape %E4%, Gespanne %E5%, Pferdebus %E6%, Steuerhaus %E7%)
echo.
echo Fertig. Uebersicht: %UE%
echo Sichtpruefung: HalligHooge.cmd - Startseite, Gruppe Rundgaenge, "Mit dem Pferdebus" (Ton an); Datei, Postkarte vom Bock.
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
