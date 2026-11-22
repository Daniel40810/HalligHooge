@echo off
rem G1 GitHub (Werkbuch HalligHooge 164; F256 A drei Repos, F257 A oeffentlich, F258 B ohne lib, F259 B Renderer als
rem Zweig mit Pull Request, F260 A Daten und Abbild bleiben lokal).
rem   1 Vorbedingungen: git und gh da, gh angemeldet als Daniel40810, Steuerhaus und HalligHooge noch ohne Git und
rem     noch nicht auf GitHub, Renderer auf einem Zweig mit origin Daniel40810/Renderer, Zweig hallighooge noch frei
rem   2 vormerken (nur lokal): Renderer auf den neuen Zweig hallighooge, _p5 und nbproject\private aus dem Index,
rem     git add; Steuerhaus und HalligHooge: git init (master), Identitaet wie Git_Init.bat, git add
rem   3 pruefen und zeigen (tools\github\G1_pruefen.ps1), dann EINE Rueckfrage. Bei Verstoss oder "n" wird alles
rem     zurueckgenommen: Renderer wieder auf dem alten Zweig, die neuen .git-Ordner weg. Nichts ist hochgeladen.
rem   4 Renderer: Commit, Zweig hochladen, Pull Request nach master (mergen auf GitHub von Hand)
rem   5 Steuerhaus und 6 HalligHooge: erster Commit, Repo oeffentlich anlegen, hochladen, Beschreibung
rem   7 Probe: die drei Repos frisch von GitHub nach %TEMP%\g1_probe klonen, die Bibliotheken aus den lokalen
rem     lib-Ordnern dazu (ohne Renderer.jar und Steuerhaus.jar), mit tools\bauen.cmd des Clones bauen, aufraeumen
rem Erwartet: alles Exit 0; am Ende die Adressen der Repos und des Pull Requests.
rem Ausgaben: HalligHooge\docs\status\Status_G1_*.txt. Dauer: rund 10 bis 20 min (Hochladen rund 170 MB, Probe-Bau).
rem Vorher einmal: gh auth login. Die App schliessen; NetBeans darf offen bleiben.
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."
for %%a in ("%~dp0..\..") do set "P=%%~fa"

set "RE=%P%\Renderer"
set "SH=%P%\Steuerhaus"
set "HH=%P%\HalligHooge"
set "G=%~dp0github"
set "ST=%HH%\docs\status"
set "KONTO=Daniel40810"
set "NOREPLY=daniel40810@users.noreply.github.com"
set "ZWEIG=hallighooge"
set "GRENZE=52428800"
set "PROBE=%TEMP%\g1_probe"
set "VORHER="
set "NEU_S="
set "NEU_H="

if not exist "%ST%" mkdir "%ST%"
set "UE=%ST%\Status_G1_.txt"
set "L1=%ST%\Status_G1_1.txt"
set "L2=%ST%\Status_G1_2.txt"
set "L3=%ST%\Status_G1_3.txt"
set "L4=%ST%\Status_G1_4.txt"
set "L5=%ST%\Status_G1_5.txt"
set "L6=%ST%\Status_G1_6.txt"
set "L7=%ST%\Status_G1_7.txt"
set "E=0"
>"%UE%" echo Lauf G1 (GitHub), gestartet %DATE% %TIME%
>"%L1%" echo Status_G1_1: Vorbedingungen
>"%L2%" echo Status_G1_2: vormerken (nur lokal)
>"%L3%" echo Status_G1_3: pruefen und zeigen
>"%L4%" echo Status_G1_4: Renderer - Commit, Zweig %ZWEIG%, Pull Request
>"%L5%" echo Status_G1_5: Steuerhaus - erster Commit, Repo, hochladen
>"%L6%" echo Status_G1_6: HalligHooge - erster Commit, Repo, hochladen
>"%L7%" echo Status_G1_7: Probe - frisch klonen und bauen

for %%f in (G1_pruefen.ps1 commit_Renderer.txt commit_Steuerhaus.txt commit_HalligHooge.txt pr_Renderer.md repo_Steuerhaus.json repo_HalligHooge.json) do if not exist "%G%\%%f" (
  echo %G%\%%f fehlt.
  >>"%UE%" echo %G%\%%f fehlt.
  set "N=0 Dateien in tools\github"
  goto :abbruch
)

