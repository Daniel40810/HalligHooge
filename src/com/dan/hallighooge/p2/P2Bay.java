package com.dan.hallighooge.p2;

import com.dan.core.Core;
import com.dan.core.gpu.Ablauf;
import com.dan.core.gpu.Geraet;
import com.dan.core.gpu.Kernel;
import com.dan.core.gpu.Konto;
import com.dan.core.gpu.Mittel;
import com.dan.core.gpu.Puffer;
import com.dan.core.gpu.Shader;
import com.dan.core.gpu.Stoppuhr;
import com.dan.core.pruef.Attest;
import com.dan.wave.Bay;
import com.dan.wave.BayGrid;
import com.dan.wave.gl.BayGpu;
import com.jogamp.opengl.GL4;
import com.jogamp.opengl.GLAutoDrawable;
import com.jogamp.opengl.GLCapabilities;
import com.jogamp.opengl.GLDrawableFactory;
import com.jogamp.opengl.GLOffscreenAutoDrawable;
import com.jogamp.opengl.GLProfile;
import org.lwjgl.system.MemoryStack;

import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.function.Supplier;

import static com.dan.core.pruef.Attest.f;
import static org.lwjgl.system.MemoryStack.stackPush;

/**
 * P2 (Werkbuch HalligHooge Teil A, Abschnitt 12): „Kernel aus {@code Bay} gleich“ – die Kernels des Bestands
 * ({@code bay_edges}, {@code bay_flux}, {@code bay_update} aus Renderer.jar) laufen über {@code com.dan.core.gpu}
 * (Vulkan) und werden mit zwei Bezügen verglichen:
 * <ul>
 * <li>{@link BayGpu} (OpenGL über JOGL): dieselben Shader, dieselbe Reihenfolge, float gegen float, der Fall aus P0
 * (250 Schritte zu 0,04 s). Grenze A aus P0: nach einem Schritt jede Zelle auf 1·10⁻⁵ m; nach vielen Schritten ist es
 * Rundungsdrift und wird festgehalten.</li>
 * <li>{@link Bay} auf dem Prozessor (double), mit dessen Zeitschritten nach CFL (rund 0,05 bis 0,1 s). Spielraum des
 * Bestands ({@code BayGpuCheck}): 1 mm, Volumen 1·10⁻⁶.</li>
 * </ul>
 * Anders als P0 kommt hier nichts Eigenes mehr vor: Gerät, Puffer, Kernel, Sperren ({@link Ablauf}) und Zeiten
 * ({@link Stoppuhr}) sind die des Kerns. Die Grenzwerte standen fest, bevor gemessen wurde.
 * <p>
 * Schalter: {@code --ohne-gl} lässt den Vergleich mit OpenGL weg (wo es kein JOGL gibt), {@code --klein} rechnet 256²
 * statt 1024² Zellen. Schreibt {@code docs/status/P2_Bay.md}.
 */
public final class P2Bay {
    private P2Bay() { }

    /** Ein Fall: Name, Bucht, Zahl der Schritte, ganz nass (dann gilt die Grenze für jede Zelle). */
    record Fall(String name, Supplier<Bay> bau, int schritte, boolean nass) { }

    /** Größte, 99,9 %- und mittlere Abweichung der Tiefe, größte des Durchflusses, Volumen, NaN. */
    record Abstand(double max, double q999, double median, double dq, double dvol, int nan) {
        String text() { return f("Tiefe größte %.1e m, 99,9 %% %.1e m, Median %.1e m; Durchfluss größte %.1e m²/s; Volumen %.1e; NaN %d", max, q999, median, dq, dvol, nan); }
    }

    private static final Attest A = new Attest("HalligHooge P2 (com.dan.core.gpu)", Core.VERSION);
    private static final int[] STAENDE = {1, 10, 50, 250};
    /** Fester Zeitschritt des Falls aus P0 in s; für ihn ist die Grenze gegen OpenGL gesetzt. */
    private static final double DT_P0 = 0.04;

