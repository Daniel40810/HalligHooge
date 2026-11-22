import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * Prüft, ob das Projekt dünn bleibt (Werkbuch HalligHooge Teil B, B.1; Prüfsteine 4 und 5 aus B.6; seit Steuerhaus W1,
 * Werkbuch 110, Prüfstein 5: höchstens 200 Zeilen, das Steuerhaus erlaubt):
 * <ul>
 * <li><b>Importe:</b> Die Anwendung kennt nur {@code com.dan.steuerhaus} (ohne {@code demo}), {@code com.dan.lauf} (ohne {@code demo}), {@code com.dan.core} (ohne
 * {@code core.gpu}), FStyle (Klassen aus {@code lib/FStyle.jar}), sich selbst, {@code java.*} und
 * {@code javax.swing.*}. Geprüft wird jeder Name {@code com.dan.…}, {@code org.…} und {@code javax.…} im Code, nicht
 * nur die Zeilen mit {@code import}.</li>
 * <li><b>Umfang:</b> höchstens 200 Zeilen Java [G] (bis Teil A 1 500).</li>
 * <li><b>Inhalt:</b> keine Shader.</li>
 * </ul>
 * Die Proben aus P0 und P2 ({@code p0}, {@code p2}) gehören nicht zur Anwendung und zählen nicht mit.
 * <pre>
 * java tools\ImportPruefung.java [src] [lib\FStyle.jar]
 * </pre>
 */
public final class ImportPruefung {
    static final int GRENZE = 200;
    static final Set<String> PROBEN = Set.of("p0", "p2");
    static int steine, verstoesse;

    public static void main(String[] args) throws Exception {
        File src = new File(args.length > 0 ? args[0] : "src"), fstyle = new File(args.length > 1 ? args[1] : "lib" + File.separator + "FStyle.jar");
        File wurzel = new File(src, "com" + File.separator + "dan" + File.separator + "hallighooge");
        System.out.println("ImportPruefung – HalligHooge (Werkbuch HalligHooge Teil B, B.1; Steuerhaus W1)");
        Set<String> stil = new HashSet<>();
        try (ZipFile z = new ZipFile(fstyle)) {
            for (ZipEntry e : java.util.Collections.list(z.entries())) {
                String n = e.getName();
                if (n.startsWith("com/dan/") && n.endsWith(".class")) stil.add(n.substring(0, n.lastIndexOf('/')).replace('/', '.'));
            }
        }
        List<File> quellen = new ArrayList<>(), shader = new ArrayList<>();
        sammle(wurzel, quellen, shader);
        List<String> schlecht = new ArrayList<>();
        int zeilen = 0;
        Pattern name = Pattern.compile("\\b(com\\.dan|org|javax)\\.[a-z_][A-Za-z0-9_]*(\\.[a-z_][a-z0-9_]*)*");
        for (File f : quellen) {
            int nr = 0;
            boolean kommentar = false;
            for (String z : Files.readAllLines(f.toPath(), StandardCharsets.UTF_8)) {
                nr++;
                zeilen++;
                String c = z;
                // Kommentare grob abziehen: Blöcke und alles hinter //
                if (kommentar) {
                    int e = c.indexOf("*/");
                    if (e < 0) continue;
                    c = c.substring(e + 2);
                    kommentar = false;
                }
                for (int a; (a = c.indexOf("/*")) >= 0; ) {
                    int e = c.indexOf("*/", a + 2);
                    if (e < 0) {
                        c = c.substring(0, a);
                        kommentar = true;
                        break;
                    }
                    c = c.substring(0, a) + c.substring(e + 2);
                }
                int k = c.indexOf("//");
                if (k >= 0) c = c.substring(0, k);
                c = c.replaceAll("\"(\\\\.|[^\"\\\\])*\"", "\"\"");
                Matcher m = name.matcher(c);
                while (m.find()) {
                    String p = m.group();
                    if (!erlaubt(p, stil)) schlecht.add(wurzel.toPath().relativize(f.toPath()) + ":" + nr + " " + p);
                }
            }
        }
        pruefe(schlecht.isEmpty(), "Importe der Anwendung (nur steuerhaus, lauf, core ohne gpu, FStyle, java.*, javax.swing.*)",
                schlecht.size() + " Verstöße in " + quellen.size() + " Dateien" + (schlecht.isEmpty() ? "" : ": " + String.join("; ", schlecht.subList(0, Math.min(8, schlecht.size())))), "0 Verstöße");
        pruefe(zeilen <= GRENZE, "Prüfstein 5 (W1): Umfang der Anwendung, Java ohne die Proben p0 und p2", zeilen + " Zeilen in " + quellen.size() + " Dateien", "≤ " + GRENZE + " Zeilen [G]");
        pruefe(shader.isEmpty(), "Inhalt: Shader in der Anwendung", shader.size() + " Dateien", "0");
        System.out.println();
        System.out.println(steine + " Prüfsteine. " + (verstoesse == 0 ? "Alles in Ordnung." : verstoesse + (verstoesse == 1 ? " Verstoß." : " Verstöße.")));
        System.exit(verstoesse == 0 ? 0 : 1);
    }

    static boolean erlaubt(String p, Set<String> stil) {
        if (p.startsWith("javax.")) return p.startsWith("javax.swing") || p.startsWith("javax.imageio");
        if (p.startsWith("org.")) return false;
        if (p.startsWith("com.dan.hallighooge")) return !p.startsWith("com.dan.hallighooge.p0") && !p.startsWith("com.dan.hallighooge.p2");
        if (p.startsWith("com.dan.steuerhaus")) return !p.startsWith("com.dan.steuerhaus.demo");
        if (p.startsWith("com.dan.lauf")) return !p.startsWith("com.dan.lauf.demo");
        if (p.startsWith("com.dan.core")) return !p.startsWith("com.dan.core.gpu") && !p.contains(".demo");
        for (String s : stil) if (p.equals(s) || p.startsWith(s + ".")) return true;
        return false;
    }

    static void sammle(File d, List<File> quellen, List<File> shader) {
        File[] fs = d.listFiles();
        if (fs == null) return;
        java.util.Arrays.sort(fs);
        for (File f : fs) {
            if (f.isDirectory()) {
                if (!PROBEN.contains(f.getName())) sammle(f, quellen, shader);
            } else if (f.getName().endsWith(".java")) quellen.add(f);
            else if (f.getName().matches(".*\\.(glsl|comp|frag|vert|geom|spv)")) shader.add(f);
        }
    }

    static void pruefe(boolean ok, String was, String wert, String grenze) {
        steine++;
        if (!ok) verstoesse++;
        System.out.println((ok ? "  ok     " : "  FEHLT  ") + was + ": " + wert + "  [" + grenze + "]");
    }
}
