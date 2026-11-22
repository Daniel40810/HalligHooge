#!/usr/bin/env python3
"""Ortsnamen der Szene aus OpenStreetMap (Werkbuch HalligHooge 113, F187 A) - ein Werkzeug in einer Datei.

Python 3.8+ ohne Fremdpakete. Liest die benannten Objekte der Szene (Gebiet "szene" aus kartenmaterial.py) und
schreibt sie mit Art und Lage (UTM 32) nach <gebiet>/orte.txt. Das Manifest der Anwendung (Hooge.steuerhaus) waehlt
daraus aus und kann umbenennen.

    python tools/orte/orte.py --gebiet D:/Daten/HalligHooge/gebiet
    python tools/orte/orte.py --gebiet ... --osm <datei.json>     aus einer vorhandenen Antwort (etwa osm_szene.json)

Quelle: liegt osm_szene.json (kartenmaterial, "out body geom") im Download, wird sie gelesen. Sonst fragt das
Werkzeug Overpass nach den benannten Objekten derselben Szene ("out center tags", klein) und legt die Antwort unter
<download>/vektor/osm_orte/osm_orte.json ab; ein zweiter Lauf liest sie von dort.

Arten: Hallig, Insel, Warft, Sand, Kirche, Anleger, Priel, Ort. Gleiche Namen derselben Art innerhalb von 500 m [G]
werden zusammengelegt, verschiedene Namen derselben Art innerhalb von 120 m [G] auch (der erste bleibt). Seit Lauf W2
gelten keine Nummern als Namen und keine Gebaeude, Betriebe oder Anlagen als Warft, Sand oder Ort.

Daten: (c) OpenStreetMap-Mitwirkende, ODbL 1.0.
"""
import argparse
import datetime
import json
import math
import os
import re
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
PROJEKT = os.path.dirname(os.path.dirname(HIER))
sys.path.insert(0, os.path.join(PROJEKT, "tools", "kartenmaterial"))
import kartenmaterial as km  # noqa: E402

HALLIGEN = {"Hooge", "Langeneß", "Langeness", "Gröde", "Oland", "Nordstrandischmoor", "Norderoog", "Süderoog", "Südfall",
            "Hamburger Hallig", "Habel"}
ZUSAMMEN = 500.0
NAEHE = 120.0


def abfrage(bb):
    teile = ['nwr["name"]["place"]', 'nwr["name"]["amenity"~"^(place_of_worship|ferry_terminal)$"]',
             'nwr["name"]["building"~"^(church|chapel)$"]', 'nwr["name"]["man_made"~"^(pier|lighthouse|beacon)$"]',
             'nwr["name"]["harbour"]', 'nwr["name"]["leisure"="marina"]',
             'nwr["name"]["natural"~"^(sand|shoal|island|islet|beach|mud|water|bay|strait)$"]',
             'nwr["name"]["waterway"]', 'nwr["name"~"warft",i]']
    return "[out:json][timeout:300];(" + "".join(t + bb + ";" for t in teile) + ");out center tags;"


NUR_ZAHL = re.compile(r"^[\d\s,./-]+$")
# Merkmale einer Sache (Gebäude, Betrieb, Weg, Anlage): deren Namen nennen keinen Ort, auch wenn sie auf -warft enden
SACHE = ("building", "power", "amenity", "tourism", "shop", "office", "craft", "leisure", "historic", "highway", "route", "man_made")


def art(tags):
    """Art eines benannten Objekts (seit Lauf W2 strenger: keine Nummern, keine Gebaeude und Betriebe mit Ortsnamen)."""
    name = tags.get("name", "").strip()
    klein = name.lower()
    if not name or NUR_ZAHL.match(name):
        return None
    place, natural, waterway = tags.get("place", ""), tags.get("natural", ""), tags.get("waterway", "")
    sache = any(k in tags for k in SACHE)
    if klein.endswith(("warft", "warf")) and not sache:
        return "Warft"
    if (tags.get("building") in ("church", "chapel") or tags.get("amenity") == "place_of_worship") and re.search(r"kirche|kapelle|st\.|sankt", klein):
        return "Kirche"
    if tags.get("amenity") == "ferry_terminal" or tags.get("man_made") == "pier" and re.search(r"anleger|f\u00e4hr|mole", klein) \
            or "harbour" in tags and re.search(r"anleger|f\u00e4hr", klein):
        return "Anleger"
    if place in ("island", "islet") or natural in ("island", "islet"):
        if klein.endswith("sand"):
            return "Sand"
        return "Hallig" if name in HALLIGEN or klein.startswith("hallig ") else "Insel"
    if natural in ("sand", "shoal", "beach") and not sache and (natural == "shoal" or klein.endswith(("sand", "s\u00e4nde"))):
        return "Sand"
    if (waterway in ("river", "stream", "tidal_channel", "canal", "fairway") or natural in ("strait", "bay")
            or tags.get("water") in ("river", "tidal_channel")) and not re.search(r"route|weg|teich|villa|koje|hafen|see$", klein):
        return "Priel"
    if place in ("village", "hamlet", "isolated_dwelling", "locality", "town", "neighbourhood", "suburb") and not sache:
        return "Ort"
    return None


