#!/usr/bin/env python3
"""Kartenmaterial fuer HalligHooge - ein Werkzeug in einer Datei.

Python 3.8+ ohne Fremdpakete (Windows, Linux, macOS). Gebiete nach Werkbuch Teil A, Abschnitt 10.

    python tools/kartenmaterial/kartenmaterial.py liste             Quellen, Stufen, Gebiete
    python tools/kartenmaterial/kartenmaterial.py plan              was "laden" holen wuerde
    python tools/kartenmaterial/kartenmaterial.py laden             alle Quellen der Stufe "standard"
    python tools/kartenmaterial/kartenmaterial.py laden --gross     dazu die grossen (EasyGSH 1996-2014, ERA5, PBF)
    python tools/kartenmaterial/kartenmaterial.py laden --quellen dgm1,dop20 --gebiet szene
    python tools/kartenmaterial/kartenmaterial.py laden --quellen trilawatt_topographie --jahre 2015-2021
    python tools/kartenmaterial/kartenmaterial.py laden --quellen dgm1 --gebiet szene --jahre 2024   das Land der Szene
    python tools/kartenmaterial/kartenmaterial.py laden --quellen era5_cds --monate 202610         ERA5 aus dem Climate Data Store
    python tools/kartenmaterial/kartenmaterial.py laden --quellen era5_cds_schub --monate 202610   dazu die Schubspannung (F34)
    python tools/kartenmaterial/kartenmaterial.py laden --quellen era5_cds_seegang --monate 202610 Seegang (P8b, F74 A)
    python tools/kartenmaterial/kartenmaterial.py laden --quellen era5_cds_luft --monate 202610    Luft und Strahlung (P10b)
    python tools/kartenmaterial/kartenmaterial.py laden --quellen era5_cds_boee --monate 202610,201312  Boee fg10 (Seegang S8b)
    python tools/kartenmaterial/kartenmaterial.py laden --quellen dwd_wind                         Wind des DWD, Helgoland und List (F36 A)
    python tools/kartenmaterial/kartenmaterial.py laden --quellen sentinel2 --baender B02,B03,B04  Baender fuer die Eichung der Albedo (F44 A)
    python tools/kartenmaterial/kartenmaterial.py laden --quellen lod2 --ziel D:/Daten/HalligHooge    3D-Gebaeude LoD2 (P12a, F125 A)
    python tools/kartenmaterial/kartenmaterial.py laden --quellen bdom --ziel D:/Daten/HalligHooge    Oberflaechenmodell bDOM 20 cm (P12c, F136 A)
    python tools/kartenmaterial/kartenmaterial.py einsortieren      Handdownloads (DTK5-Mehrfachdownload, ZIPs) einordnen
    python tools/kartenmaterial/kartenmaterial.py dgm1-tif --loeschen     DGM1-Kacheln XYZ -> GeoTIFF
    python tools/kartenmaterial/kartenmaterial.py inventar          INVENTAR.md und inventar.csv neu
    python tools/kartenmaterial/kartenmaterial.py gebiete           Gebiete als GeoJSON fuer QGIS

Ziel: --ziel, sonst die Umgebungsvariable HALLIGHOOGE_DOWNLOAD, sonst download/ im Projekt
(in .gitignore). Je Quelle ein Ordner <ziel>/<gruppe>/<quelle>/. Abgebrochene Dateien werden
fortgesetzt, vorhandene uebersprungen. Antworten von Diensten (WCS, WMS, Overpass, PEGELONLINE,
Massendownload) werden auf ihre Art geprueft; eine Fehlermeldung statt Daten steht im Inventar
unter "Fehlgeschlagen". Der Ordner kann nach der Aufbereitung geloescht werden; INVENTAR.md und
_status/ halten fest, was woher kam.

DGM1 und DOP20 kommen aus den Kachelindizes des Massendownloads des LVermGeo SH
(Downloadclient -> Massendownload -> GeoJSON). Sie liegen in tools/kartenmaterial/index/:
    DGM1_SH__Massendownload.geojson, DOP20_SH__Massendownload.geojson
Fuer einen neuen Stand die GeoJSON dort ersetzen.

ERA5 aus dem Climate Data Store (Quelle era5_cds, Werkbuch 12.6, F28) braucht ein Konto: Der Schluessel steht in
%USERPROFILE%\\.cdsapirc (Zeilen "url: https://cds.climate.copernicus.eu/api" und "key: ..."), die Lizenz von ERA5
(single levels) ist auf der Seite des Datensatzes angenommen. Das Werkzeug liest die Datei selbst und gibt den
Schluessel nie aus. Ohne Fremdpakete (kein cdsapi): Auftrag, Warten, Laden ueber die Schnittstelle (retrieve/v1).

Gebiete (UTM 32 = ETRS89 / UTM 32N, EPSG:25832; Hoehen NHN):
    schelf         G0  15 W - 13 O, 43 - 64 N             Tide (EOT20), Tiefe (GEBCO), Wetter (ERA5)
    bucht          G1  6,0 - 9,1 O, 53,2 - 55,8 N         Deutsche Bucht: EMODnet, Pegel
    nordfriesland  G2  O 428-500 km, N 6011-6096 km       Kennwerte, Sediment, OSM-Kueste
    szene          G3  O 454-478 km, N 6025-6057 km       Hooge und die Aussensaende
    kern               O 461-475 km, N 6043-6051 km       Hooge und Japsand, feinste Daten
"""

import argparse
import array
import concurrent.futures as cf
import csv
import glob
import http.client
import io
import json
import math
import os
import re
import shutil
import ssl
import struct
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import zlib
from dataclasses import dataclass, field

HIER = os.path.dirname(os.path.abspath(__file__))
PROJEKT = os.path.dirname(os.path.dirname(HIER))
INDEX_ORDNER = os.path.join(HIER, "index")
BEFEHLE = ("liste", "plan", "laden", "einsortieren", "inventar", "gebiete", "dgm1-tif")


# ===========================================================================
# 1  RAUM: UTM, MGRS, GEBIETE
# ===========================================================================
_A = 6378137.0                      # GRS80 (ETRS89; fuer diese Zwecke gleich WGS84)
_F = 1 / 298.257222101
_E = math.sqrt(_F * (2 - _F))
_N = _F / (2 - _F)
_AA = _A / (1 + _N) * (1 + _N ** 2 / 4 + _N ** 4 / 64)
_ALPHA = (_N / 2 - 2 * _N ** 2 / 3 + 5 * _N ** 3 / 16, 13 * _N ** 2 / 48 - 3 * _N ** 3 / 5, 61 * _N ** 3 / 240)
_BETA = (_N / 2 - 2 * _N ** 2 / 3 + 37 * _N ** 3 / 96, _N ** 2 / 48 + _N ** 3 / 15, 17 * _N ** 3 / 480)
_DELTA = (2 * _N - 2 * _N ** 2 / 3 - 2 * _N ** 3, 7 * _N ** 2 / 3 - 8 * _N ** 3 / 5, 56 * _N ** 3 / 15)
_K0 = 0.9996


def utm_vorwaerts(lon, lat, zone=32):
    """Laenge/Breite (Grad) -> (Ost, Nord) in Metern (Krueger-Reihen nach Karney 2011)."""
    lam = math.radians(lon - (zone * 6 - 183))
    phi = math.radians(lat)
    t = math.sinh(math.atanh(math.sin(phi)) - _E * math.atanh(_E * math.sin(phi)))
    xi_, eta_ = math.atan2(t, math.cos(lam)), math.atanh(math.sin(lam) / math.sqrt(1 + t * t))
    xi, eta = xi_, eta_
    for j, a in enumerate(_ALPHA, 1):
        xi += a * math.sin(2 * j * xi_) * math.cosh(2 * j * eta_)
        eta += a * math.cos(2 * j * xi_) * math.sinh(2 * j * eta_)
    return 500000.0 + _K0 * _AA * eta, _K0 * _AA * xi


def utm_rueckwaerts(ost, nord, zone=32):
    """(Ost, Nord) in Metern -> Laenge/Breite (Grad)."""
    xi, eta = nord / (_K0 * _AA), (ost - 500000.0) / (_K0 * _AA)
    xi_, eta_ = xi, eta
    for j, b in enumerate(_BETA, 1):
        xi_ -= b * math.sin(2 * j * xi) * math.cosh(2 * j * eta)
        eta_ -= b * math.cos(2 * j * xi) * math.sinh(2 * j * eta)
    chi = math.asin(math.sin(xi_) / math.cosh(eta_))
    phi = chi + sum(d * math.sin(2 * j * chi) for j, d in enumerate(_DELTA, 1))
    return math.degrees(math.atan2(math.sinh(eta_), math.cos(xi_))) + (zone * 6 - 183), math.degrees(phi)


