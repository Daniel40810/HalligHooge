package com.dan.hallighooge.p0;

import java.nio.file.Path;

/**
 * P0 – Unterbau messen (Werkbuch 12), alles ohne Fenster in einem Lauf: Gerät (P0.1), Bay-Kernel in Vulkan gegen BayGpu
 * (P0.3), Strahlabfrage über einer DGM1-Kachel (P0.4), Bau (P0.5). Schreibt die Messtabelle nach
 * {@code docs/status/P0_Messtabelle.md} und endet mit „Alles in Ordnung.“ oder der Zahl der Verstöße.
 * <p>
 * Die Vulkan-Fläche im FFrame (P0.2) ist ein Fenster: {@link P0Flaeche}. Schalter: {@code -Dp0.validierung=true}
 * (Validierung, verfälscht die Zeiten), {@code -Dp0.geraet=N}, {@code -Dp0.dgm1=<datei.xyz>}.
 */
public final class P0Check {
    private P0Check() {}

    public static void main(String[] a) {
        System.out.println("P0 – Unterbau messen (Werkbuch 12)");
        Bericht b = new Bericht();
        P0Geraet.messen(b);
        P0Bay.messen(b);
        P0Strahl.messen(b);
        Path p = b.schreiben("P0_Messtabelle.md", "P0 – Unterbau messen: Messtabelle");
        System.out.println();
        System.out.println("Messtabelle: " + p);
        System.out.println("Die Fläche im FFrame (P0.2) misst P0Flaeche (Fenster).");
        System.out.println(b.verstoesse() == 0 ? "Alles in Ordnung." : b.verstoesse() + " Verstöße.");
        System.exit(b.verstoesse() == 0 ? 0 : 1);
    }
}
