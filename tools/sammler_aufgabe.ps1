# HalligHooge - die stuendliche Aufgabe des Messarchivs (DB1, Werkbuch HalligHooge 167).
# Kopiert Steuerhaus.jar, Renderer.jar und ojdbc11.jar aus dist\lib nach %USERPROFILE%\.steuerhaus\HalligHooge\sammler
# (so stoert ein Clean and Build die Aufgabe nicht) und legt die Aufgabe "HalligHooge Messarchiv" an: javaw ohne Fenster,
# taeglich ab 00:07 jede Stunde, nur wenn Daniel angemeldet ist (kein gespeichertes Passwort), auch im Akkubetrieb,
# verpasste Laeufe sobald moeglich, hoechstens 20 min, nie zwei zugleich. Danach einmal gestartet.
# Aufruf: tools\sammler_aufgabe.cmd        (anlegen oder erneuern; nach einem neuen Bau des Steuerhauses wieder aufrufen)
#         tools\sammler_aufgabe.cmd aus    (Aufgabe entfernen; die Datenbank bleibt)
param([switch]$Aus)
$ErrorActionPreference = 'Stop'
$name = 'HalligHooge Messarchiv'
$projekt = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ($Aus) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "Aufgabe '$name' entfernt."
    exit 0
}

$ziel = Join-Path $env:USERPROFILE '.steuerhaus\HalligHooge\sammler'
New-Item -ItemType Directory -Force -Path $ziel | Out-Null
foreach ($j in 'Steuerhaus.jar', 'Renderer.jar', 'ojdbc11.jar') {
    $q = Join-Path $projekt "dist\lib\$j"
    if (-not (Test-Path $q)) { throw "$q fehlt - erst bauen (tools\lauf_DB1.cmd oder Clean and Build)" }
    Copy-Item $q (Join-Path $ziel $j) -Force
}
Write-Output "Bibliotheken nach $ziel kopiert."

$javaw = $null
if ($env:JDK21) { $javaw = Join-Path $env:JDK21 'bin\javaw.exe' }
if (-not $javaw -or -not (Test-Path $javaw)) {
    $c = Get-Command javaw.exe -ErrorAction SilentlyContinue
    if ($c) { $javaw = $c.Source }
}
if (-not $javaw -or -not (Test-Path $javaw)) { throw 'javaw.exe nicht gefunden - vorher  set JDK21=C:\Program Files\Java\jdk-21' }
$java = Join-Path (Split-Path $javaw) 'java.exe'
$alt = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$v = (& $java -version 2>&1 | Out-String)
$ErrorActionPreference = $alt
if ($v -notmatch 'version "(\d+)') { throw "Version von $java nicht lesbar: $v" }
if ([int]$Matches[1] -lt 21) { throw "$java ist Java $($Matches[1]), gebraucht wird 21 oder neuer" }

$manifest = Join-Path $projekt 'src\szenen\Hooge.steuerhaus'
$argumente = "-Dfile.encoding=UTF-8 -cp `"$ziel\*`" com.dan.steuerhaus.messung.Sammler --manifest `"$manifest`" --abruf"
$aktion = New-ScheduledTaskAction -Execute $javaw -Argument $argumente -WorkingDirectory $projekt
$ausloeser = New-ScheduledTaskTrigger -Daily -At '00:07'
$ausloeser.Repetition = (New-ScheduledTaskTrigger -Once -At '00:07' -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition
$einstellungen = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -MultipleInstances IgnoreNew
$wer = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$text = 'Holt stuendlich die Pegel (PEGELONLINE) und taeglich den Wind (DWD) ins Messarchiv HALLIGHOOGE (Werkbuch HalligHooge 167). Protokoll: %USERPROFILE%\.steuerhaus\HalligHooge\sammler.log'
Register-ScheduledTask -TaskName $name -Action $aktion -Trigger $ausloeser -Settings $einstellungen -Principal $wer -Description $text -Force | Out-Null
Write-Output "Aufgabe '$name' angelegt: jede Stunde zur Minute 07, $javaw"
Write-Output "  $argumente"
Start-ScheduledTask -TaskName $name
Write-Output "Einmal gestartet. Stand: Get-ScheduledTaskInfo -TaskName '$name'"
exit 0