def mgrs_kachel(lon, lat):
    """Kennung des 100-km-Quadrats (Sentinel-2-Kachel), z. B. (8.548, 54.571) -> '32UMF'."""
    zone = int((lon + 180) // 6) + 1
    ost, nord = utm_vorwaerts(lon, lat, zone)
    band = "CDEFGHJKLMNPQRSTUVWX"[int((lat + 80) // 8)]
    spalte = ("ABCDEFGH", "JKLMNPQR", "STUVWXYZ")[(zone - 1) % 3][int(ost // 100000) - 1]
    zeile = "ABCDEFGHJKLMNPQRSTUV"[(int(nord // 100000) + (5 if zone % 2 == 0 else 0)) % 20]
    return f"{zone:02d}{band}{spalte}{zeile}"


class Gebiet:
    """Rechteck in UTM 32 (volle km) oder in Grad (fuer die grossen Gitter)."""

    def __init__(self, name, kuerzel, zweck, utm=None, grad=None):
        self.name, self.kuerzel, self.zweck, self.utm, self._grad = name, kuerzel, zweck, utm, grad

    def rand_grad(self, schritte=40):
        """Ring in Grad (Laenge, Breite) entlang des Randes."""
        if self.utm:
            e0, n0, e1, n1 = self.utm
            pts = []
            for (xa, ya), (xb, yb) in (((e0, n0), (e0, n1)), ((e0, n1), (e1, n1)), ((e1, n1), (e1, n0)), ((e1, n0), (e0, n0))):
                pts += [utm_rueckwaerts(xa + i / schritte * (xb - xa), ya + i / schritte * (yb - ya)) for i in range(schritte)]
            return pts
        w, s, o, n = self._grad
        pts = []
        for (xa, ya), (xb, yb) in (((w, s), (w, n)), ((w, n), (o, n)), ((o, n), (o, s)), ((o, s), (w, s))):
            pts += [(xa + i / schritte * (xb - xa), ya + i / schritte * (yb - ya)) for i in range(schritte)]
        return pts

    @property
    def lonlat(self):
        """(West, Sued, Ost, Nord) in Grad, umschliessend."""
        if self._grad:
            return self._grad
        pts = self.rand_grad()
        return (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))

    def utm_huelle(self):
        """(Ost0, Nord0, Ost1, Nord1) in UTM 32; bei Grad-Gebieten die umschliessende Huelle auf volle km."""
        if self.utm:
            return self.utm
        pts = [utm_vorwaerts(lon, lat) for lon, lat in self.rand_grad()]
        return (math.floor(min(p[0] for p in pts) / 1000) * 1000, math.floor(min(p[1] for p in pts) / 1000) * 1000,
                math.ceil(max(p[0] for p in pts) / 1000) * 1000, math.ceil(max(p[1] for p in pts) / 1000) * 1000)

    def enthaelt(self, lon, lat):
        if self.utm:
            e, n = utm_vorwaerts(lon, lat)
            return self.utm[0] <= e <= self.utm[2] and self.utm[1] <= n <= self.utm[3]
        w, s, o, n = self._grad
        return w <= lon <= o and s <= lat <= n

    def flaeche_km2(self):
        if self.utm:
            e0, n0, e1, n1 = self.utm
            return (e1 - e0) * (n1 - n0) / 1e6
        w, s, o, n = self._grad
        return 6371.0 ** 2 * math.radians(o - w) * (math.sin(math.radians(n)) - math.sin(math.radians(s)))


GEBIETE = {g.name: g for g in (
    Gebiet("schelf", "G0", "Nordwesteuropäischer Schelf: Tide (EOT20), Tiefe (GEBCO), Wetter (ERA5)", grad=(-15.0, 43.0, 13.0, 64.0)),
    Gebiet("bucht", "G1", "Deutsche Bucht: Tiefe (EMODnet), Pegel", grad=(6.0, 53.2, 9.1, 55.8)),
    Gebiet("nordfriesland", "G2", "Nordfriesisches Wattenmeer: Kennwerte, Sediment, Küste", utm=(428000, 6011000, 500000, 6096000)),
    Gebiet("szene", "G3", "Hooge, Japsand, Norderoogsand, Norderoog, Süderoogsand, Süderoog", utm=(454000, 6025000, 478000, 6057000)),
    Gebiet("kern", "G3/G4", "Hooge und Japsand: DGM1, DOP20, DTK5", utm=(461000, 6043000, 475000, 6051000)),
)}


# ===========================================================================
# 2  NETZ
# ===========================================================================
AGENT = "HalligHooge-Kartenmaterial/2.0 (Werkzeug fuer offene Geodaten)"
NETZFEHLER = (urllib.error.URLError, TimeoutError, ConnectionError, OSError, http.client.HTTPException)


class DienstFehler(Exception):
    """Der Dienst hat geantwortet, aber nicht mit Daten. Kein neuer Versuch."""


def _zertifikat(e):
    """Kann Python die Zertifikatskette nicht pruefen (etwa fehlendes Zwischenzertifikat beim Server)?"""
    return isinstance(getattr(e, "reason", None), ssl.SSLCertVerificationError) or "CERTIFICATE_VERIFY_FAILED" in str(e)


CURL = shutil.which("curl.exe") or shutil.which("curl")


def _curl(url, ziel=None, fortsetzen=False, kopf=None):
    """Ausweg bei Zertifikatsfehlern: curl prueft mit dem Zertifikatsspeicher des Systems (unter Windows Schannel,
    das fehlende Zwischenzertifikate nachlaedt wie der Browser). Ohne ziel kommt der Inhalt als bytes zurueck."""
    if not CURL:
        raise DienstFehler("Zertifikat des Servers für Python nicht prüfbar, und curl wurde nicht gefunden")
    cmd = [CURL, "-L", "-f", "-sS", "--retry", "3", "--connect-timeout", "30", "--speed-limit", "1000",
           "--speed-time", "180", "-A", AGENT]
    for k, v in (kopf or {}).items():
        cmd += ["-H", f"{k}: {v}"]
    if ziel:
        cmd += ["-o", ziel] + (["-C", "-"] if fortsetzen else [])
    r = subprocess.run(cmd + [url], capture_output=True)
    if r.returncode:
        raise DienstFehler(f"curl {r.returncode}: {r.stderr.decode('utf-8', 'replace').strip()[:200]}")
    return None if ziel else r.stdout


def _anfrage(url, kopf=None, methode="GET"):
    k = {"User-Agent": AGENT}
    k.update(kopf or {})
    return urllib.request.Request(url, headers=k, method=methode)


def hole(url, versuche=4, timeout=120, kopf=None):
    """Inhalt als bytes; wiederholt bei Netzfehlern (2, 4, 8 s)."""
    warte = 2
    for i in range(versuche):
        try:
            with urllib.request.urlopen(_anfrage(url, kopf), timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (400, 401, 403, 404, 410) or i == versuche - 1:
                raise
        except NETZFEHLER as e:
            if _zertifikat(e):
                return _curl(url, kopf=kopf)
            if i == versuche - 1:
                raise
        time.sleep(warte)
        warte *= 2


def hole_text(url, **kw):
    return hole(url, **kw).decode("utf-8", errors="replace")


def hole_json(url, **kw):
    return json.loads(hole(url, **kw))


def s3_liste(basis, prefix, trenner=None):
    """Oeffentlicher S3-Bucket (ListObjectsV2) -> ([(key, groesse)], [unterordner])."""
    dateien, ordner, token = [], [], None
    while True:
        q = {"list-type": "2", "prefix": prefix}
        if trenner:
            q["delimiter"] = trenner
        if token:
            q["continuation-token"] = token
        x = hole_text(basis.rstrip("/") + "/?" + urllib.parse.urlencode(q))
        ent = lambda s: s.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"')
        for m in re.finditer(r"<Contents>.*?<Key>([^<]*)</Key>.*?<Size>(\d+)</Size>.*?</Contents>", x, re.S):
            dateien.append((ent(m.group(1)), int(m.group(2))))
        ordner += [ent(p) for p in re.findall(r"<CommonPrefixes><Prefix>([^<]*)</Prefix>", x)]
        m = re.search(r"<NextContinuationToken>([^<]*)</NextContinuationToken>", x)
        if not m:
            return dateien, ordner
        token = ent(m.group(1))


def s3_url(basis, key):
    return basis.rstrip("/") + "/" + urllib.parse.quote(key)


def verzeichnis(url, tiefe=1):
    """Dateien unter einem Verzeichnis mit HTML-Index (Apache/nginx), bis zur angegebenen Tiefe."""
    url = url if url.endswith("/") else url + "/"
    html = hole_text(url, timeout=90)
    dateien, ordner = [], []
    for h in re.findall(r'href="([^"]+)"', html, re.I):
        if h.startswith(("?", "#", "mailto:")):
            continue
        voll = urllib.parse.urljoin(url, h)
        if not voll.startswith(url) or voll == url:
            continue
        (ordner if voll.endswith("/") else dateien).append(voll)
    out = list(dict.fromkeys(dateien))
    if tiefe > 1:
        for o in dict.fromkeys(ordner):
            try:
                out += verzeichnis(o, tiefe - 1)
            except Exception:
                out.append(o + " (nicht lesbar)")
    return out


_ART = {"tiff": (b"II*\x00", b"MM\x00*", b"II+\x00", b"MM\x00+"), "jpeg": (b"\xff\xd8",), "png": (b"\x89PNG",),
        "zip": (b"PK",), "json": (b"{", b"["), "netcdf": (b"CDF", b"\x89HDF"), "grib": (b"GRIB",),
        "citygml": (b"<?xml", b"<core:CityModel", b"<CityModel", b"\xef\xbb\xbf<?xml")}


def pruefe_art(pfad, art):
    """Erste Bytes pruefen; schickt ein Dienst eine Fehlermeldung (XML, HTML) statt Daten -> DienstFehler."""
    if not art:
        return
    with open(pfad, "rb") as f:
        kopf = f.read(4096)
    k = kopf.lstrip()
    if art == "xyz" and (k[:2] == b"PK" or (k[:1] and k[:1] in b"0123456789-+.")):
        return
    if art in _ART and any(k.startswith(m) for m in _ART[art]):
        return
    text = " ".join(re.sub(r"<[^>]+>", " ", kopf.decode("utf-8", errors="replace")).split())[:300]
    os.remove(pfad)
    raise DienstFehler(f"Antwort ist kein {art}: {text}")


def laden(url, ziel, soll=None, versuche=8):
    """Laedt eine feste Datei; setzt eine angefangene .part-Datei fort (HTTP-Range)."""
    teil = ziel + ".part"
    if os.path.exists(ziel) and (soll is None or os.path.getsize(ziel) == soll):
        return "vorhanden"
    os.makedirs(os.path.dirname(ziel) or ".", exist_ok=True)
    warte = 2
    for versuch in range(versuche):
        try:
            schon = os.path.getsize(teil) if os.path.exists(teil) else 0
            with urllib.request.urlopen(_anfrage(url, {"Range": f"bytes={schon}-"} if schon else {}), timeout=180) as r:
                if schon and r.status != 206:
                    schon = 0
                laenge = r.headers.get("Content-Length")
                gesamt = int(laenge) + schon if laenge else soll
                n = schon
                with open(teil, "ab" if schon else "wb") as f:
                    while True:
                        block = r.read(1 << 20)
                        if not block:
                            break
                        f.write(block)
                        n += len(block)
                if laenge and n < gesamt:
                    raise http.client.IncompleteRead(b"", gesamt - n)
            if soll is not None and os.path.getsize(teil) != soll:
                raise IOError(f"Größe {os.path.getsize(teil)} statt {soll}")
            os.replace(teil, ziel)
            return "geladen"
        except urllib.error.HTTPError as e:
            if e.code == 416 and os.path.exists(teil):
                os.replace(teil, ziel)
                return "geladen"
            if e.code in (401, 403, 404, 410) or versuch == versuche - 1:
                raise DienstFehler(f"HTTP {e.code}") from None
        except NETZFEHLER as e:
            if _zertifikat(e):
                print(f"    Zertifikat für Python nicht prüfbar, lade mit curl: {url.rsplit('/', 1)[-1][:60]}", file=sys.stderr)
                _curl(url, teil, fortsetzen=os.path.exists(teil))
                if soll is not None and os.path.getsize(teil) != soll:
                    raise IOError(f"Größe {os.path.getsize(teil)} statt {soll}")
                os.replace(teil, ziel)
                return "geladen (curl)"
            if versuch == versuche - 1:
                raise
            print(f"    {type(e).__name__}, setze in {warte} s fort: {url.rsplit('/', 1)[-1][:60]}", file=sys.stderr)
        time.sleep(warte)
        warte = min(warte * 2, 60)


def laden_dienst(url, ziel, art=None, versuche=4, timeout=600):
    """Laedt die Antwort eines Dienstes ganz (ohne Range) und prueft ihre Art."""
    if os.path.exists(ziel):
        return "vorhanden"
    teil = ziel + ".part"
    os.makedirs(os.path.dirname(ziel) or ".", exist_ok=True)
    warte = 5
    for versuch in range(versuche):
        try:
            with urllib.request.urlopen(_anfrage(url), timeout=timeout) as r, open(teil, "wb") as f:
                while True:
                    block = r.read(1 << 20)
                    if not block:
                        break
                    f.write(block)
            pruefe_art(teil, art)
            os.replace(teil, ziel)
            return "geladen"
        except urllib.error.HTTPError as e:
            if e.code in (400, 401, 403, 404, 410) or versuch == versuche - 1:
                try:
                    meldung = " ".join(re.sub(r"<[^>]+>", " ", e.read().decode("utf-8", "replace")).split())[:300]
                except Exception:
                    meldung = ""
                raise DienstFehler(f"HTTP {e.code}: {meldung}") from None
        except NETZFEHLER as e:
            if _zertifikat(e):
                _curl(url, teil)
                pruefe_art(teil, art)
                os.replace(teil, ziel)
                return "geladen (curl)"
            if versuch == versuche - 1:
                raise
        print(f"    neuer Versuch in {warte} s: {url[:90]}", file=sys.stderr)
        time.sleep(warte)
        warte *= 2


# ===========================================================================
# 3  GEOTIFF: Ausschnitt aus einem COG im Netz lesen, GeoTIFF schreiben
# ===========================================================================
_TYP = {1: "B", 2: "s", 3: "H", 4: "I", 5: "II", 6: "b", 7: "B", 8: "h", 9: "i", 10: "ii", 11: "f", 12: "d", 16: "Q", 17: "q", 18: "Q"}
_BYTES = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 16: 8, 17: 8, 18: 8}


class _FernDatei:
    """Datei im Netz ueber HTTP-Range, Zwischenspeicher je 256 KiB."""
    BLOCK = 1 << 18

    def __init__(self, url):
        self.url, self.pos, self.cache = url, 0, {}

    def seek(self, pos):
        self.pos = pos

    def tell(self):
        return self.pos

    def read(self, n):
        out = bytearray()
        while n > 0:
            b, o = divmod(self.pos, self.BLOCK)
            if b not in self.cache:
                if len(self.cache) > 512:
                    self.cache.clear()
                a = b * self.BLOCK
                self.cache[b] = hole(self.url, kopf={"Range": f"bytes={a}-{a + self.BLOCK - 1}"})
            d = self.cache[b][o:o + n]
            if not d:
                break
            out += d
            self.pos += len(d)
            n -= len(d)
        return bytes(out)

    def close(self):
        self.cache.clear()


class GeoTiff:
    """Gekacheltes GeoTIFF/COG (klassisch oder BigTIFF), Deflate/LZW/ohne, Praediktor 1-3, ein Kanal.
    stufe = Uebersichtsstufe (0 voll, 1 halb, ...)."""

    def __init__(self, pfad, stufe=0):
        self.f = _FernDatei(pfad) if str(pfad).startswith("http") else open(pfad, "rb")
        kopf = self.f.read(16)
        self.e = "<" if kopf[:2] == b"II" else ">"
        self.big = struct.unpack(self.e + "H", kopf[2:4])[0] == 43
        off = struct.unpack(self.e + ("Q" if self.big else "I"), kopf[8:16] if self.big else kopf[4:8])[0]
        ifds = []
        while off:
            ifd, off = self._ifd(off)
            ifds.append(ifd)
        voll = ifds[0]
        stufen = [voll] + [i for i in ifds[1:] if not (i.get(254, [0])[0] & 4)]
        t = stufen[min(stufe, len(stufen) - 1)]
        self.breite, self.hoehe = t[256][0], t[257][0]
        self.bits, self.format = t.get(258, [8])[0], t.get(339, [1])[0]
        self.kompression, self.praediktor = t.get(259, [1])[0], t.get(317, [1])[0]
        self.kanaele = t.get(277, [1])[0]
        self.kachel = (t[322][0], t[323][0]) if 322 in t else None
        self.offsets, self.laengen = t.get(324) or t.get(273), t.get(325) or t.get(279)
        fx, fy = voll[256][0] / self.breite, voll[257][0] / self.hoehe
        tp, sc = voll[33922], voll[33550]
        self.ursprung = (tp[3] - tp[0] * sc[0], tp[4] + tp[1] * sc[1])
        self.pixel = (sc[0] * fx, sc[1] * fy)
        keys = {}
        if 34735 in voll:
            g = voll[34735]
            for i in range(4, 4 + 4 * g[3], 4):
                if g[i + 1] == 0:
                    keys[g[i]] = g[i + 3]
        self.epsg = keys.get(3072) or keys.get(2048)
        self.punkt = keys.get(1025) == 2
        self.nodata = None
        if 42113 in voll:
            try:
                self.nodata = float(voll[42113].strip("\x00 "))
            except ValueError:
                pass

    def _ifd(self, off):
        e = self.e
        self.f.seek(off)
        n = struct.unpack(e + ("Q" if self.big else "H"), self.f.read(8 if self.big else 2))[0]
        groesse, zeiger = (20, "Q") if self.big else (12, "I")
        roh = self.f.read(n * groesse + (8 if self.big else 4))
        ifd = {}
        for i in range(n):
            s = roh[i * groesse:(i + 1) * groesse]
            tag, typ, anzahl = struct.unpack(e + ("HHQ" if self.big else "HHI"), s[:12 if self.big else 8])
            feld = s[12:20] if self.big else s[8:12]
            g = _BYTES.get(typ, 1) * anzahl
            if g > len(feld):
                pos = self.f.tell()
                self.f.seek(struct.unpack(e + zeiger, feld)[0])
                daten = self.f.read(g)
                self.f.seek(pos)
            else:
                daten = feld[:g]
            if typ == 2:
                ifd[tag] = daten.decode("latin-1")
            elif typ in (5, 10):
                v = struct.unpack(e + _TYP[typ][0] * (2 * anzahl), daten)
                ifd[tag] = [v[i] / v[i + 1] if v[i + 1] else 0 for i in range(0, len(v), 2)]
            elif typ in _TYP:
                ifd[tag] = list(struct.unpack(e + _TYP[typ] * anzahl, daten))
        return ifd, struct.unpack(e + zeiger, roh[n * groesse:])[0]

    def _block(self, i, bw, bh):
        self.f.seek(self.offsets[i])
        roh = self.f.read(self.laengen[i])
        if self.kompression in (8, 32946):
            roh = zlib.decompress(roh)
        elif self.kompression == 5:
            roh = _lzw(roh)
        elif self.kompression != 1:
            raise ValueError(f"Kompression {self.kompression} nicht unterstützt")
        k, nb = self.kanaele, self.bits // 8
        n = bw * bh * k
        roh = roh[:n * nb].ljust(n * nb, b"\0")
        if self.praediktor == 3:
            zeile, w = bw * k * nb, bw * k
            ba, out = bytearray(roh), bytearray(len(roh))
            for r in range(bh):
                z = ba[r * zeile:(r + 1) * zeile]
                for j in range(1, zeile):
                    z[j] = (z[j] + z[j - 1]) & 0xFF
                for x in range(w):
                    for b in range(nb):
                        out[r * zeile + x * nb + ((nb - 1 - b) if self.e == "<" else b)] = z[b * w + x]
            roh = bytes(out)
        zeichen = {3: {32: "f", 64: "d"}, 2: {8: "b", 16: "h", 32: "i"}}.get(self.format, {8: "B", 16: "H", 32: "I"})[self.bits]
        werte = list(struct.unpack(f"{self.e}{n}{zeichen}", roh))
        if self.praediktor == 2:
            maske = (1 << self.bits) - 1
            for r in range(bh):
                b0 = r * bw * k
                for x in range(k, bw * k):
                    werte[b0 + x] = (werte[b0 + x] + werte[b0 + x - k]) & maske
            if self.format == 2:
                halb = 1 << (self.bits - 1)
                werte = [v - (1 << self.bits) if v >= halb else v for v in werte]
        return werte

    def grenzen(self):
        x0, y0 = self.ursprung
        px, py = self.pixel
        if self.punkt:
            x0, y0 = x0 - px / 2, y0 + py / 2
        return x0, y0 - self.hoehe * py, x0 + self.breite * px, y0

    def ausschnitt(self, x0, y0, x1, y1):
        """Liest nur die Kacheln im Rechteck (Koordinaten der Datei) -> (zeilen, ursprung, pixel)."""
        gx0, _, _, gy1 = self.grenzen()
        px, py = self.pixel
        c0, c1 = max(0, int((x0 - gx0) // px)), min(self.breite, int(-(-(x1 - gx0) // px)))
        r0, r1 = max(0, int((gy1 - y1) // py)), min(self.hoehe, int(-(-(gy1 - y0) // py)))
        bild = [[0] * (c1 - c0) for _ in range(r1 - r0)]
        tw, th = self.kachel
        je_zeile = (self.breite + tw - 1) // tw
        for ty in range(r0 // th, (r1 - 1) // th + 1):
            for tx in range(c0 // tw, (c1 - 1) // tw + 1):
                i = ty * je_zeile + tx
                if not self.laengen[i]:
                    continue
                werte = self._block(i, tw, th)
                for r in range(th):
                    y = ty * th + r
                    if r0 <= y < r1:
                        z = bild[y - r0]
                        for c in range(tw):
                            x = tx * tw + c
                            if c0 <= x < c1:
                                z[x - c0] = werte[(r * tw + c) * self.kanaele]
        return bild, (gx0 + c0 * px, gy1 - r0 * py), (px, py)

    def schliessen(self):
        self.f.close()


def _lzw(d):
    tab = [bytes([i]) for i in range(256)] + [b"", b""]
    out, bits, pos, alt, n = bytearray(), 9, 0, None, len(d) * 8
    while pos + bits <= n:
        chunk = int.from_bytes(d[pos >> 3:(pos >> 3) + 4].ljust(4, b"\0"), "big")
        code = (chunk >> (32 - bits - (pos & 7))) & ((1 << bits) - 1)
        pos += bits
        if code == 256:
            tab, bits, alt = tab[:258], 9, None
            continue
        if code == 257:
            break
        if alt is None:
            eintrag = tab[code]
        elif code < len(tab):
            eintrag = tab[code]
            tab.append(alt + eintrag[:1])
        else:
            eintrag = alt + alt[:1]
            tab.append(eintrag)
        out += eintrag
        alt = eintrag
        if len(tab) + 1 >= (1 << bits) and bits < 12:
            bits += 1
    return bytes(out)


def tiff_schreiben(pfad, zeilen, ursprung, pixel, epsg, nodata=None, typ="f"):
    """Unkomprimiertes GeoTIFF, ein Kanal; typ 'f' float32 oder 'h' int16; ursprung = obere linke Pixelkante."""
    H, W = len(zeilen), len(zeilen[0])
    bits, fmt = (32, 3) if typ == "f" else (16, 2)
    nb = bits // 8
    keys = [1, 1, 0, 3] + ([1024, 0, 1, 2, 1025, 0, 1, 1, 2048, 0, 1, epsg] if 4000 <= epsg < 5000
                           else [1024, 0, 1, 1, 1025, 0, 1, 1, 3072, 0, 1, epsg])
    eintraege = [(256, 4, [W]), (257, 4, [H]), (258, 3, [bits]), (259, 3, [1]), (262, 3, [1]), (273, 4, None),
                 (277, 3, [1]), (278, 4, [1]), (279, 4, [W * nb] * H), (284, 3, [1]), (339, 3, [fmt]),
                 (33550, 12, [pixel[0], pixel[1], 0.0]), (33922, 12, [0.0, 0.0, 0.0, ursprung[0], ursprung[1], 0.0]),
                 (34735, 3, keys)]
    if nodata is not None:
        eintraege.append((42113, 2, (repr(nodata) + "\0").encode()))
    eintraege.sort(key=lambda t: t[0])
    fz, gr = {3: "H", 4: "I", 12: "d", 2: None}, {3: 2, 4: 4, 12: 8, 2: 1}
    extra_pos = 8 + 2 + 12 * len(eintraege) + 4
    daten_pos = extra_pos + sum(gr[t] * len(v if v is not None else range(H)) for _, t, v in eintraege
                                if gr[t] * len(v if v is not None else range(H)) > 4) + 16
    eintraege = [(tag, t, v if v is not None else [daten_pos + r * W * nb for r in range(H)]) for tag, t, v in eintraege]
    ifd, extra = struct.pack("<H", len(eintraege)), b""
    for tag, t, v in eintraege:
        roh = v if t == 2 else struct.pack("<" + fz[t] * len(v), *v)
        if len(roh) <= 4:
            ifd += struct.pack("<HHI", tag, t, len(v)) + roh.ljust(4, b"\0")
        else:
            ifd += struct.pack("<HHII", tag, t, len(v), extra_pos + len(extra))
            extra += roh + (b"\0" if len(roh) % 2 else b"")
    ifd += struct.pack("<I", 0)
    with open(pfad, "wb") as f:
        f.write(b"II*\0" + struct.pack("<I", 8) + ifd + extra)
        f.write(bytes(daten_pos - f.tell()))
        for z in zeilen:
            f.write(struct.pack(f"<{W}{typ}", *z))


# ===========================================================================
# 4  QUELLEN: Rahmen und Hilfen
# ===========================================================================
@dataclass
class Datei:
    url: str
    pfad: str                   # relativ zum Ordner der Quelle
    groesse: int = None
    notiz: str = ""
    dienst: bool = False        # Antwort eines Dienstes: ganz laden, nicht fortsetzen
    art: str = None             # tiff, jpeg, png, zip, json, netcdf, xyz
    ausschnitt: tuple = None    # (x0, y0, x1, y1) in der Abbildung eines COG: nur diesen Teil lesen
    stufe: int = 0              # Uebersichtsstufe des COG fuer den Ausschnitt
    ersatz: tuple = ()          # liegt eine dieser Dateien vor, gilt die Datei als da
    cds: tuple = None           # (Sammlung, Anfrage): Auftrag im Climate Data Store statt fester Adresse


@dataclass
class Quelle:
    id: str
    gruppe: str
    titel: str
    anbieter: str
    lizenz: str
    gebiet: str
    stufe: str
    text: str
    seite: str
    plan: object = field(repr=False, default=None)
    pruefung: object = field(repr=False, default=None)


class Ctx:
    def __init__(self, gebiet, opt):
        self.gebiet, self.opt, self.beilagen, self.hinweis = gebiet, opt, {}, None


QUELLEN = {}
GRUPPEN = {"hoehe": "Höhe (Land und trockenes Watt)", "bathymetrie": "Wassertiefe und Topographie des Watts",
           "gezeiten": "Gezeiten, Strömung, Pegel", "sediment": "Sediment", "wetter": "Wetter (Antrieb)",
           "karten": "Karten", "luftbild": "Luft- und Satellitenbild", "vektor": "Vektordaten",
           "gebaeude": "Gebäude (3D-Modelle)",
           "verzeichnis": "Verzeichnisse der BAW (zum Nachsehen)"}


def quelle(id, gruppe, titel, anbieter, lizenz, gebiet, stufe, text, seite):
    def deko(f):
        QUELLEN[id] = Quelle(id, gruppe, titel, anbieter, lizenz, gebiet, stufe, " ".join(text.split()), seite, f)
        return f
    return deko


SH_LIZENZ = "CC BY 4.0, „© GeoBasis-DE/LVermGeo SH/CC BY 4.0“"
BAW_LIZENZ = "CC BY 4.0, „Quellenvermerk: Bundesanstalt für Wasserbau <Jahr des Datenbezugs>“; nicht für die Navigation"
BAW_WCS = "https://coast.baw.de/geoserver"
BAW_REPO = "https://dl.datenrepository.baw.de/7000"
EASYGSH = BAW_REPO + "/B3955.02.04.70229/EasyGSH-DB"
TRILAWATT = BAW_REPO + "/B3955.02.04.70237"
SH_WMS = "https://service.gdi-sh.de"
SH_CLIENT = "https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload/"


def _csv(kopf, zeilen):
    s = io.StringIO()
    w = csv.writer(s, lineterminator="\n")
    w.writerow(kopf)
    w.writerows(zeilen)
    return s.getvalue()


def _name(url):
    return urllib.parse.unquote(url.split("?")[0].rstrip("/").rsplit("/", 1)[-1])


def _jahre(ctx, vorgabe, gueltig):
    """Jahre aus --jahre ('2015', '1996-2014', '2006,2016'), sonst die Vorgabe; nur gueltige."""
    roh = ctx.opt.get("jahre")
    if not roh:
        return [j for j in vorgabe if j in gueltig]
    out = []
    for teil in str(roh).split(","):
        a, _, b = teil.strip().partition("-")
        out += range(int(a), int(b or a) + 1) if a else []
    return [j for j in out if j in gueltig]


def _gleich(x0, y0, x1, y1, hoechstens, raster):
    """Gleich grosse Rechtecke auf dem Raster, hoechstens so breit und hoch wie angegeben."""
    nx, ny = max(1, math.ceil((x1 - x0) / hoechstens - 1e-9)), max(1, math.ceil((y1 - y0) / hoechstens - 1e-9))
    sx = math.ceil((x1 - x0) / nx / raster) * raster
    sy = math.ceil((y1 - y0) / ny / raster) * raster
    y = y0
    while y < y1 - 1e-9:
        x, yb = x0, min(y + sy, y1)
        while x < x1 - 1e-9:
            xb = min(x + sx, x1)
            yield x, y, xb, yb
            x = xb
        y = yb


_ACHSEN = {}


def _wcs_achsen(basis, cov):
    """(EPSG, [Achsen]) aus DescribeCoverage; Vorgabe 25832 mit E/N."""
    if (basis, cov) not in _ACHSEN:
        erg = (25832, ["E", "N"])
        try:
            x = hole_text(f"{basis}?service=WCS&version=2.0.1&request=DescribeCoverage&coverageId={urllib.parse.quote(cov)}",
                          timeout=180, versuche=2)
            m = re.search(r"<gml:Envelope[^>]*>", x)
            srs = re.search(r'srsName="[^"]*?(\d+)"', m.group(0)) if m else None
            ax = re.search(r'axisLabels="([^"]+)"', m.group(0)) if m else None
            if srs and ax:
                erg = (int(srs.group(1)), ax.group(1).split())
        except Exception:
            pass
        _ACHSEN[(basis, cov)] = erg
    return _ACHSEN[(basis, cov)]


def _wcs_url(basis, cov, achsen, box, fmt="image/tiff"):
    """GetCoverage 2.0.1 fuer box = (x0, y0, x1, y1): x Ost bzw. Laenge, y Nord bzw. Breite."""
    x0, y0, x1, y1 = box
    teile = ""
    for a in achsen:
        if a.lower() in ("e", "x", "long", "lon", "easting"):
            teile += f"&subset={a}({x0:.6f},{x1:.6f})"
        elif a.lower() in ("n", "y", "lat", "northing"):
            teile += f"&subset={a}({y0:.6f},{y1:.6f})"
    return (f"{basis}?service=WCS&version=2.0.1&request=GetCoverage&coverageId={urllib.parse.quote(cov)}"
            f"&format={urllib.parse.quote(fmt)}{teile}")


def _wcs_box(g, epsg):
    if epsg == 25832:
        return g.utm_huelle()
    if epsg == 4326:
        return g.lonlat
    raise ValueError(f"Abbildung EPSG:{epsg} wird nicht umgerechnet (erwartet 25832 oder 4326)")


def _wms(ctx, qid, basis, ebene, aufloesung, fmt, endung, max_px=4000):
    """max_px: Kantenlaenge je Anfrage; der DTK5-Dienst lehnt Anfragen ueber 500 interne Kacheln ab."""
    """GetMap-Kacheln in EPSG:25832 mit Weltdatei je Kachel."""
    e0, n0, e1, n1 = ctx.gebiet.utm_huelle()
    out = []
    for x0, y0, x1, y1 in _gleich(e0, n0, e1, n1, max_px * aufloesung, aufloesung):
        w, h = int(round((x1 - x0) / aufloesung)), int(round((y1 - y0) / aufloesung))
        q = {"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap", "LAYERS": ebene, "STYLES": "", "CRS": "EPSG:25832",
             "BBOX": f"{x0:.1f},{y0:.1f},{x1:.1f},{y1:.1f}", "WIDTH": w, "HEIGHT": h, "FORMAT": fmt}
        name = f"{ebene}_{aufloesung:g}m_{int(x0)}_{int(y0)}"
        out.append(Datei(basis + "?" + urllib.parse.urlencode(q), f"{name}.{endung}", dienst=True,
                         art={"jpg": "jpeg", "png": "png"}[endung], notiz=f"{w} × {h} px"))
        ctx.beilagen[f"{qid}/{name}.{endung[0]}{endung[-1]}w"] = (
            f"{aufloesung}\n0\n0\n{-aufloesung}\n{x0 + aufloesung / 2:.3f}\n{y1 - aufloesung / 2:.3f}\n")
    ctx.beilagen[f"{qid}/LIESMICH.txt"] = (f"{basis}, Ebene {ebene}, {aufloesung} m je Bildpunkt, EPSG:25832 "
                                           f"(Weltdatei je Bild).\nLizenz: {SH_LIZENZ}\n")
    return out


def _wms_ebene(basis, muster):
    x = hole_text(basis + "?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetCapabilities", timeout=90)
    for n in re.findall(r"<Layer[^>]*>\s*<Name>([^<]+)</Name>", x):
        if muster in n.lower():
            return n
    raise ValueError(f"keine Ebene mit '{muster}' in {basis}")


def _massen_index(muster):
    """Neueste GeoJSON des Massendownloads (index/ neben diesem Werkzeug) -> (pfad, [properties])."""
    kandidaten = sorted(glob.glob(os.path.join(INDEX_ORDNER, muster)) + glob.glob(os.path.join(HIER, muster)),
                        key=os.path.getmtime)
    if not kandidaten:
        raise FileNotFoundError(f"Index {muster} fehlt in {INDEX_ORDNER} – im Downloadclient {SH_CLIENT} "
                                "unter Massendownload als GeoJSON speichern und dort ablegen")
    with open(kandidaten[-1], encoding="utf-8") as f:
        return kandidaten[-1], [ft["properties"] for ft in json.load(f)["features"]]


def _massen_kacheln(muster, regex, g):
    """Kacheln des Index im Gebiet: [(datei, ost_km, nord_km, datum, adresse)]."""
    pfad, props = _massen_index(muster)
    e0, n0, e1, n1 = g.utm_huelle()
    out = []
    for p in props:
        m = re.search(regex, p.get("link_data", ""))
        if m:
            e, n = int(m.group(2)), int(m.group(3))
            if e0 // 1000 <= e < -(-e1 // 1000) and n0 // 1000 <= n < -(-n1 // 1000):
                out.append((m.group(1), e, n, p.get("datum", ""), p["link_data"]))
    return pfad, sorted(out, key=lambda t: (t[1], t[2]))


DGM1_RE = r"file=(dgm1_32_(\d{3})_(\d{4})_1_sh(?:_\d{4})?\.\w+)"
DOP20_RE = r"file=(dop20rgbi_32_(\d{3})_(\d{4})_1_sh_\d{4}(?:_bw)?\.tif)"
BDOM_RE = r"file=(bdom20\w*_32_(\d{3})_(\d{4})_1_sh_\d{4}\.tif)"


def _kachel_pruefung(muster, regex, namen_re):
    def pruefe(ordner, g):
        da = set()
        for _, _, dateien in os.walk(ordner):
            for f in dateien:
                m = re.search(namen_re, f)
                if m and not f.endswith(".part"):
                    da.add((int(m.group(1)), int(m.group(2))))
        _, ks = _massen_kacheln(muster, regex, g)
        fehlen = [f"{e}_{n}" for _, e, n, _, _ in ks if (e, n) not in da]
        jahre = {}
        for _, e, n, datum, _ in ks:
            j = jahre.setdefault(datum[:4] or "?", [0, 0])
            j[0] += (e, n) in da
            j[1] += 1
        je_jahr = ", ".join(f"{j}: {a} von {b}" for j, (a, b) in sorted(jahre.items()))
        return (f"{len(ks) - len(fehlen)} von {len(ks)} Kacheln im Gebiet {g.name} vorhanden ({je_jahr})."
                + (f" Es fehlen u. a.: {', '.join(fehlen[:12])}" + (" …" if len(fehlen) > 12 else "") if fehlen else ""))
    return pruefe


# ===========================================================================
# 5  QUELLEN
# ===========================================================================
# ---- Hoehe ----------------------------------------------------------------
@quelle("dgm1", "hoehe", "DGM1 Schleswig-Holstein (Laserscan, 1 m)", "LVermGeo SH", SH_LIZENZ, "kern", "standard",
        """Warften, Sommerdeich, Prielkanten, trockenes Watt. Kacheln 1 × 1 km als XYZ (rund 27 MB), EPSG:25832, aus dem
        Index des Massendownloads (index/DGM1_SH__Massendownload.geojson). Kern 90 Kacheln, Szene 445 (--gebiet szene).
        Hooge 2024 beflogen, Watt und Sände 2005; westlich von rund 464 km Ost keine Kacheln. Mit --jahre nur die
        Kacheln dieser Befliegungen (z. B. --gebiet szene --jahre 2024: das Land der Szene). Danach 'dgm1-tif'.""",
        SH_CLIENT + "dl-dgm1.html")
def _p(ctx):
    pfad, ks = _massen_kacheln("DGM1_SH__Massendownload*.geojson", DGM1_RE, ctx.gebiet)
    jahre = {}
    for _, _, _, datum, _ in ks:
        jahre[datum[:4]] = jahre.get(datum[:4], 0) + 1
    ctx.beilagen[f"dgm1/kacheln_{ctx.gebiet.name}.csv"] = _csv(["datei", "ost_km", "nord_km", "befliegung"], [k[:4] for k in ks])
    gewaehlt = _jahre(ctx, sorted(int(j) for j in jahre if j.isdigit()), {int(j) for j in jahre if j.isdigit()})
    if ctx.opt.get("jahre"):
        ks = [k for k in ks if k[3][:4].isdigit() and int(k[3][:4]) in gewaehlt]
    ctx.beilagen["dgm1/LIESMICH.txt"] = (
        f"DGM1 Schleswig-Holstein, 1 × 1 km je Kachel, EPSG:25832, Höhen NHN. Index: {os.path.basename(pfad)}\n"
        f"Gebiet {ctx.gebiet.name}: {sum(jahre.values())} Kacheln ({', '.join(f'{j}: {n}' for j, n in sorted(jahre.items()))}).\n"
        + (f"Geladen nur die Befliegungen {', '.join(map(str, gewaehlt))} (--jahre): {len(ks)} Kacheln.\n"
           if ctx.opt.get("jahre") else "") +
        f"In GeoTIFF float32 umwandeln (Ordner tif/), XYZ danach löschen:\n"
        f"  python tools/kartenmaterial/kartenmaterial.py dgm1-tif --loeschen\nLizenz: {SH_LIZENZ}\n")
    return [Datei(url, datei, dienst=True, art="xyz", notiz=f"Befliegung {datum}",
                  ersatz=("tif/" + os.path.splitext(datei)[0] + ".tif",)) for datei, e, n, datum, url in ks]


QUELLEN["dgm1"].pruefung = _kachel_pruefung("DGM1_SH__Massendownload*.geojson", DGM1_RE, r"dgm1_32_(\d{3})_(\d{4})")


@quelle("copernicus_glo30", "hoehe", "Copernicus DEM GLO-30 (Föhr, Amrum, Pellworm, Festland)", "ESA / Airbus",
        "Copernicus DEM Lizenz (frei, © DLR/Airbus)", "nordfriesland", "standard",
        "Oberflächenmodell 30 m für das Land in G2 außerhalb der Szene. Ganzgradkacheln (COG) mit Wassermaske.",
        "https://registry.opendata.aws/copernicus-dem/")
def _p(ctx):
    basis, out = "https://copernicus-dem-30m.s3.amazonaws.com", []
    w, s, o, n = ctx.gebiet.lonlat
    for lat in range(math.floor(s), math.ceil(n)):
        for lon in range(math.floor(w), math.ceil(o)):
            name = f"Copernicus_DSM_COG_10_N{lat:02d}_00_E{lon:03d}_00_DEM"
            for k, gr in s3_liste(basis, name + "/")[0]:
                if k.endswith(("_DEM.tif", "_WBM.tif", ".xml")):
                    out.append(Datei(s3_url(basis, k), f"{name}/{_name(k)}", gr))
    return out


# ---- Wassertiefe und Topographie --------------------------------------------
@quelle("gebco", "bathymetrie", "GEBCO 2025, Ausschnitt Schelf (G0)", "GEBCO / BODC (Spiegel: source.coop)",
        "GEBCO-Nutzungsbedingungen (frei, Namensnennung)", "schelf", "standard",
        """Land und Meer für G0 bis zum Schelfrand, aus der ersten Übersichtsstufe (30", rund 0,9 km) des 3,3-GB-COG per
        HTTP-Range gelesen, als GeoTIFF int16, EPSG:4326. Die Rechnung dauert einige Minuten.""",
        "https://www.gebco.net/data-products/gridded-bathymetry-data")
def _p(ctx):
    basis = "https://s3.us-west-2.amazonaws.com/us-west-2.opendata.source.coop/ausantarctic/gebco/"
    return [Datei(basis + "GEBCO_2025.tif", f"GEBCO_2025_{ctx.gebiet.name}_30s.tif", notiz="Ausschnitt",
                  ausschnitt=ctx.gebiet.lonlat, stufe=1),
            Datei(basis + "GEBCO_2025.stac-item.json", "GEBCO_2025.stac-item.json")]


@quelle("emodnet", "bathymetrie", "EMODnet Digital Bathymetry, Deutsche Bucht (G1)", "EMODnet Bathymetry",
        "frei, Namensnennung (EMODnet Bathymetry Consortium)", "bucht", "standard",
        "Mittlere Wassertiefe 1/16' (rund 115 m) aus dem WCS (emodnet__mean, EPSG:4326) in vier Kacheln.",
        "https://emodnet.ec.europa.eu/en/bathymetry")
def _p(ctx):
    w, s, o, n = ctx.gebiet.lonlat
    out = []
    for i in range(2):
        for j in range(2):
            box = (w + i * (o - w) / 2, s + j * (n - s) / 2, w + (i + 1) * (o - w) / 2, s + (j + 1) * (n - s) / 2)
            out.append(Datei(_wcs_url("https://ows.emodnet-bathymetry.eu/wcs", "emodnet__mean", ["Lat", "Long"], box),
                             f"emodnet_mean_{box[0]:.2f}_{box[1]:.2f}.tif", dienst=True, art="tiff"))
    return out


@quelle("trilawatt_topographie", "bathymetrie", "TrilaWatt Topographie des Wattenmeers (10 m, je Jahr)", "BAW (TrilaWatt)",
        BAW_LIZENZ, "nordfriesland", "standard",
        """Nachfolger von EasyGSH: jährliche Topographien 2015–2021 (Stand 1. Juli) der 12-sm-Zone, GeoTIFF 10 m, aus dem
        BAW-Datenrepository. Vorgabe das jüngste Jahr 2021, andere mit --jahre (2022 nur als Vorversion). Die Dateien
        werden aus dem Verzeichnis gewählt (deutscher Teil); jede deckt das ganze deutsche Wattenmeer.""",
        "https://trilawatt.eu/daten/datenprodukte/")
def _p(ctx):
    jahre = _jahre(ctx, [2021], range(2015, 2023))
    try:
        alle = [u for u in verzeichnis(TRILAWATT + "/Topographie/", 2) if u.lower().endswith((".zip", ".tif", ".tiff"))]
    except Exception as e:
        alle = []
        ctx.hinweis = f"Verzeichnis {TRILAWATT}/Topographie/ nicht lesbar ({e}); Dateinamen geraten"
    out = []
    for j in jahre:
        treffer = [u for u in alle if str(j) in _name(u) and "_nl" not in _name(u).lower()]
        deutsch = [u for u in treffer if "ger" in _name(u).lower() or "_de" in _name(u).lower()]
        for u in (deutsch or treffer or [f"{TRILAWATT}/Topographie/topography_{j}_ger.zip"]):
            out.append(Datei(u, f"{j}/{_name(u)}", art="zip" if u.lower().endswith(".zip") else "tiff"))
    if 2022 in jahre:
        out.append(Datei(f"{TRILAWATT}/Topographie_PP_Update/topography_2022_ger_update.zip",
                         "2022/topography_2022_ger_update.zip", art="zip"))
    return out


@quelle("easygsh_bathymetrie", "bathymetrie", "EasyGSH-DB Bathymetrie 1996–2014, Szene (10 m)", "BAW (EasyGSH-DB)",
        BAW_LIZENZ, "szene", "gross",
        """Die Jahre vor TrilaWatt, für die Wanderung des Japsands (P9): je Jahr ein Ausschnitt der Szene aus dem WCS
        EasyGSH_Bathymetrie auf coast.baw.de (EPSG:25832), dazu die Hüllen min/max 1996–2016. Der Dienst erzeugt jede Datei
        neu, das dauert je 1–2 min. Andere Jahre mit --jahre.""",
        "https://coast.baw.de/easygsh/Easy_DownloadG.html")
def _p(ctx):
    basis = BAW_WCS + "/EasyGSH_Bathymetrie/wcs"
    covs = [(str(j), f"EasyGSH_Bathymetrie__DGM_{j}_10m_DB_Bathymetrie") for j in _jahre(ctx, range(1996, 2015), range(1996, 2017))]
    covs += [("minmax", "EasyGSH_Bathymetrie__easygsh-db_minz_1996-2016"), ("minmax", "EasyGSH_Bathymetrie__easygsh-db_maxz_1996-2016")]
    out = []
    for ordner, cov in covs:
        for box in _gleich(*ctx.gebiet.utm_huelle(), 32000, 10):
            out.append(Datei(_wcs_url(basis, cov, ["E", "N"], box), f"{ordner}/{cov.split('__', 1)[1]}_{int(box[0]) // 1000}_{int(box[1]) // 1000}.tif",
                             dienst=True, art="tiff"))
    return out


# ---- Gezeiten, Stroemung, Pegel ---------------------------------------------
@quelle("eot20", "gezeiten", "EOT20 Gezeitenatlas (17 Partialtiden, Ozean und Auflast)", "DGFI-TUM (SEANOE)",
        "CC BY 4.0 (Hart-Davis u. a. 2021)", "schelf", "standard",
        "Randwerte für G0 (Werkbuch F11): NetCDF 1/8°, weltweit, ein Archiv von rund 2 GB.",
        "https://www.seanoe.org/data/00683/79489/")
def _p(ctx):
    return [Datei("https://www.seanoe.org/data/00683/79489/data/85762.zip", "EOT20.zip", art="zip")]


KENNWERTE = (r"m2_amplitude|m2_phase|high_water_level_50q|low_water_level_50q|tidal_range_(05|50|95)q|mean_tide_level_50q|"
             r"(mean|max)_(flood|ebb)_current_velocity(_50q|_95q)?|mean_inundation_period\w*|"
             r"max_eff_bedshearstress_(flood|ebb)_current_50q|significant_wave_height_(50|95|99)q|hsmean|water_level_(01|99)q")
KENNWERTE_ERSATZ = ("m2_amplitude", "m2_phase", "tidal_range_50q", "mean_tide_level_50q", "high_water_level_50q",
                    "low_water_level_50q", "max_flood_current_velocity_50q", "max_ebb_current_velocity_50q",
                    "mean_flood_current_velocity", "mean_inundation_period_12m", "max_eff_bedshearstress_flood_current_50q",
                    "significant_wave_height_50q", "hsmean")


@quelle("easygsh_kennwerte", "gezeiten", "EasyGSH-DB Kennwerte: M2, Tidehub, Strömung, Überflutungsdauer, Seegang",
        "BAW (EasyGSH-DB, UnTRIM², SWAN)", BAW_LIZENZ, "nordfriesland", "standard",
        """Ergebnisse der BAW-Modelle als Raster 100 m für G2: M2-Amplitude und -Phase, Hoch- und Niedrigwasser, Tidehub,
        Flut- und Ebbströmung, Überflutungsdauer, Sohlschubspannung, Seegang – der Prüfstein für tide und hydro (P5).
        WCS EasyGSH_Kennwerte_<Jahr> auf coast.baw.de, Coverages aus GetCapabilities. Vorgabe 2015, sonst --jahre 1996–2015.""",
        "https://coast.baw.de/easygsh/EasyEN_DownloadH.html")
def _p(ctx):
    muster = re.compile(r"(?:\w+?__)?(\d{4})_100m_(?:" + KENNWERTE + r")")
    out = []
    for j in _jahre(ctx, [2015], range(1996, 2016)):
        basis = f"{BAW_WCS}/EasyGSH_Kennwerte_{j}/wcs"
        try:
            x = hole_text(basis + "?service=WCS&version=2.0.1&request=GetCapabilities", timeout=180, versuche=2)
            covs = sorted({c for c in re.findall(r"<wcs:CoverageId>([^<]+)</wcs:CoverageId>", x) if muster.fullmatch(c) and str(j) in c})
        except Exception:
            covs = []
        covs = covs or [f"{j}_100m_{k}" for k in KENNWERTE_ERSATZ]
        epsg, achsen = _wcs_achsen(basis, covs[0])
        box = _wcs_box(ctx.gebiet, epsg)
        out += [Datei(_wcs_url(basis, c, achsen, box), f"{j}/{c.split('__', 1)[-1]}.tif", dienst=True, art="tiff") for c in covs]
    return out


@quelle("pegelonline", "gezeiten", "PEGELONLINE: Pegel in Nordfriesland und an der Nordsee, letzte 30 Tage", "WSV",
        "DL-DE Zero 2.0", "bucht", "standard",
        """Stammdaten mit Pegelnull und Kennwerten (MThw, MTnw …) und Wasserstand W der letzten 30 Tage. Der Dienst gibt nur
        30 Tage zurück: jeder Lauf legt eine neue Datei mit Datum an, so wächst die Reihe.""",
        "https://www.pegelonline.wsv.de/webservice/ueberblick")
def _p(ctx):
    basis = "https://www.pegelonline.wsv.de/webservices/rest-api/v2"
    heute, out, zeilen = time.strftime("%Y%m%d"), [], []
    nf = GEBIETE["nordfriesland"]
    for st in hole_json(basis + "/stations.json?includeTimeseries=true&includeCharacteristicValues=true"):
        lon, lat = st.get("longitude"), st.get("latitude")
        wasser = (st.get("water") or {}).get("shortname", "")
        if lon is None or lat is None or not (nf.enthaelt(lon, lat) or (ctx.gebiet.enthaelt(lon, lat) and wasser.upper() == "NORDSEE")):
            continue
        reihen = [t.get("shortname") for t in st.get("timeseries", [])]
        name = re.sub(r"[^0-9A-Za-zÄÖÜäöüß_-]+", "_", st.get("shortname") or st["uuid"]).strip("_")
        zeilen.append([name, st.get("number", ""), wasser, f"{lon:.5f}", f"{lat:.5f}", " ".join(r for r in reihen if r), st["uuid"]])
        out.append(Datei(f"{basis}/stations/{st['uuid']}.json?includeTimeseries=true&includeCharacteristicValues=true",
                         f"{name}/station.json", dienst=True, art="json"))
        if "W" in reihen:
            out.append(Datei(f"{basis}/stations/{st['uuid']}/W/measurements.json?start=P30D", f"{name}/W_bis_{heute}_30_tage.json",
                             dienst=True, art="json"))
    ctx.beilagen["pegelonline/pegel.csv"] = _csv(["pegel", "nummer", "gewaesser", "laenge", "breite", "reihen", "uuid"], sorted(zeilen))
    return out


# ---- Sediment ----------------------------------------------------------------
@quelle("easygsh_sediment", "sediment", "EasyGSH-DB Sedimentologie (Vorgabe 2016)", "BAW (EasyGSH-DB)", BAW_LIZENZ,
        "nordfriesland", "standard",
        """Je Jahr ein ZIP der ganzen Deutschen Bucht (100 m): D50, Sortierung, Schiefe, Porosität, Petrographie (Haupt- und
        Nebenkomponente) als Raster, dazu alle Werte als CSV (2016: 1,6 GB). Vorgabe 2016, sonst --jahre 1996,2006,2016.""",
        "https://doi.org/10.48437/02.2020.K2.7000.0002")
def _p(ctx):
    return [Datei(f"{EASYGSH}/Sedimentologie/EasyGSH_DB_Sedimentologie_{j}.zip", f"EasyGSH_DB_Sedimentologie_{j}.zip", art="zip")
            for j in _jahre(ctx, [2016], (1996, 2006, 2016))]


# ---- Wetter -----------------------------------------------------------------
@quelle("era5", "wetter", "ERA5 Dezember 2013 (Sturmflut Xaver): Luftdruck, Wind 10 m, Temperatur 2 m",
        "ECMWF / NSF NCAR (AWS)", "Copernicus-Lizenz (frei, Namensnennung)", "schelf", "gross",
        "Antrieb für den Prüfstein Xaver (F13), stündlich 0,25°, ganze Erde je Datei, zusammen rund 4 GB. Andere Monate: --monate 202310,202311.",
        "https://registry.opendata.aws/nsf-ncar-era5/")
def _p(ctx):
    basis, out = "https://nsf-ncar-era5.s3.amazonaws.com", []
    for m in ctx.opt.get("monate") or ["201312"]:
        for var in ("128_151_msl", "128_165_10u", "128_166_10v", "128_167_2t"):
            out += [Datei(f"{basis}/{k}", f"{m}/{_name(k)}", gr) for k, gr in s3_liste(basis, f"e5.oper.an.sfc/{m}/e5.oper.an.sfc.{var}")[0]]
    return out


# Climate Data Store (Copernicus): Auftrag ueber die Schnittstelle retrieve/v1, wie ecmwf-datastores-client
CDS_SAMMLUNG = "reanalysis-era5-single-levels"
CDS_GROESSEN = ["10m_u_component_of_wind", "10m_v_component_of_wind", "mean_sea_level_pressure"]
CDS_VERZUG = 6                  # Tage: ERA5T liegt etwa fuenf Tage hinter heute


def _cds_zugang():
    """(url, schluessel) aus CDSAPI_URL/CDSAPI_KEY oder der Datei CDSAPI_RC bzw. ~/.cdsapirc. Der Schluessel wird nie ausgegeben."""
    url, key = os.environ.get("CDSAPI_URL"), os.environ.get("CDSAPI_KEY")
    pfad = os.environ.get("CDSAPI_RC") or os.path.join(os.path.expanduser("~"), ".cdsapirc")
    if (not url or not key) and os.path.exists(pfad):
        with open(pfad, encoding="utf-8-sig") as f:
            for z in f:
                if ":" not in z:
                    continue
                k, v = z.split(":", 1)
                if k.strip() == "url" and not url:
                    url = v.strip()
                elif k.strip() == "key" and not key:
                    key = v.strip()
    if not url or not key:
        raise DienstFehler(f"kein Zugang zum Climate Data Store: {pfad} mit den Zeilen 'url:' und 'key:' fehlt "
                           "(https://cds.climate.copernicus.eu/how-to-api)")
    return url.rstrip("/"), key


def _cds_json(url, key, daten=None):
    """GET oder (mit daten) POST als JSON an den Climate Data Store; Fehler als DienstFehler mit dem Text des Dienstes."""
    kopf = {"User-Agent": AGENT, "PRIVATE-TOKEN": key, "Accept": "application/json"}
    rumpf = None
    if daten is not None:
        rumpf = json.dumps(daten).encode("utf-8")
        kopf["Content-Type"] = "application/json"
    warte = 5
    for versuch in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=rumpf, headers=kopf, method="POST" if rumpf else "GET"),
                                        timeout=120) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            try:
                text = e.read().decode("utf-8", "replace")
                j = json.loads(text)
                text = " ".join(str(j.get(k, "")) for k in ("title", "detail") if j.get(k))
            except Exception:
                text = ""
            if e.code in (500, 502, 503, 504) and versuch < 4:
                time.sleep(warte)
                warte *= 2
                continue
            if e.code in (401, 403):
                text += " – Schluessel in .cdsapirc und Lizenz von ERA5 (Seite des Datensatzes, Reiter Download) pruefen"
            raise DienstFehler(f"Climate Data Store HTTP {e.code}: {text[:300]}") from None
        except NETZFEHLER as e:
            if versuch == 4:
                raise
            time.sleep(warte)
            warte *= 2


def cds_laden(sammlung, anfrage, ziel, warte_hoechstens=4 * 3600):
    """Auftrag an den Climate Data Store, warten, Ergebnis nach ziel laden (fortsetzbar). Gibt den Zustand zurueck."""
    url, key = _cds_zugang()
    basis = url + "/retrieve/v1"
    job = _cds_json(f"{basis}/processes/{sammlung}/execution", key, {"inputs": anfrage})
    links = {l.get("rel"): l.get("href") for l in job.get("links", [])}
    auftrag = links.get("monitor") or f"{basis}/jobs/{job['jobID']}"
    name = os.path.basename(ziel)
    print(f"    {name}: Auftrag {job.get('jobID', '?')} im Climate Data Store, Zustand {job.get('status')}")
    t0, warte, zustand = time.time(), 2.0, job.get("status")
    while zustand in ("accepted", "running", "queued", None):
        if time.time() - t0 > warte_hoechstens:
            raise DienstFehler(f"Climate Data Store: Auftrag nach {warte_hoechstens / 3600:.0f} h noch {zustand}; spaeter neu starten")
        time.sleep(warte)
        warte = min(warte * 1.5, 60)
        j = _cds_json(auftrag, key)
        if j.get("status") != zustand:
            print(f"    {name}: {zustand} -> {j.get('status')} nach {time.time() - t0:.0f} s")
        zustand = j.get("status")
    j = _cds_json(auftrag, key)
    links = {l.get("rel"): l.get("href") for l in j.get("links", [])}
    ergebnis = links.get("results") or f"{auftrag}/results"
    if zustand != "successful":
        try:
            r = _cds_json(ergebnis, key)
            text = " ".join(str(r.get(k, "")) for k in ("title", "detail") if r.get(k))
        except DienstFehler as e:
            text = str(e)
        raise DienstFehler(f"Climate Data Store: Auftrag {zustand}: {text[:300]}")
    r = _cds_json(ergebnis, key)
    a = r["asset"]["value"]
    adresse = urllib.parse.urljoin(ergebnis, a["href"])
    return laden(adresse, ziel, int(a["file:size"]) if a.get("file:size") else None)


def _cds_bereich(g, rand=0.5):
    """[Nord, West, Sued, Ost] um das Gebiet, um rand Grad erweitert, auf das Raster von ERA5 (1/4 Grad)."""
    w, s, o, n = g.lonlat
    auf = lambda x: math.ceil(x * 4 - 1e-9) / 4
    ab = lambda x: math.floor(x * 4 + 1e-9) / 4
    return [auf(n + rand), ab(w - rand), ab(s - rand), auf(o + rand)]


def _cds_monate(ctx, groessen, gebiet="schelf"):
    """Je Monat aus --monate (Vorgabe 202610) ein Auftrag fuer die Groessen ueber dem Gebiet (Vorgabe G0), stuendlich, GRIB."""
    out = []
    grenze = time.gmtime(time.time() - CDS_VERZUG * 86400)
    bereich = _cds_bereich(GEBIETE[gebiet])
    for m in ctx.opt.get("monate") or ["202610"]:
        if not re.fullmatch(r"\d{6}", m):
            raise ValueError(f"Monat {m}: JJJJMM erwartet")
        j, mo = int(m[:4]), int(m[4:])
        tage = [31, 29 if (j % 4 == 0 and j % 100 != 0) or j % 400 == 0 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1]
        if (j, mo) > (grenze.tm_year, grenze.tm_mon):
            ctx.hinweis = f"{m} liegt noch nicht im Climate Data Store (etwa {CDS_VERZUG} Tage Verzug)"
            continue
        letzter = tage if (j, mo) < (grenze.tm_year, grenze.tm_mon) else grenze.tm_mday
        pfad = f"{m}.grib" if letzter == tage else f"{m}_bis_{letzter:02d}.grib"
        anfrage = {"product_type": ["reanalysis"], "variable": list(groessen), "year": [f"{j}"], "month": [f"{mo:02d}"],
                   "day": [f"{d:02d}" for d in range(1, letzter + 1)], "time": [f"{h:02d}:00" for h in range(24)],
                   "area": bereich, "data_format": "grib", "download_format": "unarchived"}
        out.append(Datei(f"cds:{CDS_SAMMLUNG}/{m}/1-{letzter}", pfad, None,
                         f"{letzter} Tage, {len(groessen)} Größen, Bereich N {bereich[0]} W {bereich[1]} S {bereich[2]} O {bereich[3]}",
                         art="grib", cds=(CDS_SAMMLUNG, anfrage)))
    return out


@quelle("era5_cds", "wetter", "ERA5 stündlich aus dem Climate Data Store: Wind 10 m und Luftdruck über G0",
        "ECMWF / Copernicus Climate Change Service", "Copernicus-Lizenz (frei, Namensnennung; Konto nötig)", "schelf", "konto",
        """Antrieb für P5 (F28 A): u10, v10, msl stündlich auf 0,25°, ausgeschnitten auf G0 und 0,5° darüber hinaus, GRIB, je
        Monat eine Datei (rund 45 MB). Auch der laufende Monat bis etwa sechs Tage vor heute (ERA5T; die Datei heißt dann
        JJJJMM_bis_TT.grib). Vorgabe --monate 202610 (Sturmflut 25./26.10.2026). Braucht ein Konto und %USERPROFILE%\\.cdsapirc.""",
        "https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels")
def _p(ctx):
    return _cds_monate(ctx, CDS_GROESSEN)


# Schubspannung an der Oberflaeche (Werkbuch 12.6, F34 A): von ECMWF mit dem gekoppelten Seegangsmodell gerechnet.
# iews/inss (Parameter 229/230, N/m², Augenblickswert zur vollen Stunde, positiv nach Osten bzw. Norden auf das Wasser);
# charnock (148) zur Auskunft (F34 B/C).
CDS_SCHUB = ["instantaneous_eastward_turbulent_surface_stress", "instantaneous_northward_turbulent_surface_stress", "charnock"]


@quelle("era5_cds_schub", "wetter", "ERA5 stündlich aus dem Climate Data Store: Schubspannung an der Oberfläche über G0",
        "ECMWF / Copernicus Climate Change Service", "Copernicus-Lizenz (frei, Namensnennung; Konto nötig)", "schelf", "konto",
        """Windschub für P5e (F34 A): iews, inss (instantaneous eastward/northward turbulent surface stress, N/m²) und
        charnock stündlich auf 0,25°, Bereich wie era5_cds, GRIB, je Monat eine Datei (rund 45 MB). Vorgabe --monate 202610.
        Braucht ein Konto und %USERPROFILE%\\.cdsapirc wie era5_cds.""",
        "https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels")
def _p(ctx):
    return _cds_monate(ctx, CDS_SCHUB)


# Seegang (Werkbuch 12.9, P8b, F74 A): Rand von G2w fuer physics.waves und Vergleich im Inneren (Pruefstein 4).
# Gerechnet von ECMWF mit dem gekoppelten Seegangsmodell auf 0,5 Grad; Windsee und Duenung getrennt, dazu die Richtungsbreite.
CDS_SEEGANG = ["significant_height_of_combined_wind_waves_and_swell", "peak_wave_period", "mean_wave_direction", "mean_wave_period",
               "significant_height_of_wind_waves", "mean_period_of_wind_waves", "mean_direction_of_wind_waves",
               "significant_height_of_total_swell", "mean_period_of_total_swell", "mean_direction_of_total_swell",
               "wave_spectral_directional_width_for_wind_waves", "wave_spectral_directional_width_for_swell"]


@quelle("era5_cds_seegang", "wetter", "ERA5 stündlich aus dem Climate Data Store: Seegang über der Deutschen Bucht",
        "ECMWF / Copernicus Climate Change Service", "Copernicus-Lizenz (frei, Namensnennung; Konto nötig)", "bucht", "konto",
        """Rand des Seegangs für P8b (F74 A): Wellenhöhe, Spitzen- und mittlere Periode, Richtung, getrennt nach Windsee und
        Dünung, dazu die Richtungsbreite; stündlich auf dem Raster des Seegangsmodells (0,5°), Bereich G1 und 0,5° darüber
        hinaus, GRIB, je Monat eine Datei. Vorgabe --monate 202610. Braucht ein Konto und %USERPROFILE%\\.cdsapirc wie era5_cds.""",
        "https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels")
def _p(ctx):
    return _cds_monate(ctx, CDS_SEEGANG, "bucht")


# Luft, Strahlung und Wassertemperatur (Werkbuch 12.11, P10b, F90 A): Eingang von physics.atmos. Temperatur und Taupunkt
# in 2 m (K), Temperatur der Meeresoberflaeche (K, ueber Land ohne Wert); Sonnen- und Gegenstrahlung am Boden als Summe der
# Stunde vor der gueltigen Zeit (J/m², nach unten); fuehlbare und latente Waerme ebenso (J/m², nach unten positiv), nur zum
# Vergleich mit atmos; Bewoelkung (0-1) und Niederschlag (m je Stunde) zur Auskunft.
CDS_LUFT = ["2m_temperature", "2m_dewpoint_temperature", "sea_surface_temperature", "surface_solar_radiation_downwards",
            "surface_thermal_radiation_downwards", "surface_sensible_heat_flux", "surface_latent_heat_flux", "total_cloud_cover",
            "total_precipitation"]


@quelle("era5_cds_luft", "wetter", "ERA5 stündlich aus dem Climate Data Store: Temperatur, Feuchte, Strahlung, Wassertemperatur über der Deutschen Bucht",
        "ECMWF / Copernicus Climate Change Service", "Copernicus-Lizenz (frei, Namensnennung; Konto nötig)", "bucht", "konto",
        """Wetter für atmos (P10b, F90 A): Temperatur und Taupunkt in 2 m, Temperatur der Meeresoberfläche, Sonnen- und
        Gegenstrahlung am Boden, fühlbare und latente Wärme (zum Vergleich), Bewölkung und Niederschlag (zur Auskunft);
        stündlich auf 0,25°, Bereich G1 und 0,5° darüber hinaus, GRIB, je Monat eine Datei (wenige MB). Vorgabe --monate 202610.
        Braucht ein Konto und %USERPROFILE%\\.cdsapirc wie era5_cds.""",
        "https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels")
def _p(ctx):
    return _cds_monate(ctx, CDS_LUFT, "bucht")


# Boee in 10 m (Seegang S8b, SF156 A): Staerke der Katzenpfoten. fg10 (Parameter 49, m/s) ist die staerkste Boee der Stunde
# vor der gueltigen Zeit nach dem Nachbearbeiten von ECMWF (WMO: 3-s-Mittel), auf dem Raster des Atmosphaerenmodells.
CDS_BOEE = ["10m_wind_gust_since_previous_post_processing"]


@quelle("era5_cds_boee", "wetter", "ERA5 stündlich aus dem Climate Data Store: Böe in 10 m über der Deutschen Bucht",
        "ECMWF / Copernicus Climate Change Service", "Copernicus-Lizenz (frei, Namensnennung; Konto nötig)", "bucht", "konto",
        """Böe für die Katzenpfoten im Seegang (S8b, SF156 A): fg10 (10 m wind gust since previous post-processing, m/s,
        stärkste Böe der Stunde vor der Zeit) stündlich auf 0,25°, Bereich G1 und 0,5° darüber hinaus, GRIB, je Monat eine
        Datei (unter 1 MB). Vorgabe --monate 202610; für Xaver 201312. Braucht ein Konto und %USERPROFILE%\\.cdsapirc wie era5_cds.""",
        "https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels")
def _p(ctx):
    return _cds_monate(ctx, CDS_BOEE, "bucht")


# Wind an Stationen des DWD (Werkbuch 12.6, F36 A): 10-Minuten-Werte, Ordner "recent" (rund die letzten 500 Tage, taeglich neu)
DWD_WIND = "https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/10_minutes/wind/recent"
DWD_WIND_META = "https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/10_minutes/wind/meta_data"
DWD_WIND_HIST = "https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/10_minutes/wind/historical"
DWD_STATIONEN = {"02115": "Helgoland", "03032": "List auf Sylt"}


@quelle("dwd_wind", "wetter", "Wind an Stationen des DWD: 10-Minuten-Werte, Helgoland und List auf Sylt",
        "Deutscher Wetterdienst, Climate Data Center (opendata.dwd.de)", "CC BY 4.0, „Quelle: Deutscher Wetterdienst“", "bucht", "standard",
        """Prüfung des Winds von ERA5 im Sturm (P5e, F36 A): je Station ein ZIP mit FF_10 und DD_10 (10-Minuten-Mittel, UTC),
        je Station die Metadaten aus meta_data (Lage, Höhe des Gebers) und die Stationsliste. Der Ordner recent reicht rund 500 Tage zurück und
        wird täglich neu geschrieben; ein vorhandenes ZIP wird nicht neu geladen (für einen neuen Stand löschen). Seit P13d (A31) dazu
        je Station das ZIP aus historical für 2010–2019 (Sturmflut Xaver, Dezember 2013).""",
        DWD_WIND + "/")
def _p(ctx):
    out = [Datei(f"{DWD_WIND}/10minutenwerte_wind_{k}_akt.zip", f"10minutenwerte_wind_{k}_akt.zip", None, f"{n} ({k})", art="zip")
           for k, n in DWD_STATIONEN.items()]
    # Die ZIP aus recent tragen nur die Werte; Lage und Hoehe des Gebers stehen in meta_data (gemessen 14.11.2026)
    out += [Datei(f"{DWD_WIND_META}/Meta_Daten_zehn_min_ff_{k}.zip", f"Meta_Daten_zehn_min_ff_{k}.zip", None, f"{n} ({k}), Metadaten", art="zip")
            for k, n in DWD_STATIONEN.items()]
    out.append(Datei(f"{DWD_WIND}/zehn_min_ff_Beschreibung_Stationen.txt", "zehn_min_ff_Beschreibung_Stationen.txt", None, "Stationsliste"))
    # seit P13d (A31, Werkbuch Datei 106): die historischen Werte 2010-2019 fuer Xaver (Dezember 2013); im selben Ordner,
    # damit der Schritt wind der Aufbereitung sie mit den recent-Werten liest (je Station rund 10-20 MB)
    out += [Datei(f"{DWD_WIND_HIST}/10minutenwerte_wind_{k}_20100101_20191231_hist.zip", f"10minutenwerte_wind_{k}_20100101_20191231_hist.zip", None,
                  f"{n} ({k}), historisch 2010-2019", art="zip")
            for k, n in DWD_STATIONEN.items()]
    return out


# ---- Karten -----------------------------------------------------------------
@quelle("dtk25", "karten", "DTK25 Schleswig-Holstein (farbig), Szene", "LVermGeo SH (WMS OpenGBD)", SH_LIZENZ, "szene", "standard",
        "Topographische Karte 1:25 000 mit Prielen und Wattrinnen, PNG-Kacheln 2,5 m mit Weltdatei (Ebene sh_dtk25_col).",
        SH_WMS + "/WMS_SH_DTK25_OpenGBD?service=wms&version=1.3.0&request=getCapabilities")
def _p(ctx):
    return _wms(ctx, "dtk25", SH_WMS + "/WMS_SH_DTK25_OpenGBD", "sh_dtk25_col", 2.5, "image/png", "png")


DTK5_CLIENT = SH_CLIENT + "dl-dtk5.html"


def _dtk5_blaetter(g):
    """DTK5-Blaetter 2 x 2 km (Suedwestecke auf geraden km) im Gebiet: [(blatt_id, stamm, ost_km, nord_km)]."""
    e0, n0, e1, n1 = g.utm_huelle()
    out = []
    for n in range(n0 // 2000 * 2, -(-n1 // 2000) * 2, 2):
        for e in range(e0 // 2000 * 2, -(-e1 // 2000) * 2, 2):
            out.append((f"32{e}{n}", f"dtk5_32{e}_{n}_2_sh", e, n))
    return out


def _dtk5_pruefung(ordner, g):
    da = set()
    for _, _, dateien in os.walk(ordner):
        for f in dateien:
            m = re.match(r"dtk5_32(\d{3})_(\d{4})_2_sh", f)
            if m:
                da.add((int(m.group(1)), int(m.group(2))))
    bl = _dtk5_blaetter(g)
    fehlen = [b for b, _, e, n in bl if (e, n) not in da]
    return (f"{len(bl) - len(fehlen)} von {len(bl)} möglichen Blättern im Gebiet {g.name} vorhanden (über offenem Wasser "
            f"gibt es keine). Fehlende Blattnummern für den Downloadclient: {' '.join(fehlen) if fehlen else '–'}")


@quelle("dtk5", "karten", "DTK5 Schleswig-Holstein, Originalblätter 2 × 2 km (von Hand)", "LVermGeo SH", SH_LIZENZ, "kern", "standard",
        """Blätter 2 × 2 km zu 0,25 m (8000 × 8000) mit Weltdatei: Gesamtbild farbig (_col), einfarbig (_ein), grau (_g) und je
        Thema eine Folie (_watt, _wies, _sebl, _baum, _babl …). Der Downloadclient hat keinen Massendownload: Blätter dort
        anklicken (Mehrfachdownload), die ZIPs ins Zielverzeichnis legen, dann 'einsortieren'. Blattnummer
        32<Ost km><Nord km> der Südwestecke, z. B. 324706048. Die Liste schreibt 'plan' nach karten/dtk5/.""",
        DTK5_CLIENT)
def _p(ctx):
    for g in (GEBIETE["kern"], GEBIETE["szene"]):
        ctx.beilagen[f"dtk5/blaetter_{g.name}.csv"] = _csv(["blatt", "dateistamm", "ost_km", "nord_km"], _dtk5_blaetter(g))
    ctx.hinweis = (f"DTK5 von Hand über den Downloadclient ({DTK5_CLIENT}), Mehrfachdownload; Blattlisten in karten/dtk5/, "
                   "danach 'einsortieren'.")
    return []


QUELLEN["dtk5"].pruefung = _dtk5_pruefung


@quelle("dtk5_wms", "karten", "DTK5 aus dem WMS (Ersatz, 0,5 m)", "LVermGeo SH (WMS OpenGBD)", SH_LIZENZ, "kern", "gross",
        """Falls Blätter fehlen: Gesamtbild aus dem WMS in Bildern 1 × 1 km zu 0,5 m mit Weltdatei (der Dienst setzt je Bild
        höchstens 500 eigene Kacheln zusammen).""",
        SH_WMS + "/WMS_SH_DTK5_OpenGBD?service=wms&version=1.3.0&request=getCapabilities")
def _p(ctx):
    basis = SH_WMS + "/WMS_SH_DTK5_OpenGBD"
    return _wms(ctx, "dtk5_wms", basis, _wms_ebene(basis, "dtk5"), 0.5, "image/png", "png", max_px=2000)


# ---- Luftbild ---------------------------------------------------------------
@quelle("dop20", "luftbild", "DOP20 Schleswig-Holstein (RGB + Infrarot, 20 cm)", "LVermGeo SH", SH_LIZENZ, "kern", "standard",
        """Originalkacheln 1 × 1 km (GeoTIFF, vier Kanäle) aus dem Index des Massendownloads
        (index/DOP20_SH__Massendownload.geojson). Nur über Land: Kern 22 Kacheln (Hooge), Szene 139 (--gebiet szene,
        mit Norderoog, Süderoog, Amrum-Süd, Pellworm-West). Watt und Sände zeigt Sentinel-2.""",
        SH_CLIENT + "dl-dop20.html")
def _p(ctx):
    pfad, ks = _massen_kacheln("DOP20_SH__Massendownload*.geojson", DOP20_RE, ctx.gebiet)
    ctx.beilagen[f"dop20/kacheln_{ctx.gebiet.name}.csv"] = _csv(["datei", "ost_km", "nord_km", "befliegung"], [k[:4] for k in ks])
    return [Datei(url, datei, dienst=True, art="tiff", notiz=f"Befliegung {datum}") for datei, e, n, datum, url in ks]


QUELLEN["dop20"].pruefung = _kachel_pruefung("DOP20_SH__Massendownload*.geojson", DOP20_RE, r"dop20rgbi_32_(\d{3})_(\d{4})")


# ---- Oberflaeche (P12c, F136 A) ------------------------------------------------
@quelle("bdom", "hoehe", "bDOM Schleswig-Holstein (bildbasiertes Oberflächenmodell, 20 cm)", "LVermGeo SH", SH_LIZENZ, "kern", "standard",
        """Oberfläche mit Gebäuden und Vegetation, Gitter 20 cm, Höhe ±0,5 m (GeoTIFF, EPSG:25832, DHHN2016), Kacheln
        1 × 1 km aus dem Index des Massendownloads (index/bDOM_SH_Massendownload.geojson). Für die Gehölze an den Warften
        (Schritt gehoelz: bDOM − DGM1). Kern: die Kacheln über Hooge (Befliegung Mai 2024).""",
        SH_CLIENT + "dl-bdom.html")
def _p(ctx):
    pfad, ks = _massen_kacheln("bDOM_SH_Massendownload*.geojson", BDOM_RE, ctx.gebiet)
    ctx.beilagen[f"bdom/kacheln_{ctx.gebiet.name}.csv"] = _csv(["datei", "ost_km", "nord_km", "befliegung"], [k[:4] for k in ks])
    return [Datei(url, datei, dienst=True, art="tiff", notiz=f"Befliegung {datum}") for datei, e, n, datum, url in ks]


QUELLEN["bdom"].pruefung = _kachel_pruefung("bDOM_SH_Massendownload*.geojson", BDOM_RE, r"bdom20\w*_32_(\d{3})_(\d{4})")


# ---- Gebaeude (P12a, F125 A) -------------------------------------------------
LOD2_INDEX = "LOD2_SH_Massendownload.geojson"
LOD2_INDEX_URL = SH_CLIENT + "single.php?file=" + LOD2_INDEX + "&id=4"


def _bbox(geom):
    """Huelle (x0, y0, x1, y1) einer GeoJSON-Geometrie (beliebig tief verschachtelte Koordinaten)."""
    xs, ys = [], []

    def lauf(c):
        if c and isinstance(c[0], (int, float)):
            xs.append(c[0])
            ys.append(c[1])
        else:
            for t in c:
                lauf(t)
    lauf(geom["coordinates"])
    return min(xs), min(ys), max(xs), max(ys)


def _lod2_index():
    """Index des Massendownloads LoD2: liegt er nicht in index/, wird er vom Downloadportal geholt (single.php)."""
    pfad = os.path.join(INDEX_ORDNER, LOD2_INDEX)
    if not os.path.exists(pfad):
        os.makedirs(INDEX_ORDNER, exist_ok=True)
        daten = hole(LOD2_INDEX_URL, timeout=300)
        if not daten.lstrip().startswith(b"{"):
            raise ValueError(f"{LOD2_INDEX_URL} lieferte kein GeoJSON ({daten[:80]!r}) – im Downloadclient "
                             f"{SH_CLIENT}dl-lod2.html unter Massendownload als GeoJSON speichern und nach {INDEX_ORDNER} legen")
        with open(pfad, "wb") as f:
            f.write(daten)
    with open(pfad, encoding="utf-8") as f:
        return pfad, json.load(f)


def _lod2_kacheln(g):
    """Kacheln des LoD2-Index, deren Fläche das Gebiet schneidet: [(datei, x0, y0, datum, adresse)].
    Lage aus der Geometrie (EPSG:25832, Name des Dateimusters unbekannt), Dateiname aus 'file=' der Adresse."""
    pfad, fc = _lod2_index()
    e0, n0, e1, n1 = g.utm_huelle()
    out = []
    for ft in fc["features"]:
        p = ft.get("properties", {})
        url = p.get("data_link") or p.get("link_data") or p.get("link") or ""      # LoD2: data_link, DGM1/DOP20: link_data
        if not url or not ft.get("geometry"):
            continue
        x0, y0, x1, y1 = _bbox(ft["geometry"])
        if x1 <= e0 or x0 >= e1 or y1 <= n0 or y0 >= n1:
            continue
        m = re.search(r"file=([^&]+)", url)
        datei = urllib.parse.unquote(m.group(1)) if m else _name(url)
        out.append((os.path.basename(datei), int(x0), int(y0), p.get("datum", ""), url))
    return pfad, sorted(out, key=lambda t: (t[1], t[2]))


@quelle("lod2", "gebaeude", "3D-Gebäudemodell LoD2 Schleswig-Holstein (CityGML)", "LVermGeo SH", SH_LIZENZ, "kern", "standard",
        """Amtliche Gebäude aus dem ALKIS-Grundriss mit Dachform und Höhen (CityGML, EPSG:25832, Höhen NHN), Kacheln aus
        dem Index des Massendownloads (LOD2_SH_Massendownload.geojson; fehlt er in index/, holt ihn das Werkzeug vom
        Downloadportal). Kern: Hooge und Japsand. Gelesen von der Aufbereitung, Schritt 'gebaeude' (P12a).""",
        SH_CLIENT + "dl-lod2.html")
def _p(ctx):
    pfad, ks = _lod2_kacheln(ctx.gebiet)
    ctx.beilagen[f"lod2/kacheln_{ctx.gebiet.name}.csv"] = _csv(["datei", "ost", "nord", "stand"], [k[:4] for k in ks])
    ctx.beilagen["lod2/LIESMICH.txt"] = (
        f"3D-Gebäudemodell LoD2 Schleswig-Holstein, CityGML, EPSG:25832, Höhen NHN. Index: {os.path.basename(pfad)}\n"
        f"Gebiet {ctx.gebiet.name}: {len(ks)} Kacheln.\nLizenz: {SH_LIZENZ}\n")
    return [Datei(url, datei, dienst=True, notiz=f"Stand {datum}",
                  art="zip" if datei.lower().endswith(".zip") else "citygml" if datei.lower().endswith((".gml", ".xml")) else None)
            for datei, e, n, datum, url in ks]


def _lod2_pruefung(ordner, g):
    _, ks = _lod2_kacheln(g)
    da = {f for _, _, fs in os.walk(ordner) for f in fs if not f.endswith(".part")}
    fehlen = [d for d, *_ in ks if d not in da]
    return (f"{len(ks) - len(fehlen)} von {len(ks)} Kacheln im Gebiet {g.name} vorhanden."
            + (f" Es fehlen: {', '.join(fehlen[:12])}" + (" …" if len(fehlen) > 12 else "") if fehlen else ""))


QUELLEN["lod2"].pruefung = _lod2_pruefung


@quelle("sentinel2", "luftbild", "Sentinel-2 L2A, klarste Szenen April–September (10 m)", "ESA Copernicus / Element 84",
        "Copernicus Sentinel Data (frei, Namensnennung)", "szene", "standard",
        """Je Kachel über der Szene (32UMF) die klarsten Szenen: Echtfarbe TCI, Szenenklassen SCL, Vorschau, JSON; mit
        --gross auch Rot (B04) und Nahinfrarot (B08), mit --baender weitere (B02,B03,B04 für die Eichung der Albedo,
        Werkbuch 12.7, F44). Anzahl: --szenen (Vorgabe 3). Alle Szenen in szenen.csv.""",
        "https://registry.opendata.aws/sentinel-2-l2a-cogs/")
def _p(ctx):
    basis = "https://sentinel-cogs.s3.us-west-2.amazonaws.com"
    kacheln = {mgrs_kachel(lon, lat) for lon, lat in ctx.gebiet.rand_grad(10)}
    kandidaten = []
    for k in sorted(kacheln):
        z, b, q = k[:2].lstrip("0"), k[2], k[3:]
        for j in range(2017, int(time.strftime("%Y")) + 1):
            for m in range(4, 10):
                kandidaten += s3_liste(basis, f"sentinel-s2-l2a-cogs/{z}/{b}/{q}/{j}/{m}/", "/")[1]

    def lies(o):
        name = o.rstrip("/").rsplit("/", 1)[-1]
        try:
            p = hole_json(s3_url(basis, o + name + ".json"))["properties"]
            return o, name, p.get("eo:cloud_cover", 100), p.get("s2:nodata_pixel_percentage", 100), p.get("datetime", "")
        except Exception:
            return None

    with cf.ThreadPoolExecutor(16) as ex:
        szenen = [s for s in ex.map(lies, kandidaten) if s]
    ctx.beilagen["sentinel2/szenen.csv"] = _csv(["szene", "zeit", "wolken_prozent", "ohne_daten_prozent"],
                                                sorted(([s[1], s[4], s[2], s[3]] for s in szenen), key=lambda z: z[1]))
    baender = ["TCI.tif", "SCL.tif", "thumbnail.jpg"] + (["B04.tif", "B08.tif"] if ctx.opt.get("gross") else [])
    baender += [b.strip() + ".tif" for b in (ctx.opt.get("baender") or "").split(",") if b.strip() and b.strip() + ".tif" not in baender]
    out = []
    for k in sorted(kacheln):
        eigene = sorted((s for s in szenen if f"_{k.lstrip('0')}_" in s[1] and s[3] < 5), key=lambda s: s[2])
        for o, name, wolken, _, zeit in eigene[:int(ctx.opt.get("szenen", 3))]:
            vorhanden = dict(s3_liste(basis, o, "/")[0])
            out += [Datei(s3_url(basis, o + f), f"{name}/{f}", vorhanden[o + f], notiz=f"{zeit[:10]}, Wolken {wolken:.1f} %")
                    for f in baender + [name + ".json"] if o + f in vorhanden]
    return out


# ---- Vektor -----------------------------------------------------------------
def _overpass(abfrage):
    return "https://overpass-api.de/api/interpreter?data=" + urllib.parse.quote(" ".join(abfrage.split()))


def _bb(g):
    w, s, o, n = g.lonlat
    return f"({s:.4f},{w:.4f},{n:.4f},{o:.4f})"


@quelle("osm_szene", "vektor", "OpenStreetMap: alle Objekte der Szene", "OpenStreetMap-Mitwirkende", "ODbL 1.0", "szene", "standard",
        "Warften, Häuser, Kirche, Sommerdeich, Gräben, Priele, Fethinge, Anleger, Wege, Namen als JSON mit Geometrie (Overpass).",
        "https://www.openstreetmap.org/")
def _p(ctx):
    return [Datei(_overpass(f"[out:json][timeout:600];nwr{_bb(ctx.gebiet)};out body geom;"), "osm_szene.json", dienst=True, art="json")]


@quelle("osm_kueste", "vektor", "OpenStreetMap: Küste, Deiche, Gewässer, Watt, Häfen in Nordfriesland", "OpenStreetMap-Mitwirkende",
        "ODbL 1.0", "nordfriesland", "standard",
        "Küstenlinie, Deiche und Lahnungen, Gewässer, Watt, Sand, Salzwiesen, Häfen, Seezeichen, Ortsnamen (Overpass).",
        "https://www.openstreetmap.org/")
def _p(ctx):
    bb = _bb(ctx.gebiet)
    teile = ["way[natural=coastline]", 'nwr[man_made~"^(dyke|groyne|breakwater|pier)$"]', "nwr[embankment=yes]", "nwr[waterway]",
             'nwr[natural~"^(water|wetland|sand|beach|mud|shoal|bay|strait)$"]', "nwr[place]", "nwr[harbour]",
             "nwr[leisure=marina]", 'nwr["seamark:type"]']
    q = "[out:json][timeout:900];(" + "".join(t + bb + ";" for t in teile) + ");out body geom;"
    return [Datei(_overpass(q), "osm_kueste.json", dienst=True, art="json")]


@quelle("osm_pbf", "vektor", "OpenStreetMap: Schleswig-Holstein als PBF", "Geofabrik / OSM", "ODbL 1.0", "bucht", "gross",
        "Ganzer Landesauszug für eigene Auswertungen.", "https://download.geofabrik.de/europe/germany/schleswig-holstein.html")
def _p(ctx):
    return [Datei("https://download.geofabrik.de/europe/germany/schleswig-holstein-latest.osm.pbf", "schleswig-holstein-latest.osm.pbf")]


@quelle("natural_earth", "vektor", "Natural Earth 10 m (Küste, Land, Inseln, Staaten, Orte)", "Natural Earth", "gemeinfrei",
        "schelf", "standard", "Grobe Übersicht und Kartenrahmen für G0 und G1.", "https://www.naturalearthdata.com/")
def _p(ctx):
    basis, out = "https://naturalearth.s3.amazonaws.com", []
    for o in ("10m_physical/ne_10m_coastline.zip", "10m_physical/ne_10m_land.zip", "10m_physical/ne_10m_minor_islands.zip",
              "10m_cultural/ne_10m_admin_0_countries.zip", "10m_cultural/ne_10m_populated_places.zip"):
        d = dict(s3_liste(basis, o)[0])
        if o in d:
            out.append(Datei(s3_url(basis, o), _name(o), d[o]))
    return out


# ---- Verzeichnisse ----------------------------------------------------------
@quelle("baw_verzeichnis", "verzeichnis", "Verzeichnisse von TrilaWatt und EasyGSH im BAW-Datenrepository", "BAW",
        BAW_LIZENZ, "nordfriesland", "standard",
        """Schreibt die Dateilisten der Repository-Ordner (TrilaWatt: Topographie, Hydrodynamik, Kennwerte, Sediment;
        EasyGSH) als Text, damit weitere Produkte gezielt gewählt werden können. Lädt selbst nichts.""",
        "https://datenrepository.baw.de/")
def _p(ctx):
    for name, url in (("trilawatt", TRILAWATT + "/"), ("easygsh", EASYGSH + "/")):
        try:
            ctx.beilagen[f"baw_verzeichnis/{name}.txt"] = "\n".join(verzeichnis(url, 3)) + "\n"
        except Exception as e:
            ctx.beilagen[f"baw_verzeichnis/{name}.txt"] = f"{url}: nicht lesbar ({type(e).__name__}: {e})\n"
    return []


# ===========================================================================
# 6  DGM1: XYZ -> GeoTIFF
# ===========================================================================
def xyz_zu_tif(quelle, ziel, e_km, n_km):
    """Kachel (XYZ oder ZIP mit XYZ) -> GeoTIFF float32 1000 x 1000, EPSG:25832, NaN ohne Wert.
    Der Versatz der Punkte zum vollen Meter wird aus dem ersten Punkt gelesen; jede Zelle hat ihren Punkt in der Mitte."""
    with open(quelle, "rb") as f:
        zip_ = f.read(2) == b"PK"
    if zip_:
        z = zipfile.ZipFile(quelle)
        namen = [n for n in z.namelist() if n.lower().endswith((".xyz", ".txt", ".asc", ".csv"))]
        if not namen:
            raise ValueError("kein XYZ im ZIP")
        strom = io.TextIOWrapper(z.open(namen[0]), encoding="ascii", errors="replace")
    else:
        strom = open(quelle, encoding="ascii", errors="replace")
    e0, n0, nan = e_km * 1000.0, n_km * 1000.0, float("nan")
    werte = array.array("f", [nan]) * 1_000_000
    punkte = ausserhalb = doppelt = 0
    fx = fy = None
    zmin, zmax = math.inf, -math.inf
    with strom:
        for zeile in strom:
            t = zeile.replace(",", " ").replace(";", " ").split()
            try:
                x, y, zw = float(t[0]), float(t[1]), float(t[2])
            except (ValueError, IndexError):
                continue
            punkte += 1
            if fx is None:
                fx, fy = x - math.floor(x), y - math.floor(y)
            c, j = int(math.floor(x - e0 - fx + 0.5)), int(math.floor(y - n0 - fy + 0.5))
            if not (0 <= c < 1000 and 0 <= j < 1000):
                ausserhalb += 1
                continue
            i = (999 - j) * 1000 + c
            if werte[i] == werte[i]:
                doppelt += 1
            werte[i] = zw
            zmin, zmax = min(zmin, zw), max(zmax, zw)
    if not punkte or punkte == ausserhalb:
        raise ValueError(f"keine Punkte in der Kachel {e_km}_{n_km} ({punkte} gelesen, {ausserhalb} außerhalb)")
    zeilen = [werte[r * 1000:(r + 1) * 1000].tolist() for r in range(1000)]
    os.makedirs(os.path.dirname(ziel), exist_ok=True)
    tiff_schreiben(ziel + ".part", zeilen, (e0 + fx - 0.5, n0 + fy + 999.5), (1.0, 1.0), 25832, nan, "f")
    os.replace(ziel + ".part", ziel)
    return {"punkte": punkte, "ausserhalb": ausserhalb, "doppelt": doppelt, "leer": sum(1 for v in werte if v != v),
            "zmin": round(zmin, 3), "zmax": round(zmax, 3), "versatz": f"{fx:.2f} {fy:.2f}"}


def _umwandeln(aufgabe):
    quelle, ziel, e, n, loeschen = aufgabe
    try:
        r = xyz_zu_tif(quelle, ziel, e, n)
        if loeschen and not r["ausserhalb"] and not r["doppelt"]:
            os.remove(quelle)
            r["geloescht"] = "ja"
        return os.path.basename(quelle), r
    except Exception as ex:
        return os.path.basename(quelle), f"{type(ex).__name__}: {ex}"


# ===========================================================================
# 7  BEFEHLE
# ===========================================================================
def mb(n):
    if n is None:
        return "?"
    return f"{n / 1e9:.2f} GB" if n >= 1e9 else (f"{n / 1e3:.0f} kB" if n < 1e6 else f"{n / 1e6:.1f} MB")


def _auswahl(args):
    if args.quellen:
        namen = [x.strip() for x in args.quellen.split(",") if x.strip()]
        unbekannt = [n for n in namen if n not in QUELLEN]
        if unbekannt:
            sys.exit("Unbekannte Quelle(n): " + ", ".join(unbekannt) + " (siehe: liste)")
        return [QUELLEN[n] for n in namen]
    stufen = {"standard"} | ({"gross"} if args.gross else set())
    gruppen = set(args.gruppe.split(",")) if args.gruppe else set(GRUPPEN)
    return [q for q in QUELLEN.values() if q.stufe in stufen and q.gruppe in gruppen]


def _ordner(ziel, q):
    return os.path.join(ziel, q.gruppe, q.id)


def cmd_liste(args):
    for gr, titel in GRUPPEN.items():
        qs = [q for q in QUELLEN.values() if q.gruppe == gr]
        if qs:
            print(f"\n{titel}")
            for q in qs:
                print(f"  {q.id:22s} {q.stufe:8s} {q.gebiet:13s} {q.titel}")
    print(f"\n{len(QUELLEN)} Quellen. Stufen: standard (laden), gross (laden --gross).")
    print("Gebiete: " + ", ".join(f"{g.name} ({g.kuerzel})" for g in GEBIETE.values()))


def cmd_plan(args, laden=False):
    ziel = os.path.abspath(args.ziel)
    os.makedirs(os.path.join(ziel, "_status"), exist_ok=True)
    opt = {"gross": args.gross, "szenen": args.szenen, "jahre": args.jahre, "baender": args.baender,
           "monate": [m.strip() for m in args.monate.split(",")] if args.monate else None}
    gesamt, fehler, hinweise = 0, 0, []
    for q in _auswahl(args):
        g = GEBIETE[args.gebiet or q.gebiet]
        ctx = Ctx(g, dict(opt))
        t0 = time.time()
        try:
            dateien = q.plan(ctx)
        except Exception as e:
            print(f"! {q.id}: Planung fehlgeschlagen: {type(e).__name__}: {e}")
            _status(ziel, q, g, [], [("Planung", f"{type(e).__name__}: {e}")], True, None)
            fehler += 1
            continue
        summe = sum(d.groesse or 0 for d in dateien)
        gesamt += summe
        ohne = sum(1 for d in dateien if d.groesse is None)
        print(f"{q.id:22s} {g.name:13s} {len(dateien):5d} Dateien {mb(summe):>10s}"
              + (f" (+{ohne} ohne Größe)" if ohne else "") + f"  [{time.time() - t0:.0f} s]")
        if ctx.hinweis:
            print(f"  Hinweis: {ctx.hinweis}")
            hinweise.append((q.id, ctx.hinweis))
        for pfad, text in ctx.beilagen.items():
            p = os.path.join(ziel, q.gruppe, *pfad.split("/"))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8", newline="") as f:
                f.write(text)
        beilagen = [Datei("beilage:" + p, p.split("/", 1)[1], len(t.encode("utf-8")), "vom Werkzeug erzeugt")
                    for p, t in ctx.beilagen.items()]
        if not laden or (args.max_gb and summe > args.max_gb * 1e9):
            if laden:
                print(f"  übersprungen: {mb(summe)} > --max-gb {args.max_gb}")
            _status(ziel, q, g, dateien + beilagen, [], True, ctx.hinweis)
            continue
        f_q = _lade_alle(_ordner(ziel, q), dateien, args.parallel)
        fehler += len(f_q)
        _status(ziel, q, g, dateien + beilagen, f_q, False, ctx.hinweis)
    print(f"\nSumme der bekannten Größen: {mb(gesamt)}")
    if laden:
        cmd_inventar(args)
    for qid, h in hinweise:
        print(f"Hinweis {qid}: {h}")
    if fehler:
        print(f"{fehler} Fehler, siehe {os.path.join(ziel, 'INVENTAR.md')}")


def _lade_eine(o, d):
    p = os.path.join(o, *d.pfad.split("/"))
    if any(os.path.exists(os.path.join(o, *e.split("/"))) for e in d.ersatz):
        return "vorhanden"
    if d.cds:
        if os.path.exists(p):
            return "vorhanden"
        r = cds_laden(d.cds[0], d.cds[1], p)
        pruefe_art(p, d.art)
        return r
    if d.ausschnitt:
        if os.path.exists(p):
            return "vorhanden"
        t = GeoTiff(d.url, d.stufe)
        zeilen, ursprung, pixel = t.ausschnitt(*d.ausschnitt)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tiff_schreiben(p + ".part", zeilen, ursprung, pixel, t.epsg or 4326, t.nodata,
                       "h" if (t.format == 2 and t.bits == 16) else "f")
        t.schliessen()
        os.replace(p + ".part", p)
        return "ausgeschnitten"
    if d.dienst:
        return laden_dienst(d.url, p, d.art)
    r = laden(d.url, p, d.groesse)
    if r == "geladen":
        pruefe_art(p, d.art)
    return r


def _lade_alle(o, dateien, parallel):
    fehler, fertig = [], 0
    with cf.ThreadPoolExecutor(max(1, parallel)) as ex:
        zukunft = {ex.submit(_lade_eine, o, d): d for d in dateien}
        for z in cf.as_completed(zukunft):
            d = zukunft[z]
            fertig += 1
            try:
                r = z.result()
                if r != "vorhanden":
                    print(f"  [{fertig}/{len(dateien)}] {r:14s} {d.pfad}  {mb(d.groesse) if d.groesse else d.notiz}")
            except Exception as e:
                fehler.append((d.url, f"{type(e).__name__}: {e}"))
                print(f"  [{fertig}/{len(dateien)}] FEHLER         {d.pfad}: {str(e)[:200]}")
    return fehler


def _status(ziel, q, g, dateien, fehler, nur_plan, hinweis):
    with open(os.path.join(ziel, "_status", q.id + ".json"), "w", encoding="utf-8") as f:
        json.dump({"quelle": q.id, "gebiet": g.name, "zeit": time.strftime("%Y-%m-%d %H:%M"), "nur_plan": nur_plan,
                   "hinweis": hinweis, "fehler": [list(x) for x in fehler],
                   "dateien": [{"url": d.url, "pfad": d.pfad, "groesse": d.groesse, "notiz": d.notiz} for d in dateien]},
                  f, ensure_ascii=False, indent=1)


def cmd_inventar(args):
    ziel = os.path.abspath(args.ziel)
    zeilen, abschnitte, fehler_alle, von_hand, summe_alle = [], [], [], [], 0
    for gr, titel in GRUPPEN.items():
        teil = []
        for q in (q for q in QUELLEN.values() if q.gruppe == gr):
            o = _ordner(ziel, q)
            sp = os.path.join(ziel, "_status", q.id + ".json")
            st = json.load(open(sp, encoding="utf-8")) if os.path.exists(sp) else None
            da, summe = 0, 0
            for wurzel, _, dateien in os.walk(o):
                for f in dateien:
                    if not f.endswith(".part"):
                        p = os.path.join(wurzel, f)
                        da += 1
                        summe += os.path.getsize(p)
                        zeilen.append([q.gruppe, q.id, os.path.relpath(p, ziel).replace(os.sep, "/"), os.path.getsize(p)])
            summe_alle += summe
            geplant = len(st["dateien"]) if st else 0
            pfade = {d["url"]: d["pfad"] for d in st["dateien"]} if st else {}
            fehler = [f for f in (st["fehler"] if st else [])
                      if not (f[0] in pfade and os.path.exists(os.path.join(o, *pfade[f[0]].split("/"))))]
            fehler_alle += [(q.id, *f) for f in fehler]
            if not st:
                zustand = "nicht geplant"
            elif st["nur_plan"] and not da:
                zustand = "geplant"
            elif fehler:
                zustand = "fehlgeschlagen" if not da else "teilweise"
            else:
                zustand = "vollständig" if da >= geplant else "teilweise"
            if st and st.get("hinweis"):
                von_hand.append((q.id, st["hinweis"]))
            if q.pruefung and st:
                try:
                    von_hand.append((q.id, q.pruefung(o, GEBIETE[st["gebiet"]])))
                except Exception as e:
                    von_hand.append((q.id, f"Prüfung nicht möglich: {e}"))
            teil.append(f"| `{q.id}` | {q.titel} | {q.stufe} | {st['gebiet'] if st else q.gebiet} | {da}/{geplant} | "
                        f"{mb(summe)} | {zustand} |")
        if teil:
            abschnitte.append(f"\n### {titel}\n\n| Quelle | Titel | Stufe | Gebiet | Dateien | geladen | Zustand |\n"
                              "|---|---|---|---|---|---|---|\n" + "\n".join(teil))
    os.makedirs(ziel, exist_ok=True)
    with open(os.path.join(ziel, "inventar.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["gruppe", "quelle", "datei", "bytes"])
        w.writerows(sorted(zeilen))
    md = ["# Kartenmaterial HalligHooge – Inventar\n",
          f"Stand {time.strftime('%d.%m.%Y %H:%M')}, Ordner `{ziel}`. **{len(zeilen)} Dateien, {mb(summe_alle)}.** "
          "Jede Datei in `inventar.csv`, Adressen und Fehler in `_status/<quelle>.json`.\n",
          "## Gebiete\n\nUTM 32 = ETRS89 / UTM 32N (EPSG:25832), Höhen NHN.\n",
          "| Gebiet | Gitter | Grad (W, S, O, N) | UTM 32 (m) | Fläche | Zweck |", "|---|---|---|---|---|---|"]
    for g in GEBIETE.values():
        w_, s_, o_, n_ = g.lonlat
        utm = f"O {g.utm[0]}–{g.utm[2]}, N {g.utm[1]}–{g.utm[3]}" if g.utm else "–"
        md.append(f"| {g.name} | {g.kuerzel} | {w_:.4f}, {s_:.4f}, {o_:.4f}, {n_:.4f} | {utm} | {g.flaeche_km2():,.0f} km² | {g.zweck} |")
    md += ["\n## Quellen"] + abschnitte
    if von_hand:
        md += ["\n## Hinweise\n"] + [f"- `{qid}`: {t}" for qid, t in von_hand]
    if fehler_alle:
        md += ["\n## Fehlgeschlagen\n\n| Quelle | Adresse | Fehler |\n|---|---|---|"]
        md += [f"| `{qid}` | {url[:200]} | {str(e)[:200]} |" for qid, url, e in fehler_alle]
    with open(os.path.join(ziel, "INVENTAR.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
    print(f"Inventar: {len(zeilen)} Dateien, {mb(summe_alle)} -> {os.path.join(ziel, 'INVENTAR.md')}")


EINSORTIEREN = (
    # (Muster des Dateinamens, Zielordner relativ zum Ziel; {jahr} aus dem Namen)
    (r"^topography_(?P<jahr>\d{4})_ger(_update)?\.zip$", "bathymetrie/trilawatt_topographie/{jahr}"),
    (r"^EasyGSH_DB_Sedimentologie_(?P<jahr>\d{4})\.zip$", "sediment/easygsh_sediment"),
    (r"^EasyGSH_DB_Bathymetrie_(?P<jahr>\d{4})\.zip$", "bathymetrie/easygsh_bathymetrie/zip"),
    (r"^dgm1_32_\d{3}_\d{4}_1_sh(_\d{4})?\.(xyz|zip)$", "hoehe/dgm1"),
    (r"^dop20rgbi_32_\d{3}_\d{4}_1_sh_\d{4}(_bw)?\.tif$", "luftbild/dop20"),
)


def cmd_einsortieren(args):
    """Ordnet Handdownloads im Zielverzeichnis (oberste Ebene) ein: DTK5-Mehrfachdownloads werden nach
    karten/dtk5/kacheln/ entpackt (die ZIPs nach karten/dtk5/mehrfachdownload/), bekannte Dateien wandern in den
    Ordner ihrer Quelle. Danach das Inventar."""
    ziel = os.path.abspath(args.ziel)
    n = 0
    for f in sorted(os.listdir(ziel)):
        p = os.path.join(ziel, f)
        if not os.path.isfile(p) or f.endswith(".part"):
            continue
        if f.lower().endswith(".zip"):
            try:
                with zipfile.ZipFile(p) as z:
                    namen = [x for x in z.namelist() if re.match(r"dtk5_32\d{3}_\d{4}_2_sh", os.path.basename(x))]
                    if namen:
                        k = os.path.join(ziel, "karten", "dtk5", "kacheln")
                        os.makedirs(k, exist_ok=True)
                        for x in namen:
                            with z.open(x) as q, open(os.path.join(k, os.path.basename(x)), "wb") as d:
                                while True:
                                    b = q.read(1 << 20)
                                    if not b:
                                        break
                                    d.write(b)
                        blaetter = sorted({re.match(r"dtk5_32(\d{3}_\d{4})", os.path.basename(x)).group(1) for x in namen})
                        z.close()
                        a = os.path.join(ziel, "karten", "dtk5", "mehrfachdownload")
                        os.makedirs(a, exist_ok=True)
                        os.replace(p, os.path.join(a, f))
                        print(f"  {f}: DTK5-Blätter {', '.join(blaetter)} -> karten/dtk5/kacheln/")
                        n += 1
                        continue
            except zipfile.BadZipFile:
                print(f"  {f}: kein gültiges ZIP, bleibt liegen")
                continue
        for muster, ordner in EINSORTIEREN:
            m = re.match(muster, f)
            if m:
                o = os.path.join(ziel, *ordner.format(**m.groupdict()).split("/"))
                os.makedirs(o, exist_ok=True)
                if os.path.exists(os.path.join(o, f)):
                    print(f"  {f}: liegt schon in {os.path.relpath(o, ziel)}, bleibt liegen")
                else:
                    os.replace(p, os.path.join(o, f))
                    print(f"  {f} -> {os.path.relpath(o, ziel)}")
                    n += 1
                break
    print(f"{n} Dateien eingeordnet.")
    cmd_inventar(args)


def cmd_gebiete(args):
    feats = []
    for g in GEBIETE.values():
        ring = [[round(lon, 6), round(lat, 6)] for lon, lat in g.rand_grad(10)]
        feats.append({"type": "Feature", "properties": {"name": g.name, "gitter": g.kuerzel, "zweck": g.zweck,
                                                        "utm32": list(g.utm) if g.utm else None},
                      "geometry": {"type": "Polygon", "coordinates": [ring + [ring[0]]]}})
    p = os.path.join(PROJEKT, "geodaten", "gebiete.geojson")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        json.dump({"type": "FeatureCollection", "features": feats}, f, ensure_ascii=False, indent=1)
    print(p)


def cmd_dgm1_tif(args):
    o = os.path.join(os.path.abspath(args.ziel), "hoehe", "dgm1")
    if not os.path.isdir(o):
        sys.exit(f"Ordner fehlt: {o} (erst: laden --quellen dgm1)")
    aufgaben = []
    for f in sorted(os.listdir(o)):
        m = re.search(r"dgm1_32_(\d{3})_(\d{4})", f)
        ziel = os.path.join(o, "tif", os.path.splitext(f)[0] + ".tif")
        if m and not f.endswith((".part", ".tif", ".csv", ".txt")) and not os.path.exists(ziel):
            aufgaben.append((os.path.join(o, f), ziel, int(m.group(1)), int(m.group(2)), args.loeschen))
    if not aufgaben:
        print("Nichts umzuwandeln.")
        return
    bericht = os.path.join(o, "dgm1_tif.csv")
    neu = not os.path.exists(bericht)
    print(f"{len(aufgaben)} Kacheln, {args.parallel} Prozesse ...")
    with open(bericht, "a", encoding="utf-8", newline="") as fb, cf.ProcessPoolExecutor(max(1, args.parallel)) as ex:
        w = csv.writer(fb)
        if neu:
            w.writerow(["datei", "punkte", "ausserhalb", "doppelt", "leer", "zmin", "zmax", "versatz", "geloescht", "fehler"])
        for k, (name, r) in enumerate(ex.map(_umwandeln, aufgaben), 1):
            if isinstance(r, str):
                w.writerow([name] + [""] * 8 + [r])
                print(f"  [{k}/{len(aufgaben)}] FEHLER {name}: {r}")
            else:
                w.writerow([name, r["punkte"], r["ausserhalb"], r["doppelt"], r["leer"], r["zmin"], r["zmax"], r["versatz"],
                            r.get("geloescht", ""), ""])
                print(f"  [{k}/{len(aufgaben)}] {name}: {r['punkte']} Punkte, {r['leer']} leer, z {r['zmin']} … {r['zmax']} m"
                      + (f" ({r['ausserhalb']} außerhalb, {r['doppelt']} doppelt)" if r["ausserhalb"] or r["doppelt"] else ""))
    print(f"Bericht: {bericht}")


def main():
    try:
        sys.stdout.reconfigure(line_buffering=True, errors="replace")
    except AttributeError:
        pass
    if len(sys.argv) > 1 and sys.argv[1].lstrip("-") in BEFEHLE:
        sys.argv[1] = sys.argv[1].lstrip("-")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("befehl", choices=BEFEHLE)
    ap.add_argument("--ziel", default=os.environ.get("HALLIGHOOGE_DOWNLOAD", os.path.join(PROJEKT, "download")),
                    help="Zielordner (Vorgabe: HALLIGHOOGE_DOWNLOAD oder download/ im Projekt)")
    ap.add_argument("--quellen", help="nur diese Quellen (Komma), auch grosse")
    ap.add_argument("--gruppe", help="nur diese Gruppen (Komma): " + ",".join(GRUPPEN))
    ap.add_argument("--gebiet", choices=list(GEBIETE), help="Gebiet aller gewaehlten Quellen ueberschreiben")
    ap.add_argument("--gross", action="store_true", help="auch die Quellen der Stufe 'gross'")
    ap.add_argument("--jahre", help="Jahre fuer TrilaWatt/EasyGSH bzw. Befliegungen fuer DGM1, z. B. 2021 oder 2015-2021 oder 2006,2016")
    ap.add_argument("--monate", help="ERA5: Monate JJJJMM mit Komma (era5: Vorgabe 201312, era5_cds: 202610)")
    ap.add_argument("--szenen", type=int, default=3, help="Sentinel-2: klarste Szenen je Kachel (Vorgabe 3)")
    ap.add_argument("--baender", help="Sentinel-2: weitere Baender mit Komma, z. B. B02,B03,B04 (F44)")
    ap.add_argument("--max-gb", type=float, help="Quellen ueber dieser bekannten Groesse auslassen")
    ap.add_argument("--parallel", type=int, default=4, help="gleichzeitige Downloads bzw. Prozesse (Vorgabe 4)")
    ap.add_argument("--loeschen", action="store_true", help="dgm1-tif: XYZ nach fehlerfreier Umwandlung loeschen")
    args = ap.parse_args()
    try:
        {"liste": cmd_liste, "plan": cmd_plan, "laden": lambda a: cmd_plan(a, True), "inventar": cmd_inventar,
         "gebiete": cmd_gebiete, "dgm1-tif": cmd_dgm1_tif, "einsortieren": cmd_einsortieren}[args.befehl](args)
    except KeyboardInterrupt:
        print("\nabgebrochen – der nächste Lauf setzt fort.")
    except Exception:
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
