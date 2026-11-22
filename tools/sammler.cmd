@echo off
rem HalligHooge - den Sammler des Messarchivs von Hand aufrufen (DB1, Werkbuch HalligHooge 167). Beispiele:
rem   tools\sammler.cmd --bericht                       Fuellstand, Faecher, Stationen, Abrufe, Hochwasser, Sturmfluten, Landunter
rem   tools\sammler.cmd --abruf                         was die Aufgabe stuendlich tut
rem   tools\sammler.cmd --pflege --nur-plan             was die Pflege wegnehmen wuerde (ohne etwas zu tun)
rem   tools\sammler.cmd --pruefen --gebiet daten\gebiet Pruefsteine DB1
rem   tools\sammler.cmd --verbinden                     Verbindung pruefen, fehlt das Passwort: einmal fragen
rem   tools\sammler.cmd --guete                         seit DB3: Modell gegen Messung (nach Ausgabe --guete), schreibt Hooge.guete
rem   tools\sammler.cmd --gezeiten                      seit DB5: die Gezeit waechst mit (sonst am 1. jedes Monats von selbst)
rem Vorher bauen (Clean and Build oder tools\lauf_DB1.cmd).
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."
if not exist dist\HalligHooge.jar (
  echo dist\HalligHooge.jar fehlt - bitte erst bauen.
  exit /b 1
)
java -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 -cp dist\HalligHooge.jar com.dan.steuerhaus.messung.Sammler --manifest src\szenen\Hooge.steuerhaus %*
exit /b %ERRORLEVEL%