rem ---------------------------------------------------------------- 1 Vorbedingungen
set "L=%L1%"
set "N=1 Vorbedingungen (git, gh, Anmeldung, Repos, Zweig)"
set "C=call :vorbedingungen"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 2 vormerken
set "L=%L2%"
set "N=2 vormerken (Renderer: Zweig %ZWEIG%; Steuerhaus, HalligHooge: git init; alles git add)"
set "C=call :vormerken"
call :lauf
if not "%E%"=="0" goto :zurueck

rem ---------------------------------------------------------------- 3 pruefen und zeigen, Rueckfrage
set "L=%L3%"
set "N=3 pruefen und zeigen"
echo [%DATE% %TIME%] Start  %N%
>>"%UE%" echo [%DATE% %TIME%] Start  %N%
powershell -NoProfile -ExecutionPolicy Bypass -File "%G%\G1_pruefen.ps1" -Grenze %GRENZE% -Log "%L3%" "%RE%" "%SH%" "%HH%"
set "E=%ERRORLEVEL%"
echo [%DATE% %TIME%] Ende   %N%  - Exit %E%
>>"%UE%" echo [%DATE% %TIME%] Ende   %N%  - Exit %E%
if not "%E%"=="0" goto :zurueck
echo.
echo Renderer: Zweig %ZWEIG% mit Pull Request nach master. Steuerhaus und HalligHooge: neu und oeffentlich.
set "JA="
set /p "JA=Alles so hochladen? j = ja, sonst wird alles zurueckgenommen: "
>>"%UE%" echo Rueckfrage: Antwort "%JA%"
if /i not "%JA%"=="j" (
  set "N=3 auf Wunsch nicht hochgeladen"
  goto :zurueck
)

rem ---------------------------------------------------------------- 4 Renderer
set "L=%L4%"
set "N=4a Renderer: Commit auf %ZWEIG%"
set "C=git -C "%RE%" commit -q -F "%G%\commit_Renderer.txt""
call :lauf
if not "%E%"=="0" goto :zurueck
set "N=4b Renderer: Zweig %ZWEIG% hochladen"
set "C=git -C "%RE%" push -u origin %ZWEIG%"
call :lauf
if not "%E%"=="0" goto :abbruch
set "N=4c Renderer: Pull Request %ZWEIG% nach master"
set "C=gh pr create --repo %KONTO%/Renderer --base master --head %ZWEIG% --title "HalligHooge (Teil A bis D1)" --body-file "%G%\pr_Renderer.md""
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 5 Steuerhaus
set "L=%L5%"
set "N=5a Steuerhaus: erster Commit"
set "C=git -C "%SH%" commit -q -F "%G%\commit_Steuerhaus.txt""
call :lauf
if not "%E%"=="0" goto :abbruch
set "N=5b Steuerhaus: Repo %KONTO%/Steuerhaus oeffentlich anlegen und hochladen"
set "C=gh repo create %KONTO%/Steuerhaus --public --source "%SH%" --remote origin --push"
call :lauf
if not "%E%"=="0" goto :abbruch
set "N=5c Steuerhaus: Beschreibung"
set "C=gh api -X PATCH repos/%KONTO%/Steuerhaus --input "%G%\repo_Steuerhaus.json" --silent"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 6 HalligHooge
set "L=%L6%"
set "N=6a HalligHooge: erster Commit"
set "C=git -C "%HH%" commit -q -F "%G%\commit_HalligHooge.txt""
call :lauf
if not "%E%"=="0" goto :abbruch
set "N=6b HalligHooge: Repo %KONTO%/HalligHooge oeffentlich anlegen und hochladen"
set "C=gh repo create %KONTO%/HalligHooge --public --source "%HH%" --remote origin --push"
call :lauf
if not "%E%"=="0" goto :abbruch
set "N=6c HalligHooge: Beschreibung"
set "C=gh api -X PATCH repos/%KONTO%/HalligHooge --input "%G%\repo_HalligHooge.json" --silent"
call :lauf
if not "%E%"=="0" goto :abbruch

rem ---------------------------------------------------------------- 7 Probe
set "L=%L7%"
set "N=7a Probe: die drei Repos frisch klonen nach %PROBE%"
set "C=call :probe_klonen"
call :lauf
if not "%E%"=="0" goto :abbruch
set "N=7b Probe: Bibliotheken aus den lokalen lib-Ordnern dazu (ohne Renderer.jar, Steuerhaus.jar)"
set "C=call :probe_lib"
call :lauf
if not "%E%"=="0" goto :abbruch
set "N=7c Probe: Renderer, Steuerhaus, HalligHooge bauen (tools\bauen.cmd des Clones)"
set "C=call "%PROBE%\HalligHooge\tools\bauen.cmd" "%PROBE%""
call :lauf
if not "%E%"=="0" goto :abbruch
set "N=7d Probe aufraeumen"
set "C=rmdir /s /q "%PROBE%""
call :lauf
set "E=0"