    static Fall[] faelle(int n) {
        double l = 2.0 * n, m = l / 2;
        return new Fall[] {
                new Fall(f("nass, %d² zu 2 m, Buckel 1 m über 8–12 m Wasser", n), () -> {
                    Bay s = new Bay(0, 0, n, n, 2);
                    return s.build((x, z) -> -10 + 2 * Math.sin(x / 97) * Math.cos(z / 131), 0, new Bay.Init() {
                        public double eta(double x, double z) { return Math.exp(-((x - m) * (x - m) + (z - m) * (z - m)) / (2 * 80.0 * 80.0)); }
                    });
                }, 250, true),
                new Fall(f("Watt, %d² zu 2 m, Hang −3 … +2 m, Buckel 1,5 m (Nass-Trocken-Grenze)", n), () -> {
                    Bay s = new Bay(0, 0, n, n, 2);
                    return s.build((x, z) -> -3 + 5 * x / l + 0.5 * Math.sin(z / 60), 0, new Bay.Init() {
                        public double eta(double x, double z) { return 1.5 * Math.exp(-((x - 0.34 * l) * (x - 0.34 * l) + (z - m) * (z - m)) / (2 * 100.0 * 100.0)); }
                    });
                }, 250, false)
        };
    }

    public static void main(String[] a) {
        List<String> arg = List.of(a);
        boolean ohneGl = arg.contains("--ohne-gl");
        int n = arg.contains("--klein") ? 256 : 1024;
        System.out.println("P2Bay – Kernel aus Bay über com.dan.core.gpu " + Core.VERSION + " (Werkbuch HalligHooge Teil A, P2)");
        A.teil("Kernel aus Bay: Vulkan (core.gpu) gegen " + (ohneGl ? "den Prozessor" : "BayGpu (OpenGL) und den Prozessor"));
        if (ohneGl) {
            A.befund("Ohne OpenGL gerechnet (--ohne-gl): Der Vergleich mit BayGpu fehlt; die Abnahme von P2 braucht ihn.");
            try {
                lauf(null, n);
            } catch (Throwable e) {
                A.fehler(e);
            }
        } else MitGl.lauf(n);
        Path p = A.schreibe(Path.of("docs", "status", "P2_Bay.md"), "P2 – Kernel aus Bay gleich");
        if (p != null) System.out.println("\nAttest: " + p);
        System.out.println();
        System.out.println(A.pruefsteine() + " Prüfsteine. " + A.urteil());
        System.exit(A.verstoesse() == 0 ? 0 : 1);
    }

    /** Alles, was JOGL anfasst, liegt hier; mit {@code --ohne-gl} wird die Klasse nie geladen. */
    private static final class MitGl {
        static void lauf(int n) {
            GLOffscreenAutoDrawable dr = null;
            try {
                GLProfile prof = GLProfile.get(GLProfile.GL4);
                GLCapabilities caps = new GLCapabilities(prof);
                caps.setOnscreen(false);
                caps.setFBO(true);
                dr = GLDrawableFactory.getFactory(prof).createOffscreenAutoDrawable(null, caps, null, 64, 64);
                dr.display();
                Throwable[] fehler = {null};
                dr.invoke(true, (GLAutoDrawable d) -> {
                    try {
                        P2Bay.lauf(d.getGL().getGL4(), n);
                    } catch (Throwable e) {
                        fehler[0] = e;
                    }
                    return true;
                });
                if (fehler[0] != null) A.fehler(fehler[0]);
            } catch (Throwable e) {
                A.fehler(e);
            } finally {
                if (dr != null) dr.destroy();
            }
        }

        /** Rechnet die Bucht mit BayGpu und denselben Zeitschritten; gibt die Tiefen an den Ständen und zuletzt hu, hv. */
        static double[][] rechne(GL4 gl, Fall fall, double[] dts, double[] ms) {
            Bay bg = fall.bau.get();
            BayGpu g = new BayGpu(bg);
            g.gauges = false;
            g.timing = true;
            g.upload(gl);
            BayGrid q = bg.grids().get(0);
            double[][] erg = new double[STAENDE.length + 2][];
            for (int i = 1, k = 0; i <= fall.schritte; i++) {
                g.step(gl, dts[i - 1]);
                if (i == STAENDE[k]) {
                    if (k == STAENDE.length - 1) gl.glFinish();
                    g.sync(gl);
                    erg[k++] = q.depthCells().clone();
                }
            }
            ms[0] = g.gpuMs(0);
            g.dispose(gl);
            erg[STAENDE.length] = q.qxCells().clone();
            erg[STAENDE.length + 1] = q.qzCells().clone();
            return erg;
        }
    }

