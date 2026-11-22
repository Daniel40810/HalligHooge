# G1 GitHub (Werkbuch HalligHooge 164): prueft, was in den drei Repos vorgemerkt ist, bevor etwas hochgeladen wird.
# Aufruf aus tools\github_G1.cmd:
#   powershell -NoProfile -ExecutionPolicy Bypass -File G1_pruefen.ps1 -Grenze <Bytes> -Log <Datei> <Repo> <Repo> ...
# Zeigt je Repo: Dateien im Repo, neu / geaendert / entfernt, was hochgeladen wird (nach Ordnern, die groessten Dateien).
# Verstoesse (Exit 1): eine Datei ueber der Grenze; Zugangsdaten oder Daten im Repo (USER.sql, db.properties, .cdsapirc,
# gepackte Archive, daten\, _to_delete\, _p5\, .claude\, build\, dist\, nbproject\private\); ein Passwort in manage_user
# oder IDENTIFIED BY; password= in einer .properties-Datei; ein Schluessel des CDS; die eigene E-Mail-Adresse aus
# git config --global (sie wird nie ausgegeben); eine Identitaet ohne noreply-Adresse.
param(
    [long]$Grenze = 52428800,
    [string]$Log = "",
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Repos
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$script:verstoesse = 0

function Sag([string]$t) {
    Write-Host $t
    if ($Log -ne "") { Add-Content -LiteralPath $Log -Value $t -Encoding UTF8 }
}

function Verstoss([string]$t) {
    $script:verstoesse++
    Sag ("  VERSTOSS: " + $t)
}

function MB([double]$b) { return ("{0,9:N1} MB" -f ($b / 1MB)) }

function GitAus([string]$repo, [string[]]$argumente) {
    $aus = & git.exe -C $repo -c core.quotepath=off @argumente 2>$null
    return @($aus | Where-Object { $_ -ne $null -and $_ -ne "" })
}

$verboten = @(
    '(^|/)USER\.sql$', '(^|/)db\.properties$', '(^|/)\.cdsapirc$', '\.(f16z|f32z|teil)$', '(^|/)hs_err_pid',
    '^(daten|_to_delete|_p5|\.claude|build|dist)/', '^nbproject/private/'
)
$geheim = @(
    @{ Text = "Passwort in manage_user";         Muster = "manage_user\( *'[^']*' *, *'[^<']";           Pfad = @() },
    @{ Text = "Passwort nach IDENTIFIED BY";     Muster = "identified +by +[^< ]";                        Pfad = @() },
    @{ Text = "password= in .properties";        Muster = "^ *password *= *[^ ]";                         Pfad = @("*.properties") },
    @{ Text = "Schluessel des CDS (key: ...)";   Muster = "key: *([0-9]+:)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"; Pfad = @() }
)
$mail = (& git.exe config --global user.email 2>$null)
if ($mail -ne $null) { $mail = "$mail".Trim() }
$mailPruefen = ($mail -ne $null -and $mail -ne "" -and $mail -notlike "*noreply*")

$gesamtHoch = 0.0
foreach ($repo in $Repos) {
    $name = Split-Path $repo -Leaf
    Sag ""
    Sag ("=== " + $name + "  (" + $repo + ")")

    $zweig = (GitAus $repo @("branch", "--show-current")) -join ""
    $identitaet = (GitAus $repo @("config", "user.email")) -join ""
    Sag ("  Zweig: " + $zweig + "   Identitaet: " + ((GitAus $repo @("config", "user.name")) -join "") + " <" + $identitaet + ">")
    if ($identitaet -notlike "*users.noreply.github.com") { Verstoss "Identitaet ohne noreply-Adresse (git config user.email)" }

    $dateien = GitAus $repo @("ls-files")
    $groesse = @{}
    $summe = 0.0
    foreach ($d in $dateien) {
        $f = Join-Path $repo ($d -replace '/', '\')
        $b = 0
        if (Test-Path -LiteralPath $f -PathType Leaf) { $b = (Get-Item -LiteralPath $f).Length }
        $groesse[$d] = $b
        $summe += $b
    }

    $neu = @(); $geaendert = @(); $entfernt = @()
    foreach ($z in (GitAus $repo @("diff", "--cached", "--no-renames", "--name-status"))) {
        $t = $z -split "`t", 2
        if ($t.Count -lt 2) { continue }
        switch -Regex ($t[0]) {
            '^A' { $neu += $t[1] }
            '^D' { $entfernt += $t[1] }
            default { $geaendert += $t[1] }
        }
    }
    $hoch = @($neu + $geaendert)
    $hochSumme = 0.0
    foreach ($d in $hoch) { if ($groesse.ContainsKey($d)) { $hochSumme += $groesse[$d] } }
    $gesamtHoch += $hochSumme

    Sag ("  Im Repo danach: {0} Dateien,{1}" -f $dateien.Count, (MB $summe))
    Sag ("  Vorgemerkt: {0} neu, {1} geaendert, {2} entfernt; hochzuladen:{3}" -f $neu.Count, $geaendert.Count, $entfernt.Count, (MB $hochSumme))
    if ($entfernt.Count -gt 0) {
        $ordnerWeg = $entfernt | ForEach-Object { ($_ -split '/')[0] } | Group-Object | Sort-Object Count -Descending
        Sag ("  Entfernt (bleibt auf der Platte): " + (($ordnerWeg | ForEach-Object { $_.Name + " (" + $_.Count + ")" }) -join ", "))
    }

    Sag "  Hochzuladen nach Ordnern:"
    $hoch | ForEach-Object {
        $teile = $_ -split '/'
        $k = if ($teile.Count -gt 2) { $teile[0] + "/" + $teile[1] } else { $teile[0] }
        [pscustomobject]@{ Ordner = $k; Bytes = $groesse[$_] }
    } | Group-Object Ordner | ForEach-Object {
        [pscustomobject]@{ Ordner = $_.Name; Anzahl = $_.Count; Bytes = ($_.Group | Measure-Object Bytes -Sum).Sum }
    } | Sort-Object Bytes -Descending | Select-Object -First 10 | ForEach-Object {
        Sag ("    {0} {1,6} Dateien  {2}" -f (MB $_.Bytes), $_.Anzahl, $_.Ordner)
    }
    Sag "  Die groessten Dateien im Repo:"
    $groesse.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
        Sag ("    {0}  {1}" -f (MB $_.Value), $_.Key)
    }

    foreach ($d in $dateien) {
        if ($groesse[$d] -gt $Grenze) { Verstoss ("ueber " + (MB $Grenze).Trim() + ": " + $d + " (" + (MB $groesse[$d]).Trim() + ")") }
        foreach ($m in $verboten) { if ($d -match $m) { Verstoss ("gehoert nicht ins Repo: " + $d) } }
    }
    foreach ($g in $geheim) {
        $a = @("grep", "--cached", "-l", "-I", "-i", "-E", $g.Muster)
        if ($g.Pfad.Count -gt 0) { $a += "--"; $a += $g.Pfad }
        foreach ($d in (GitAus $repo $a)) { Verstoss ($g.Text + ": " + $d) }
    }
    if ($mailPruefen) {
        foreach ($d in (GitAus $repo @("grep", "--cached", "-l", "-I", "-i", "-F", $mail))) { Verstoss ("die eigene E-Mail-Adresse steht in: " + $d) }
    }
}

Sag ""
Sag ("Zusammen hochzuladen:" + (MB $gesamtHoch) + ";  Grenze je Datei:" + (MB $Grenze))
if (-not $mailPruefen) { Sag "Hinweis: keine private Adresse in git config --global user.email - diese Pruefung entfaellt." }
if ($script:verstoesse -gt 0) {
    Sag ("ERGEBNIS: " + $script:verstoesse + " Verstoss/Verstoesse - es wird nichts hochgeladen.")
    exit 1
}
Sag "ERGEBNIS: kein Verstoss."
exit 0
