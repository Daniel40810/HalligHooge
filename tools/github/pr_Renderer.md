Der Stand des Renderers aus dem Projekt [HalligHooge](https://github.com/Daniel40810/HalligHooge) (Teil A bis D1). Die App darüber liegt im [Steuerhaus](https://github.com/Daniel40810/Steuerhaus) und in HalligHooge.

## Neu

| Teil | Inhalt |
|---|---|
| `com.dan.core` | Kern aus reinem Java: Raum, Zeit und Himmelsmechanik, Felder mit Katalog, Gitter mit Subgrid, Bus, Takt, Archiv, Bilanzen, Prüfrahmen, Szene |
| `com.dan.core.gpu` | Kern auf der Karte: Vulkan 1.3 über LWJGL, Kernels aus GLSL (SPIR-V), Abläufe mit Sperren, Zeitleisten |
| `com.dan.physics.*` | `hydro` (Flachwasser mit Subgrid), `tide` und `antrieb` (Gezeiten aus der Nordsee, Wind nach Charnock, ERA5), `waves` (Seegang), `sediment`, `atmos`, `aeolian` (Flugsand), `vegetation` (Salzwiese) |
| `com.dan.render.*` | `frame`, `terrain`, `water`, `air`, `reference` (Pfadverfolger als Referenz), `analysis` (Messblick), `overlay`, `bau` (Häuser auf den Warften), `bewuchs`, `brandung` |
| `com.dan.lauf` | Lauf, Archivquelle und Bühne: der allgemeine Teil einer Anwendung über einem Lauf |
| `com.dan.aufbereitung` | macht aus dem Kartenmaterial ein Gebiet für Physik und Bild |
| `com.dan.core.archiv` | seit D1 auch verlustfrei gepackte Archive (`Packung`, `Packer`), ein Vorrat für entpackte Stände; `lauf.demo.DatenUmzug` und `DatenCheck` |
| `docs/status/` | Prüfberichte und Status-Bilder der Phasen P1 bis P13 |

## Aufgeräumt

- `_p5/` und `nbproject/private/` sind nicht mehr im Repository. Sie stehen in `.gitignore` und bleiben auf der Platte.
- `.gitattributes`: Zeilenenden; `.cmd` und `.bat` behalten CRLF.
- LWJGL 3.4.3 (`lib/lwjgl/`) liegt nicht im Repository; woher es kommt, steht in der README unter *Bauen und starten*.

## Geprüft

- Lauf D1 auf Windows: CoreCheck 125 Prüfsteine, DatenCheck 31, JahrCheck 6 von 6, SteuerhausCheck 81, jeweils ohne Verstoß; die App mit allen 14 Szenarien bei 44 bis 60 Bildern/s, die Uhr hat nie auf Daten gewartet.
- Nach dem Hochladen klont `tools\github_G1.cmd` in HalligHooge (Schritt 7) die drei Repos frisch von GitHub, legt die Bibliotheken dazu und baut Renderer, Steuerhaus und HalligHooge.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_017B1juzy9zDkHcnBVz928cb