def lage(el):
    """(Laenge, Breite) eines Elements: Punkt, Mitte (out center) oder Mittel der Geometrie (out geom)."""
    if "lat" in el:
        return el["lon"], el["lat"]
    if "center" in el:
        return el["center"]["lon"], el["center"]["lat"]
    pts = el.get("geometry") or []
    for m in el.get("members", []):
        pts += m.get("geometry") or []
    pts = [p for p in pts if p]
    if pts:
        return sum(p["lon"] for p in pts) / len(pts), sum(p["lat"] for p in pts) / len(pts)
    if "bounds" in el:
        b = el["bounds"]
        return (b["minlon"] + b["maxlon"]) / 2, (b["minlat"] + b["maxlat"]) / 2
    return None


def finde(ordner, name, tiefe=3):
    """Sucht eine Datei bis zur Tiefe 3 unter dem Ordner (der Ordner der Daten ist gross)."""
    if not os.path.isdir(ordner):
        return None
    start = ordner.rstrip(os.sep).count(os.sep)
    for wurzel, unter, dateien in os.walk(ordner):
        if name in dateien:
            return os.path.join(wurzel, name)
        if wurzel.count(os.sep) - start >= tiefe:
            unter[:] = []
    return None


def main():
    ap = argparse.ArgumentParser(description="Ortsnamen der Szene aus OpenStreetMap nach <gebiet>/orte.txt")
    ap.add_argument("--gebiet", required=True, help="Ordner des gebackenen Gebiets (dort entsteht orte.txt)")
    vorgabe = os.environ.get("HALLIGHOOGE_DOWNLOAD") or (r"D:\Daten\HalligHooge" if os.path.isdir(r"D:\Daten\HalligHooge") else os.path.join(PROJEKT, "download"))
    ap.add_argument("--download", default=vorgabe, help="Download-Ordner von kartenmaterial (Vorgabe: %(default)s)")
    ap.add_argument("--osm", help="eine vorhandene Antwort von Overpass (JSON)")
    ap.add_argument("--gebietsname", default="szene", help="Gebiet aus kartenmaterial.py (Vorgabe: szene)")
    a = ap.parse_args()

    g = km.GEBIETE[a.gebietsname]
    quelle = a.osm or finde(a.download, "osm_szene.json") or finde(os.path.join(PROJEKT, "download"), "osm_szene.json")
    if not quelle:
        ziel = os.path.join(a.download, "vektor", "osm_orte", "osm_orte.json")
        print("osm_szene.json liegt nicht vor; Overpass, benannte Objekte der Szene ->", ziel)
        print("  ", km.laden_dienst(km._overpass(abfrage(km._bb(g))), ziel, art="json"))
        quelle = ziel
    print("Quelle:", quelle)
    with open(quelle, encoding="utf-8") as f:
        daten = json.load(f)

    e0, n0, e1, n1 = g.utm_huelle()
    orte = []
    for el in daten.get("elements", []):
        tags = el.get("tags") or {}
        if "name" not in tags:
            continue
        a_ = art(tags)
        if a_ is None:
            continue
        p = lage(el)
        if p is None:
            continue
        ost, nord = km.utm_vorwaerts(p[0], p[1])
        if not (e0 <= ost <= e1 and n0 <= nord <= n1):
            continue
        orte.append([a_, tags["name"].strip(), ost, nord, f"{el.get('type', '?')}/{el.get('id', '?')}"])

    # zusammenlegen: gleicher Name und gleiche Art naeher als ZUSAMMEN (Lage gemittelt); gleiche Art naeher als NAEHE mit
    # anderem Namen (Schreibweisen, zwei Anleger an einer Stelle): der erste bleibt
    gut = []
    for o in orte:
        for x in gut:
            d = math.hypot(x[2] - o[2], x[3] - o[3])
            if x[0] == o[0] and x[1] == o[1] and d < ZUSAMMEN:
                x[5] += 1
                x[2] += (o[2] - x[2]) / x[5]
                x[3] += (o[3] - x[3]) / x[5]
                break
            if x[0] == o[0] and d < NAEHE:
                break
        else:
            gut.append(o + [1])
    gut.sort(key=lambda o: (o[0], o[1]))

    os.makedirs(a.gebiet, exist_ok=True)
    datei = os.path.join(a.gebiet, "orte.txt")
    with open(datei, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Ortsnamen der Szene aus OpenStreetMap ((c) OpenStreetMap-Mitwirkende, ODbL 1.0)\n")
        f.write(f"# gezogen von tools/orte/orte.py am {datetime.datetime.now():%d.%m.%Y %H:%M} aus {os.path.basename(quelle)}\n")
        f.write("# Art; Name; Ost; Nord (UTM 32, m); OSM\n")
        for o in gut:
            f.write(f"{o[0]}; {o[1]}; {o[2]:.1f}; {o[3]:.1f}; {o[4]}\n")
    zahl = {}
    for o in gut:
        zahl[o[0]] = zahl.get(o[0], 0) + 1
    print(f"{len(gut)} Orte -> {datei}")
    for k in sorted(zahl):
        print(f"  {k:8s} {zahl[k]:4d}  " + ", ".join(o[1] for o in gut if o[0] == k)[:160])
    return 0 if gut else 1


if __name__ == "__main__":
    sys.exit(main())
