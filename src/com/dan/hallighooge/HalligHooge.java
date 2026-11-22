package com.dan.hallighooge;

import com.dan.steuerhaus.buehne.Szenenapp;

import java.io.File;

/**
 * HalligHooge – die Anwendung (Werkbuch HalligHooge Teil B; seit Steuerhaus W1, Werkbuch 110 und 111, eine App im
 * Steuerhaus). Was Hooge ausmacht, steht in {@code src/szenen/Hooge.steuerhaus} (Titel, Logo, Thema, Quellen, Katalog)
 * und {@code src/szenen/Hooge.szenen} (Gebiet, Pegel, Ansichten, Szenarien). Bild, Physik und Zeit liefert
 * {@code com.dan.lauf} im Renderer, Fenster und Bedienung das Steuerhaus ({@link Szenenapp}).
 * <pre>
 * java --enable-native-access=ALL-UNNAMED -Xmx12g -jar dist\HalligHooge.jar [--szenario sturm] [--thema nautik] [--sekunden 20]
 * java --enable-native-access=ALL-UNNAMED -Xmx12g -jar dist\HalligHooge.jar --vorschau      (Bilder des Katalogs, ohne Fenster)
 * </pre>
 * Alle Aufrufoptionen: README von {@code com.dan.steuerhaus}.
 */
public final class HalligHooge {
    /** Das Manifest, relativ zum Projektordner (Start aus NetBeans, HalligHooge.cmd und die Läufe arbeiten dort). */
    static final File MANIFEST = new File("src" + File.separator + "szenen" + File.separator + "Hooge.steuerhaus");

    private HalligHooge() { }

    public static void main(String[] args) throws Exception {
        Szenenapp.starten(MANIFEST, args);
    }
}