    private static void lauf(GL4 gl, int n) {
        if (gl != null) A.info("OpenGL", BayGpu.renderer(gl));
        Geraet.Optionen o = new Geraet.Optionen();
        o.strahlen = false;
        try (Geraet g = new Geraet(o)) {
            A.info("Vulkan", g.name + ", " + Geraet.version(g.apiVersion) + (g.kann.software() ? " (rechnet auf dem Prozessor)" : "") + "; Rechnen auf " + g.rechnen);
            Shader.Bestand e = Shader.bestand("/com/dan/wave/gl/bay_edges.comp"), fl = Shader.bestand("/com/dan/wave/gl/bay_flux.comp"), u = Shader.bestand("/com/dan/wave/gl/bay_update.comp");
            A.pruefe(true, "Kernels des Bestands (GLSL 430) nach Vulkan umgesetzt", f("bay_edges, bay_flux, bay_update: %d, %d, %d Push-Konstanten; übersetzt in %.0f ms",
                    e.gl().werte.size(), fl.gl().werte.size(), u.gl().werte.size(), e.spirv().ms + fl.spirv().ms + u.spirv().ms), "übersetzt");
            Kernel.Bindung p = Kernel.Bindung.PUFFER;
            try (Kernel ke = new Kernel(g, "bay_edges", e.spirv().code, e.gl().groesse, null, p, p, p);
                 Kernel kf = new Kernel(g, "bay_flux", fl.spirv().code, fl.gl().groesse, null, p, p, p, p);
                 Kernel ku = new Kernel(g, "bay_update", u.spirv().code, u.gl().groesse, null, p, p, p, p, p, p)) {
                e.spirv().frei();
                fl.spirv().frei();
                u.spirv().frei();
                for (Fall fall : faelle(n)) vergleich(gl, g, fall, ke, kf, ku, e.gl(), fl.gl(), u.gl());
            }
            if (g.validierung) A.pruefe(g.validierungsFehler == 0, "Validierungsschicht " + g.schicht + (g.synchronPruefung ? " mit Prüfung der Synchronisation" : ""),
                    g.validierungsFehler + " Fehler" + (g.meldungen.isEmpty() ? "" : "; die erste Meldung: " + g.meldungen.get(0).replace('\n', ' ')), "0 Fehler");
        }
    }

    /** Ein Lauf über core.gpu: Tiefen an den Ständen, der Stand am Ende (h | hu | hv), der Grund, Zeiten und der Ablauf. */
    private record Lauf(float[][] hVs, float[] erg, float[] bed, double gpuMs, double wandMs, int sperren, int durchgaenge) { }

