-- HalligHooge · Messarchiv (DB1, Werkbuch HalligHooge 167): Ausbaustufe und Quellen. Beim zweiten Lauf meldet Oracle
-- ORA-00001 (Zeile vorhanden), das zählt nicht als Fehler. Stationen, Konstanten, Schwellen und Orte schreibt der
-- Sammler (--uebernehmen) aus dem Gebiet und dem Manifest.

INSERT INTO HH_SCHEMA (VERSION, TEXT) VALUES (1, 'DB1 Messarchiv: Pegel, Wind, Mittel, Scheitel, Schätzung am Ort, Wachstumsgrenze');

INSERT INTO HH_SCHEMA (VERSION, TEXT) VALUES (2, 'DB2 Chronik der Hochwasser, Wind 2020 bis 2025, Füllstand je Tabelle');

INSERT INTO HH_QUELLE (QUELLE_ID, KURZ, TITEL, ANBIETER, LIZENZ, ADRESSE) VALUES (1, 'PEGELONLINE', 'Wasserstand an den Pegeln, Rohdaten je Minute', 'Wasserstraßen- und Schifffahrtsverwaltung des Bundes (WSV)', 'DL-DE Zero 2.0', 'https://www.pegelonline.wsv.de/webservices/rest-api/v2');

INSERT INTO HH_QUELLE (QUELLE_ID, KURZ, TITEL, ANBIETER, LIZENZ, ADRESSE) VALUES (2, 'DWD', 'Wind, 10-Minuten-Werte an Stationen', 'Deutscher Wetterdienst, Climate Data Center', 'CC BY 4.0, Quelle: Deutscher Wetterdienst', 'https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/10_minutes/wind/');

INSERT INTO HH_QUELLE (QUELLE_ID, KURZ, TITEL, ANBIETER, LIZENZ, ADRESSE) VALUES (3, 'OSM', 'Ortsnamen der Szene', 'OpenStreetMap-Mitwirkende', 'ODbL 1.0', 'https://www.openstreetmap.org/copyright');

INSERT INTO HH_QUELLE (QUELLE_ID, KURZ, TITEL, ANBIETER, LIZENZ, ADRESSE) VALUES (4, 'GEZEITEN', 'Gezeit am Ort aus dem Tidenkalender der App (Modell und Messung), Windstau aus den Bezugspegeln', 'HalligHooge (eigene Rechnung)', 'wie die App', 'src/szenen/Hooge.gezeiten');

INSERT INTO HH_QUELLE (QUELLE_ID, KURZ, TITEL, ANBIETER, LIZENZ, ADRESSE) VALUES (5, 'GEBIET', 'Bestand der Aufbereitung: Pegel als Maßstab mit harmonischer Analyse über 30 Tage, Wind seit 2010', 'HalligHooge (com.dan.aufbereitung)', 'wie die Quellen', 'daten/gebiet');

COMMIT;
