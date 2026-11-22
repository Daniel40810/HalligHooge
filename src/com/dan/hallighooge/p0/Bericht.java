package com.dan.hallighooge.p0;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Messtabelle von P0 (Werkbuch 12): je Teil Zeilen mit Größe, Wert, Grenze und Urteil, dazu freie Zeilen (Befund).
 * Wird nach {@code docs/status/} im Projektordner geschrieben und auf der Konsole ausgegeben.
 */
final class Bericht {
    enum Urteil { OK, FEHLT, INFO }

    record Zeile(String teil, String groesse, String wert, String grenze, Urteil urteil) {}

    final List<Zeile> zeilen = new ArrayList<>();
    final List<String> befund = new ArrayList<>();
    private String teil = "";

    void teil(String t) {
        teil = t;
        System.out.println();
        System.out.println(t);
    }

    /** Eine geprüfte Größe: erfüllt oder nicht. */
    boolean pruefe(boolean erfuellt, String groesse, String wert, String grenze) {
        zeilen.add(new Zeile(teil, groesse, wert, grenze, erfuellt ? Urteil.OK : Urteil.FEHLT));
        System.out.println("  " + (erfuellt ? "ok   " : "FEHLT") + "  " + groesse + ": " + wert + (grenze.isEmpty() ? "" : "  [" + grenze + "]"));
        return erfuellt;
    }

    /** Eine gemessene Größe ohne Grenze. */
    void info(String groesse, String wert) {
        zeilen.add(new Zeile(teil, groesse, wert, "", Urteil.INFO));
        System.out.println("         " + groesse + ": " + wert);
    }

    void befund(String t) {
        befund.add(teil + ": " + t);
        System.out.println("  » " + t);
    }

    void fehler(Throwable e) {
        String m = e.getClass().getSimpleName() + ": " + e.getMessage();
        zeilen.add(new Zeile(teil, "Ablauf", m.replace('\n', ' '), "ohne Fehler", Urteil.FEHLT));
        System.out.println("  FEHLT  Ablauf: " + m);
        e.printStackTrace(System.out);
    }

    int verstoesse() {
        int n = 0;
        for (Zeile z : zeilen) if (z.urteil == Urteil.FEHLT) n++;
        return n;
    }

    /** Schreibt die Tabelle nach docs/status/<datei> (relativ zum Arbeitsordner = Projektordner in NetBeans). */
    Path schreiben(String datei, String titel) {
        StringBuilder b = new StringBuilder();
        b.append("# ").append(titel).append("\n\n");
        b.append("Stand ").append(LocalDateTime.now().format(DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm"))).append(", ")
                .append(System.getProperty("java.vm.name")).append(' ').append(System.getProperty("java.version"))
                .append(", LWJGL ").append(org.lwjgl.Version.getVersion()).append(".\n\n");
        b.append("| Teil | Größe | Wert | Grenze | Urteil |\n|---|---|---|---|---|\n");
        for (Zeile z : zeilen)
            b.append("| ").append(z.teil).append(" | ").append(z.groesse).append(" | ").append(z.wert.replace("|", "/")).append(" | ")
                    .append(z.grenze).append(" | ").append(switch (z.urteil) { case OK -> "ok"; case FEHLT -> "**fehlt**"; case INFO -> "–"; }).append(" |\n");
        if (!befund.isEmpty()) {
            b.append("\n## Befund\n\n");
            for (String t : befund) b.append("- ").append(t).append('\n');
        }
        int v = verstoesse();
        b.append('\n').append(v == 0 ? "Alles in Ordnung." : v + " Verstöße.").append('\n');
        Path p = Path.of("docs", "status", datei);
        try {
            Files.createDirectories(p.getParent());
            Files.writeString(p, b.toString(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            System.out.println("  (Bericht nicht geschrieben: " + e.getMessage() + ")");
        }
        return p.toAbsolutePath();
    }

    static String f(String fmt, Object... a) { return String.format(Locale.GERMAN, fmt, a); }
}