    /** Rechnet die Bucht über core.gpu mit den gegebenen Zeitschritten, in derselben Reihenfolge wie {@code BayGpu.step}. */
    private static Lauf vulkan(Geraet g, Fall fall, double[] dts, Kernel ke, Kernel kf, Kernel ku, Shader.Gl ge, Shader.Gl gf, Shader.Gl gu) {
        Bay bv = fall.bau.get();
        BayGrid q = bv.grids().get(0);
        int nx = q.nx, nz = q.nz, px = q.px, n = px * (nz + 4), nf = (nx + 1) * nz + nx * (nz + 1);
        float[] bed = new float[n], st = new float[3 * n], eta = new float[n];
        double[] bb = q.bedCells(), h = q.depthCells(), hu = q.qxCells(), hv = q.qzCells(), em = q.etaMaxCells();
        for (int c = 0; c < n; c++) {
            bed[c] = Double.isNaN(bb[c]) ? 1e30f : (float) bb[c];
            st[c] = (float) h[c];
            st[n + c] = (float) hu[c];
            st[2 * n + c] = (float) hv[c];
            eta[c] = Double.isNaN(em[c]) ? -1e30f : (float) em[c];
        }
        double gpuVk = 0, wandVk = 0;
        int sperren = 0, durchgaenge = 0;
        float[] erg;
        float[][] hVs = new float[STAENDE.length][];
        Konto konto = g.konto("P2Bay", 256L << 20);
        try (Puffer pb = Puffer.speicher(g, konto, "Grund", 4L * n);
             Puffer pa = Puffer.speicher(g, konto, "Stand A", 12L * n);
             Puffer ps = Puffer.speicher(g, konto, "Stand S", 12L * n);
             Puffer pfl = Puffer.speicher(g, konto, "Flüsse", 20L * nf);
             Puffer pmf = Puffer.speicher(g, konto, "Massenflüsse", 4L * nf);
             Puffer pe = Puffer.speicher(g, konto, "höchster Stand", 4L * n);
             Puffer pst = Puffer.speicher(g, konto, "Zähler", 16);
             Puffer pax = Puffer.speicher(g, konto, "Rand", 16L * (Math.max(nx, nz) + 4));
             Stoppuhr uhr = new Stoppuhr(g, g.rechnen, 2)) {
            pb.schreibe(bed);
            pa.schreibe(st);
            ps.schreibe(st);
            pe.schreibe(eta);
            for (Puffer x : new Puffer[] {pfl, pmf, pst, pax}) x.nullen();
            float gr = (float) q.gravity, hDry = (float) q.hDry, hVel = (float) q.hVel, dx = (float) q.dx, man = (float) q.manning, vmax = (float) q.maxVelocity;
            Ablauf ab = new Ablauf(g);
            for (int k = 0, von0 = 0; k < STAENDE.length; von0 = STAENDE[k++]) {
                ab.leere();
                for (int i = von0; i < STAENDE[k]; i++) {
                    float dt = (float) dts[i];
                    for (int stufe = 1; stufe <= 2; stufe++) {
                        try (MemoryStack s = stackPush()) {                 // die Push-Konstanten kopiert der Ablauf
                            Puffer von = stufe == 1 ? pa : ps, nach = stufe == 1 ? ps : pa;
                            // Randzellen (alle vier Seiten Wand), dann Flüsse in x und z, dann die Stufe nach Heun – wie BayGpu.step
                            for (int side = 0; side < 4; side++) {
                                int m = side < 2 ? nz : nx;
                                ab.rechne("Rand", ke, ke.satz(pb, von, pax), ge.packen(s, "nx", nx, "nz", nz, "side", side, "kind", 0, "hDry", hDry, "hVel", hVel),
                                        Kernel.gruppen((m + 4) * 2, 64), 1, 1, new Mittel[] {pax}, new Mittel[] {pb, von});
                            }
                            long satzF = kf.satz(pb, von, pfl, pmf);
                            ab.rechne("Fluss x", kf, satzF, gf.packen(s, "nx", nx, "nz", nz, "mode", 0, "stage", stufe, "g", gr, "hDry", hDry, "hVel", hVel),
                                    Kernel.gruppen((nx + 1) * nz, 64), 1, 1, new Mittel[] {pb, von}, new Mittel[] {pfl, pmf});
                            ab.rechne("Fluss z", kf, satzF, gf.packen(s, "nx", nx, "nz", nz, "mode", 1, "stage", stufe, "g", gr, "hDry", hDry, "hVel", hVel),
                                    Kernel.gruppen(nx * (nz + 1), 64), 1, 1, new Mittel[] {pb, von}, new Mittel[] {pfl, pmf});
                            ab.rechne("Stufe", ku, ku.satz(pb, von, nach, pfl, pe, pst), gu.packen(s, "nx", nx, "nz", nz, "stage", stufe, "g", gr, "hDry", hDry, "hVel", hVel,
                                    "dt", dt, "dx", dx, "manning", man, "maxVelocity", vmax), Kernel.gruppen(nx * nz, 64), 1, 1, new Mittel[] {pb, von, pfl}, new Mittel[] {nach, pe, pst});
                        }
                    }
                }
                wandVk += g.rechnen.einmal(c -> {
                    uhr.runde(c);
                    uhr.start(c, "lauf");
                    ab.aufnehmen(c, null);
                    uhr.stopp(c, "lauf");
                }) / 1e6;
                uhr.sammle(true);
                gpuVk += uhr.verfuegbar ? uhr.letzte("lauf") : 0;
                sperren += ab.sperren();
                durchgaenge += ab.durchgaenge();
                hVs[k] = pa.floats(n);
            }
            if (!uhr.verfuegbar) gpuVk = wandVk;
            erg = pa.floats(3 * n);
        }
        if (konto.belegt() != 0) throw new IllegalStateException("Speicherkonto nach dem Lauf nicht leer: " + konto);
        return new Lauf(hVs, erg, bed, gpuVk, wandVk, sperren, durchgaenge);
    }

