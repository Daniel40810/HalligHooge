package com.dan.hallighooge.p0;

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
import org.lwjgl.vulkan.VkCommandBuffer;

import java.nio.ByteBuffer;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.function.Supplier;

import static com.dan.hallighooge.p0.Bericht.f;
import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.vulkan.VK13.*;

/**
 * P0.3 (Werkbuch 12): ein Kernel aus {@code wave.Bay} in Vulkan gegen {@link BayGpu} (OpenGL über JOGL). Dieselben Shader
 * des Bestands ({@code bay_edges}, {@code bay_flux}, {@code bay_update} aus Renderer.jar) werden zur Laufzeit nach
 * Vulkan-GLSL umgesetzt (lose Uniforms → Push-Konstanten) und mit shaderc übersetzt; dann rechnen beide dieselbe Bucht
 * (ein Gitter, Wände, fester Schritt) in derselben Reihenfolge wie {@code BayGpu.step(gl, dt)}, und der Stand wird Zelle
 * für Zelle verglichen. Grenze: gleich auf 1·10⁻⁵ m (Werkbuch); dazu die Zeiten je Zellschritt auf beiden Wegen.
 */
public final class P0Bay {
    private P0Bay() {}

    /** Ein Fall: Name, Bucht, Schritt, Zahl der Schritte, ganz nass (dann gilt die Grenze für jede Zelle). */
    record Fall(String name, Supplier<Bay> bau, double dt, int schritte, boolean nass) {}

    static final Fall[] FAELLE = {
            new Fall("nass, 1024² zu 2 m, Buckel 1 m über 8–12 m Wasser", () -> {
                Bay s = new Bay(0, 0, 1024, 1024, 2);
                return s.build((x, z) -> -10 + 2 * Math.sin(x / 97) * Math.cos(z / 131), 0, new Bay.Init() {
                    public double eta(double x, double z) { return Math.exp(-((x - 1024) * (x - 1024) + (z - 1024) * (z - 1024)) / (2 * 80.0 * 80.0)); }
                });
            }, 0.04, 250, true),
            new Fall("Watt, 1024² zu 2 m, Hang −3 … +2 m, Buckel 1,5 m (Nass-Trocken-Grenze)", () -> {
                Bay s = new Bay(0, 0, 1024, 1024, 2);
                return s.build((x, z) -> -3 + 5 * x / 2048 + 0.5 * Math.sin(z / 60), 0, new Bay.Init() {
                    public double eta(double x, double z) { return 1.5 * Math.exp(-((x - 700) * (x - 700) + (z - 1024) * (z - 1024)) / (2 * 100.0 * 100.0)); }
                });
            }, 0.04, 250, false)
    };

    public static void main(String[] a) {
        Bericht b = new Bericht();
        messen(b);
        Path p = b.schreiben("P0_Bay.md", "P0.3 – Bay-Kernel in Vulkan gegen BayGpu");
        System.out.println();
        System.out.println("Bericht: " + p);
        System.out.println(b.verstoesse() == 0 ? "Alles in Ordnung." : b.verstoesse() + " Verstöße.");
        System.exit(0);
    }