:ende
set "PR="
for /f "delims=" %%u in ('gh pr view %ZWEIG% --repo %KONTO%/Renderer --json url --jq .url 2^>nul') do set "PR=%%u"
>>"%UE%" echo.
>>"%UE%" echo Renderer:     https://github.com/%KONTO%/Renderer  (Pull Request: %PR%)
>>"%UE%" echo Steuerhaus:   https://github.com/%KONTO%/Steuerhaus
>>"%UE%" echo HalligHooge:  https://github.com/%KONTO%/HalligHooge
>>"%UE%" echo.
>>"%UE%" echo FERTIG %DATE% %TIME%
echo.
echo Fertig. Uebersicht: %UE%
echo Pull Request des Renderers: %PR%
echo Steuerhaus:  https://github.com/%KONTO%/Steuerhaus
echo HalligHooge: https://github.com/%KONTO%/HalligHooge
echo Den Pull Request auf GitHub ansehen und mergen; danach im Renderer:  git switch master  und  git pull
pause
goto :eof

:zurueck
call :zuruecknehmen >>"%L%" 2>&1
>>"%UE%" echo.
>>"%UE%" echo ZURUECKGENOMMEN %DATE% %TIME% nach: %N% - nichts hochgeladen, Renderer wieder auf %VORHER%
echo.
echo Nichts hochgeladen, alles zurueckgenommen ^(Renderer wieder auf %VORHER%^). Grund: %N%  - siehe %L%
pause
exit /b 1

:abbruch
>>"%UE%" echo.
>>"%UE%" echo ABBRUCH %DATE% %TIME% nach: %N%
echo.
echo Abbruch nach: %N%  - siehe %L%
echo Was schon auf GitHub ist, bleibt dort. Bitte Status_G1_.txt melden, dann geht es von Hand weiter.
pause
exit /b 1

rem ---------------------------------------------------------------- Unterprogramme

:lauf
echo [%DATE% %TIME%] Start  %N%
>>"%UE%" echo [%DATE% %TIME%] Start  %N%
>>"%L%" echo.
>>"%L%" echo ^>%C%
%C% >>"%L%" 2>&1
set "E=%ERRORLEVEL%"
echo [%DATE% %TIME%] Ende   %N%  - Exit %E%
>>"%UE%" echo [%DATE% %TIME%] Ende   %N%  - Exit %E%
goto :eof