    private static void vergleich(GL4 gl, Geraet g, Fall fall, Kernel ke, Kernel kf, Kernel ku, Shader.Gl ge, Shader.Gl gf, Shader.Gl gu) {
        // ---------------------------------------------------------- Prozessor (Bay, double) mit seinen eigenen Zeitschritten nach CFL
        Bay bc = fall.bau.get();
        BayGrid qc = bc.grids().get(0);
        int nx = qc.nx, nz = qc.nz, px = qc.px, n = px * (nz + 4), letzter = STAENDE.length - 1;
        double[] dtC = new double[fall.schritte];
        double[][] hCs = new double[STAENDE.length][];
        long t0 = System.nanoTime();
        for (int i = 1, k = 0; i <= fall.schritte; i++) {
            dtC[i - 1] = bc.step();
            if (i == STAENDE[k]) hCs[k++] = qc.depthCells().clone();
        }
        double wandCpu = (System.nanoTime() - t0) / 1e6, zs = (double) nx * nz * fall.schritte, zeitC = 0;
        for (double dt : dtC) zeitC += dt;

        // ---------------------------------------------------------- gegen OpenGL: der Fall aus P0, fester Schritt 0,04 s
        // (für ihn ist die Grenze gesetzt; mit den längeren Schritten des Prozessors läuft die Nass-Trocken-Grenze weiter,
        // und die Rundung in float wächst dort über sie hinaus)
        if (gl != null) {
            double[] dtP0 = new double[fall.schritte];
            Arrays.fill(dtP0, DT_P0);
            Lauf v = vulkan(g, fall, dtP0, ke, kf, ku, ge, gf, gu);
            double[] msGl = {0};
            double[][] hGs = MitGl.rechne(gl, fall, dtP0, msGl);
            double hMax = 0;
            for (int c = 0; c < n; c++) if (v.bed[c] <= 1e29f) hMax = Math.max(hMax, hGs[letzter][c]);
            double ulp = Math.ulp((float) hMax);
            double[] drift = new double[STAENDE.length];
            for (int k = 0; k < STAENDE.length; k++) drift[k] = abstand(v.hVs[k], hGs[k], null, null, null, v.bed, nx, nz, px, n).max;
            A.pruefe(drift[0] <= 1e-5, fall.name + ", gegen OpenGL, ein Schritt (Kernel gleich)", f("größte %.1e m (%.1f float-Schritte bei %.1f m)", drift[0], drift[0] / ulp, hMax),
                    "jede Zelle ≤ 1·10⁻⁵ m (Grenze A)");
            A.info(fall.name + ", gegen OpenGL, Drift in float", "größte Abweichung nach Schritten (in float-Schritten): " + reihe(drift, ulp));
            Abstand d = abstand(v.erg, hGs[letzter], hGs[letzter + 1], hGs[letzter + 2], v.erg, v.bed, nx, nz, px, n);
            String lauf = f(", gegen OpenGL, %d Schritte zu %.2f s (Fall aus P0)", fall.schritte, DT_P0);
            if (fall.nass) A.pruefe(d.nan == 0, fall.name + lauf, d.text(), "kein NaN; Abweichung ohne Grenze (Drift)");
            else A.pruefe(d.q999 <= 1e-5 && d.dvol <= 1e-6 && d.nan == 0, fall.name + lauf, d.text(), "99,9 % ≤ 1·10⁻⁵ m, Volumen ≤ 1·10⁻⁶ [G]");
            A.info(fall.name + ", Zeit gegen OpenGL", f("Karte: Vulkan %.2f ns je Zellschritt (%.2f·10⁸ Zellschritte/s), OpenGL %.2f ns (%.2f : 1); Wand Vulkan %.0f ms",
                    v.gpuMs * 1e6 / zs, zs / (v.gpuMs / 1e3) / 1e8, msGl[0] * 1e6 / zs, msGl[0] / v.gpuMs, v.wandMs));
        }

        // ---------------------------------------------------------- gegen den Prozessor: dessen Zeitschritte
        Lauf v = vulkan(g, fall, dtC, ke, kf, ku, ge, gf, gu);
        double hMax = 0;
        for (int c = 0; c < n; c++) if (v.bed[c] <= 1e29f) hMax = Math.max(hMax, hCs[letzter][c]);
        double ulp = Math.ulp((float) hMax);
        double[] driftC = new double[STAENDE.length];
        for (int k = 0; k < STAENDE.length; k++) driftC[k] = abstand(v.hVs[k], hCs[k], null, null, null, v.bed, nx, nz, px, n).max;
        A.pruefe(driftC[0] <= 1e-5, fall.name + ", gegen den Prozessor (double), ein Schritt", f("größte %.1e m (%.1f float-Schritte bei %.1f m)", driftC[0], driftC[0] / ulp, hMax),
                "jede Zelle ≤ 1·10⁻⁵ m [G]");
        A.info(fall.name + ", gegen den Prozessor, Drift", "größte Abweichung nach Schritten (in float-Schritten): " + reihe(driftC, ulp));
        Abstand dc = abstand(v.erg, hCs[letzter], qc.qxCells(), qc.qzCells(), v.erg, v.bed, nx, nz, px, n);
        String lauf = f(", gegen den Prozessor, %d Schritte nach CFL (%.1f s)", fall.schritte, zeitC);
        if (fall.nass) A.pruefe(dc.max <= 1e-3 && dc.dvol <= 1e-6 && dc.nan == 0, fall.name + lauf, dc.text(), "jede Zelle ≤ 1 mm, Volumen ≤ 1·10⁻⁶ (Spielraum des Bestands)");
        else A.pruefe(dc.q999 <= 1e-3 && dc.dvol <= 1e-6 && dc.nan == 0, fall.name + lauf, dc.text(), "99,9 % ≤ 1 mm [G], Volumen ≤ 1·10⁻⁶");
        A.info(fall.name + ", Ablauf", f("%d Durchgänge, %d Sperrbefehle (der Ablauf rechnet sie aus den gemeldeten Zugriffen)", v.durchgaenge, v.sperren));
        A.info(fall.name + ", Zeit", f("Karte: Vulkan %.2f ns je Zellschritt (%.2f·10⁸ Zellschritte/s); Prozessor (ein Faden) %.0f ns; Wand Vulkan %.0f ms",
                v.gpuMs * 1e6 / zs, zs / (v.gpuMs / 1e3) / 1e8, wandCpu * 1e6 / zs, v.wandMs));
    }

