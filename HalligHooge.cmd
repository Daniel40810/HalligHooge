@echo off
rem HalligHooge starten (Werkbuch HalligHooge Teil B). Vorher bauen: Clean and Build in NetBeans oder Renderer\tools\lauf_TeilB.cmd.
rem Aufruf mit Szenario:  HalligHooge.cmd --szenario sturm     (ruhig, sturm, live; siehe src\szenen\Hooge.szenen)
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
if not exist dist\HalligHooge.jar (
  echo dist\HalligHooge.jar fehlt - bitte erst bauen.
  pause
  goto :eof
)
java -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 --enable-native-access=ALL-UNNAMED -Xmx12g -jar dist\HalligHooge.jar --szenen src\szenen\Hooge.szenen %*
if errorlevel 1 pause
