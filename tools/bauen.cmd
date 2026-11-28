@echo off
rem HalligHooge - die drei Projekte in ihrer Reihenfolge bauen (Werkbuch HalligHooge 164, G1):
rem   Renderer (clean jar)  -> dist\Renderer.jar nach Steuerhaus\lib und HalligHooge\lib
rem   Steuerhaus (clean jar) -> dist\Steuerhaus.jar nach HalligHooge\lib
rem   HalligHooge (clean jar) -> dist\HalligHooge.jar
rem Aufruf:  tools\bauen.cmd [Ordner mit Renderer, Steuerhaus und HalligHooge]   (Vorgabe: der Ordner ueber HalligHooge)
rem Die Bibliotheken in lib\ muessen da sein (README, Abschnitt Bibliotheken). Ohne die NetBeans-Plattform JDK_21
rem (frischer Clone, nie in NetBeans geoeffnet) vorher den JDK setzen, etwa:  set "JDK21=C:\Program Files\Java\jdk-21"
rem Ergebnis: Exit 0, dist\HalligHooge.jar und (seit Seegang Werkbuch 116) das Abbild dist\abbild\HalligHooge\HalligHooge.exe
rem mit Verknuepfung auf dem Desktop (tools\abbild.cmd); sonst Exit 1 mit dem Schritt, der fehlschlug.
setlocal EnableExtensions
set "P=%~1"
if "%P%"=="" set "P=%~dp0..\.."
for %%a in ("%P%") do set "P=%%~fa"
set "ANT=ant"
where ant >nul 2>nul || set "ANT=C:\Program Files\Apache NetBeans\extide\ant\bin\ant.bat"
set "PLATT="
if defined JDK21 set "PLATT=-Dplatforms.JDK_21.home=%JDK21%"

for %%d in (Renderer Steuerhaus HalligHooge) do if not exist "%P%\%%d\build.xml" (
  echo %P%\%%d\build.xml fehlt - die drei Projekte gehoeren nebeneinander in einen Ordner.
  exit /b 1
)
if not exist "%P%\Steuerhaus\lib" mkdir "%P%\Steuerhaus\lib"
if not exist "%P%\HalligHooge\lib" mkdir "%P%\HalligHooge\lib"

echo [%TIME%] Renderer bauen ...
pushd "%P%\Renderer"
call "%ANT%" -q %PLATT% -f build.xml clean jar
set "E=%ERRORLEVEL%"
popd
if not "%E%"=="0" (echo Renderer: Bau fehlgeschlagen ^(Exit %E%^). & exit /b 1)
copy /y "%P%\Renderer\dist\Renderer.jar" "%P%\Steuerhaus\lib\Renderer.jar" >nul || (echo Renderer.jar nach Steuerhaus\lib: Kopie fehlgeschlagen. & exit /b 1)
copy /y "%P%\Renderer\dist\Renderer.jar" "%P%\HalligHooge\lib\Renderer.jar" >nul || (echo Renderer.jar nach HalligHooge\lib: Kopie fehlgeschlagen. & exit /b 1)

echo [%TIME%] Steuerhaus bauen ...
pushd "%P%\Steuerhaus"
call "%ANT%" -q %PLATT% -f build.xml clean jar
set "E=%ERRORLEVEL%"
popd
if not "%E%"=="0" (echo Steuerhaus: Bau fehlgeschlagen ^(Exit %E%^). & exit /b 1)
copy /y "%P%\Steuerhaus\dist\Steuerhaus.jar" "%P%\HalligHooge\lib\Steuerhaus.jar" >nul || (echo Steuerhaus.jar nach HalligHooge\lib: Kopie fehlgeschlagen. & exit /b 1)

echo [%TIME%] HalligHooge bauen ...
pushd "%P%\HalligHooge"
call "%ANT%" -q %PLATT% -f build.xml clean jar
set "E=%ERRORLEVEL%"
popd
if not "%E%"=="0" (echo HalligHooge: Bau fehlgeschlagen ^(Exit %E%^). & exit /b 1)
if not exist "%P%\HalligHooge\dist\HalligHooge.jar" (echo dist\HalligHooge.jar fehlt nach dem Bau. & exit /b 1)

rem seit Seegang Werkbuch 116 (SF196 A): clean loescht dist\abbild - das Abbild und die Verknuepfung auf dem Desktop
rem gleich neu (tools\abbild.cmd, Version wie dort VER_VORGABE)
echo [%TIME%] Abbild und Verknuepfung ...
if defined JDK21 if not defined JDK set "JDK=%JDK21%"
call "%P%\HalligHooge\tools\abbild.cmd" "" still
set "E=%ERRORLEVEL%"
if not "%E%"=="0" (echo Abbild: fehlgeschlagen ^(Exit %E%^), siehe HalligHooge\docs\status\Status_Abbild.txt. & exit /b 1)
echo [%TIME%] Fertig: %P%\HalligHooge\dist\HalligHooge.jar und dist\abbild\HalligHooge\HalligHooge.exe
exit /b 0