    private static String reihe(double[] drift, double ulp) {
        StringBuilder d = new StringBuilder();
        for (int k = 0; k < STAENDE.length; k++) d.append(k == 0 ? "" : " · ").append(STAENDE[k]).append(f(": %.1e m (%.0f)", drift[k], drift[k] / ulp));
        return d.toString();
    }

    /**
     * Abstand der Tiefe {@code hV} (float, von der Karte) zum Bezug {@code hB} über alle Zellen mit Grund; mit
     * {@code uB}, {@code vB} und dem ganzen Stand {@code stand} (h | hu | hv) auch Durchfluss und Volumen.
     */
    private static Abstand abstand(float[] hV, double[] hB, double[] uB, double[] vB, float[] stand, float[] bed, int nx, int nz, int px, int n) {
        int zellen = 0, nan = 0;
        double[] dh = new double[nx * nz];
        double dq = 0, volB = 0, volV = 0;
        for (int j = 0; j < nz; j++)
            for (int i = 0; i < nx; i++) {
                int c = (j + 2) * px + i + 2;
                if (bed[c] > 1e29f) continue;
                double v = hV[c];
                if (Double.isNaN(v)) nan++;
                dh[zellen++] = Math.abs(v - hB[c]);
                if (uB != null) dq = Math.max(dq, Math.max(Math.abs(stand[n + c] - uB[c]), Math.abs(stand[2 * n + c] - vB[c])));
                volB += hB[c];
                volV += v;
            }
        double[] s = Arrays.copyOf(dh, zellen);
        Arrays.sort(s);
        return new Abstand(s[zellen - 1], s[(int) (0.999 * (zellen - 1))], s[zellen / 2], dq, Math.abs(volV - volB) / volB, nan);
    }
}