    static void messen(Bericht b) {
        b.teil("P0.3 Bay-Kernel: Vulkan gegen BayGpu (OpenGL)");
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
                try { lauf(d.getGL().getGL4(), b); } catch (Throwable e) { fehler[0] = e; }
                return true;
            });
            if (fehler[0] != null) b.fehler(fehler[0]);
        } catch (Throwable e) {
            b.fehler(e);
        } finally {
            if (dr != null) dr.destroy();
        }
    }

    private static void lauf(GL4 gl, Bericht b) {
        b.info("OpenGL", BayGpu.renderer(gl));
        Vulkan.Optionen o = new Vulkan.Optionen();
        o.strahlen = false;
        try (Vulkan vk = new Vulkan(o)) {
            b.info("Vulkan", vk.name + ", " + Vulkan.version(vk.apiVersion));
            Object[] e = Shader.bestand("/com/dan/wave/gl/bay_edges.comp");
            Object[] fl = Shader.bestand("/com/dan/wave/gl/bay_flux.comp");
            Object[] u = Shader.bestand("/com/dan/wave/gl/bay_update.comp");
            Shader.Gl ge = (Shader.Gl) e[0], gf = (Shader.Gl) fl[0], gu = (Shader.Gl) u[0];
            Shader.Spirv se = (Shader.Spirv) e[1], sf = (Shader.Spirv) fl[1], su = (Shader.Spirv) u[1];
            b.pruefe(true, "Bestand nach Vulkan umgesetzt", f("bay_edges, bay_flux, bay_update: %d, %d, %d Push-Konstanten, Block %s; übersetzt in %.0f ms",
                    ge.werte.size(), gf.werte.size(), gu.werte.size(), ge.namenlos && gf.namenlos && gu.namenlos ? "namenlos" : "p0w", se.ms + sf.ms + su.ms), "übersetzt");
            int sb = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            try (Kernel ke = new Kernel(vk, se.code, new int[]{sb, sb, sb}, ge.groesse);
                 Kernel kf = new Kernel(vk, sf.code, new int[]{sb, sb, sb, sb}, gf.groesse);
                 Kernel ku = new Kernel(vk, su.code, new int[]{sb, sb, sb, sb, sb, sb}, gu.groesse)) {
                se.frei();
                sf.frei();
                su.frei();
                for (Fall fall : FAELLE) vergleich(gl, vk, b, fall, ke, kf, ku, ge, gf, gu);
            }
        }
    }

    private static void vergleich(GL4 gl, Vulkan vk, Bericht b, Fall fall, Kernel ke, Kernel kf, Kernel ku, Shader.Gl ge, Shader.Gl gf, Shader.Gl gu) {
        // ---------------------------------------------------------- OpenGL (BayGpu)
        Bay bg = fall.bau.get();
        BayGpu g = new BayGpu(bg);
        g.gauges = false;
        g.timing = true;
        g.upload(gl);
        // Zwischenstände: nach einem Schritt prüft der Vergleich den Kernel, danach zeigt er, wie die Rundung wächst
        int[] staende = {1, 10, 50, fall.schritte};
        BayGrid qg = bg.grids().get(0);
        double[][] hGs = new double[staende.length][];
        long t0 = System.nanoTime();
        for (int i = 1, k = 0; i <= fall.schritte; i++) {
            g.step(gl, fall.dt);
            if (i == staende[k]) {
                if (k == staende.length - 1) gl.glFinish();
                g.sync(gl);
                hGs[k++] = qg.depthCells().clone();
            }
        }
        double wandGl = (System.nanoTime() - t0) / 1e6;
        double gpuGl = g.gpuMs(0);
        g.dispose(gl);
        double[] hG = hGs[staende.length - 1], uG = qg.qxCells().clone(), vG = qg.qzCells().clone();

        // ---------------------------------------------------------- Vulkan
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
        double wandVk = 0, gpuVk = 0;
        float[] erg;
        float[][] hVs = new float[staende.length][];
        try (Puffer pb = Puffer.speicher(vk, 4L * n);
             Puffer pa = Puffer.speicher(vk, 12L * n);
             Puffer ps = Puffer.speicher(vk, 12L * n);
             Puffer pfl = Puffer.speicher(vk, 20L * nf);
             Puffer pmf = Puffer.speicher(vk, 4L * nf);
             Puffer pe = Puffer.speicher(vk, 4L * n);
             Puffer pst = Puffer.speicher(vk, 16);
             Puffer pax = Puffer.speicher(vk, 16L * (Math.max(nx, nz) + 4))) {
            pb.schreiben(bed);
            pa.schreiben(st);
            ps.schreiben(st);
            pe.schreiben(eta);
            pfl.nullen();
            pmf.nullen();
            pst.nullen();
            pax.nullen();
            long zeit = vk.zeitAbfragen(2 * staende.length);
            float gr = (float) q.gravity, hDry = (float) q.hDry, hVel = (float) q.hVel, dt = (float) fall.dt, dx = (float) q.dx;
            float man = (float) q.manning, vmax = (float) q.maxVelocity;
            for (int k = 0, von0 = 0; k < staende.length; von0 = staende[k++]) {
                VkCommandBuffer c = vk.befehle(vk.pool);
                Vulkan.beginne(c, true);
                vkCmdResetQueryPool(c, zeit, 2 * k, 2);
                vkCmdWriteTimestamp2(c, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, zeit, 2 * k);
                for (int i = von0; i < staende[k]; i++) {
                    for (int stufe = 1; stufe <= 2; stufe++) {
                        try (MemoryStack s = stackPush()) {                 // je Stufe ein Rahmen: die Push-Konstanten liegen auf dem Stapel
                            Puffer von = stufe == 1 ? pa : ps, nach = stufe == 1 ? ps : pa;
                            // Randzellen (alle vier Seiten Wand)
                            for (int side = 0; side < 4; side++) {
                                int m = side < 2 ? nz : nx;
                                ByteBuffer pc = ge.packen(s, "nx", nx, "nz", nz, "side", side, "kind", 0, "hDry", hDry, "hVel", hVel);
                                ke.aufnehmen(c, ke.satz(pb.handle, von.handle, pax.handle), pc, gruppen((m + 4) * 2), 1, 1);
                            }
                            // Flüsse in x und z, dann die Stufe nach Heun
                            long setF = kf.satz(pb.handle, von.handle, pfl.handle, pmf.handle);
                            kf.aufnehmen(c, setF, gf.packen(s, "nx", nx, "nz", nz, "mode", 0, "stage", stufe, "g", gr, "hDry", hDry, "hVel", hVel), gruppen((nx + 1) * nz), 1, 1);
                            kf.aufnehmen(c, setF, gf.packen(s, "nx", nx, "nz", nz, "mode", 1, "stage", stufe, "g", gr, "hDry", hDry, "hVel", hVel), gruppen(nx * (nz + 1)), 1, 1);
                            ku.aufnehmen(c, ku.satz(pb.handle, von.handle, nach.handle, pfl.handle, pe.handle, pst.handle),
                                    gu.packen(s, "nx", nx, "nz", nz, "stage", stufe, "g", gr, "hDry", hDry, "hVel", hVel, "dt", dt, "dx", dx,
                                            "manning", man, "maxVelocity", vmax), gruppen(nx * nz), 1, 1);
                        }
                    }
                }
                vkCmdWriteTimestamp2(c, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, zeit, 2 * k + 1);
                Vulkan.ok(vkEndCommandBuffer(c), "vkEndCommandBuffer");
                long warte = vk.abschicken(vk.queue, c);
                vkFreeCommandBuffers(vk.device, vk.pool, c);
                double[] ts = vk.zeiten(zeit, 2 * k, 2);
                wandVk += warte / 1e6;
                gpuVk += (ts[1] - ts[0]) / 1e6;
                hVs[k] = pa.floats(n);
            }
            vkDestroyQueryPool(vk.device, zeit, null);
            erg = pa.floats(3 * n);
        }

        // ---------------------------------------------------------- Vergleich
        int zellen = 0, nanV = 0;
        double[] dh = new double[nx * nz];
        double dqMax = 0, volG = 0, volV = 0, qMax = 0;
        for (int j = 0; j < nz; j++)
            for (int i = 0; i < nx; i++) {
                int c = (j + 2) * px + i + 2;
                if (bed[c] > 1e29f) continue;
                double hv2 = erg[c];
                if (Double.isNaN(hv2)) nanV++;
                dh[zellen++] = Math.abs(hv2 - hG[c]);
                dqMax = Math.max(dqMax, Math.max(Math.abs(erg[n + c] - uG[c]), Math.abs(erg[2 * n + c] - vG[c])));
                qMax = Math.max(qMax, Math.max(Math.abs(uG[c]), Math.abs(vG[c])));
                volG += hG[c];
                volV += hv2;
            }
        double[] sortiert = Arrays.copyOf(dh, zellen);
        Arrays.sort(sortiert);
        double max = sortiert[zellen - 1], q999 = sortiert[(int) (0.999 * (zellen - 1))], median = sortiert[zellen / 2];
        double dvol = Math.abs(volV - volG) / volG;
        String werte = f("Tiefe größte %.1e m, 99,9 %% %.1e m, Median %.1e m; Durchfluss größte %.1e m²/s (von %.2f); Volumen %.1e; NaN %d",
                max, q999, median, dqMax, qMax, dvol, nanV);
        double[] drift = new double[staende.length];
        for (int k = 0; k < staende.length; k++)
            for (int j = 0; j < nz; j++)
                for (int i = 0; i < nx; i++) {
                    int c = (j + 2) * px + i + 2;
                    if (bed[c] <= 1e29f) drift[k] = Math.max(drift[k], Math.abs(hVs[k][c] - hGs[k][c]));
                }
        // Abstand benachbarter float-Werte bei der größten Tiefe (8–16 m: 9,5·10⁻⁷ m)
        double hMax = 0;
        for (int c = 0; c < n; c++) if (bed[c] <= 1e29f) hMax = Math.max(hMax, hG[c]);
        double ulp = Math.ulp((float) hMax);
        b.pruefe(drift[0] <= 1e-5, fall.name + ", ein Schritt (Kernel gleich)", f("größte %.1e m (%.1f float-Schritte bei %.1f m)", drift[0], drift[0] / ulp, hMax),
                "jede Zelle ≤ 1·10⁻⁵ m (Werkbuch)");
        StringBuilder d = new StringBuilder();
        for (int k = 0; k < staende.length; k++)
            d.append(k == 0 ? "" : " · ").append(staende[k]).append(f(": %.1e m (%.0f)", drift[k], drift[k] / ulp));
        b.info(fall.name + ", Drift in float", "größte Abweichung nach Schritten (in float-Schritten): " + d);
        // Entscheidung 11.11.2026 (Werkbuch 12.1): die Grenze 1·10⁻⁵ m gilt nach einem Schritt; nach vielen Schritten ist es
        // Rundungsdrift in float und wird nur festgehalten
        if (fall.nass) b.pruefe(nanV == 0, fall.name + f(", %d Schritte", fall.schritte), werte, "kein NaN; Abweichung ohne Grenze (Drift)");
        else b.pruefe(q999 <= 1e-5 && dvol <= 1e-6 && nanV == 0, fall.name + f(", %d Schritte", fall.schritte), werte, "99,9 % ≤ 1·10⁻⁵ m, Volumen ≤ 1·10⁻⁶ [G]");
        double zs = (double) nx * nz * fall.schritte;
        b.info("Zeit " + (fall.nass ? "nass" : "Watt"), f("Karte: Vulkan %.2f ns, OpenGL %.2f ns je Zellschritt (%.2f : 1); Wand: Vulkan %.0f ms (ein Abschicken), OpenGL %.0f ms (%d Schritte mit Rückfragen)",
                gpuVk * 1e6 / zs, gpuGl * 1e6 / zs, gpuGl / gpuVk, wandVk, wandGl, fall.schritte));
        if (fall.nass) b.info("Durchsatz HLL zweiter Ordnung (Vulkan)", f("%.2f·10⁸ Zellschritte/s (Werkbuch 11 nahm 2–3·10⁸ an, für das einfachere versetzte Verfahren)",
                zs / (gpuVk / 1e3) / 1e8));
    }

    private static int gruppen(int faeden) { return (faeden + 63) / 64; }
}