:vorbedingungen
where git.exe || (echo git.exe nicht gefunden. & exit /b 1)
where gh.exe || (echo gh.exe nicht gefunden - GitHub CLI: https://cli.github.com & exit /b 1)
git --version
gh --version
gh auth status >nul 2>&1 || (echo gh ist nicht angemeldet - bitte einmal  gh auth login  ausfuehren. & exit /b 1)
set "WER="
for /f "delims=" %%w in ('gh api user --jq .login 2^>nul') do set "WER=%%w"
echo Bei GitHub angemeldet als: %WER%
if /i not "%WER%"=="%KONTO%" (echo Erwartet: %KONTO% & exit /b 1)
if exist "%SH%\.git" (echo %SH% ist schon ein Git-Repo - Abbruch, damit nichts doppelt angelegt wird. & exit /b 1)
if exist "%HH%\.git" (echo %HH% ist schon ein Git-Repo - Abbruch, damit nichts doppelt angelegt wird. & exit /b 1)
if not exist "%SH%\.gitignore" (echo %SH%\.gitignore fehlt. & exit /b 1)
if not exist "%HH%\.gitignore" (echo %HH%\.gitignore fehlt. & exit /b 1)
if not exist "%RE%\.git" (echo %RE% ist kein Git-Repo. & exit /b 1)
gh repo view %KONTO%/Steuerhaus >nul 2>&1 && (echo Das Repo %KONTO%/Steuerhaus gibt es schon auf GitHub. & exit /b 1)
gh repo view %KONTO%/HalligHooge >nul 2>&1 && (echo Das Repo %KONTO%/HalligHooge gibt es schon auf GitHub. & exit /b 1)
for /f "delims=" %%b in ('git -C "%RE%" branch --show-current') do set "VORHER=%%b"
echo Renderer: Zweig %VORHER%
if "%VORHER%"=="" (echo Renderer steht auf keinem Zweig. & exit /b 1)
if /i "%VORHER%"=="%ZWEIG%" (echo Renderer steht schon auf %ZWEIG%. & exit /b 1)
set "URL="
for /f "delims=" %%u in ('git -C "%RE%" remote get-url origin') do set "URL=%%u"
echo Renderer: origin %URL%
echo %URL%| findstr /i /c:"github.com/%KONTO%/Renderer" /c:"github.com:%KONTO%/Renderer" >nul || (echo origin zeigt nicht auf %KONTO%/Renderer. & exit /b 1)
git -C "%RE%" show-ref --verify --quiet refs/heads/%ZWEIG% && (echo Den Zweig %ZWEIG% gibt es im Renderer schon. & exit /b 1)
git -C "%RE%" fetch origin || (echo git fetch fehlgeschlagen. & exit /b 1)
git -C "%RE%" ls-remote --exit-code --heads origin %ZWEIG% >nul && (echo Den Zweig %ZWEIG% gibt es auf GitHub schon. & exit /b 1)
git -C "%RE%" merge-base --is-ancestor HEAD origin/master && echo Renderer: %VORHER% ist in origin/master enthalten - der Pull Request zeigt nur den neuen Stand.
exit /b 0

:vormerken
git -C "%RE%" config user.name "%KONTO%" || exit /b 1
git -C "%RE%" config user.email "%NOREPLY%" || exit /b 1
git -C "%RE%" switch -c %ZWEIG% || exit /b 1
git -C "%RE%" rm -r -q --cached --ignore-unmatch _p5 nbproject/private || exit /b 1
git -C "%RE%" add -A || exit /b 1
git -C "%RE%" status --short | find /c /v ""
git -C "%SH%" init -q || exit /b 1
set "NEU_S=1"
call :neu_vormerken "%SH%" || exit /b 1
git -C "%HH%" init -q || exit /b 1
set "NEU_H=1"
call :neu_vormerken "%HH%" || exit /b 1
exit /b 0

:neu_vormerken
git -C "%~1" symbolic-ref HEAD refs/heads/master || exit /b 1
git -C "%~1" config user.name "%KONTO%" || exit /b 1
git -C "%~1" config user.email "%NOREPLY%" || exit /b 1
git -C "%~1" add -A || exit /b 1
git -C "%~1" status --short | find /c /v ""
exit /b 0

:zuruecknehmen
echo Ruecknahme:
set "JETZT="
for /f "delims=" %%b in ('git -C "%RE%" branch --show-current') do set "JETZT=%%b"
if /i "%JETZT%"=="%ZWEIG%" if defined VORHER (
  git -C "%RE%" reset -q
  git -C "%RE%" switch "%VORHER%"
  git -C "%RE%" branch -D %ZWEIG%
)
if defined NEU_S if exist "%SH%\.git" rmdir /s /q "%SH%\.git"
if defined NEU_H if exist "%HH%\.git" rmdir /s /q "%HH%\.git"
git -C "%RE%" branch --show-current
exit /b 0

:probe_klonen
if exist "%PROBE%" rmdir /s /q "%PROBE%"
mkdir "%PROBE%" || exit /b 1
git clone -q --depth 1 --branch %ZWEIG% https://github.com/%KONTO%/Renderer.git "%PROBE%\Renderer" || exit /b 1
git clone -q --depth 1 https://github.com/%KONTO%/Steuerhaus.git "%PROBE%\Steuerhaus" || exit /b 1
git clone -q --depth 1 https://github.com/%KONTO%/HalligHooge.git "%PROBE%\HalligHooge" || exit /b 1
dir /b "%PROBE%\Renderer" "%PROBE%\Steuerhaus" "%PROBE%\HalligHooge"
exit /b 0

:probe_lib
for %%d in (Renderer Steuerhaus HalligHooge) do (
  robocopy "%P%\%%d\lib" "%PROBE%\%%d\lib" /E /XF Renderer.jar Steuerhaus.jar /NFL /NDL /NJH /NJS /NP
  if errorlevel 8 exit /b 1
  if not exist "%PROBE%\%%d\nbproject\private" mkdir "%PROBE%\%%d\nbproject\private"
  if exist "%P%\%%d\nbproject\private\private.properties" copy /y "%P%\%%d\nbproject\private\private.properties" "%PROBE%\%%d\nbproject\private\" >nul
)
exit /b 0
