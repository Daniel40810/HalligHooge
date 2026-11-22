package com.dan.hallighooge.p0;

import org.lwjgl.PointerBuffer;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.vulkan.*;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.BufferedReader;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.LongBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;

import static com.dan.hallighooge.p0.Bericht.f;
import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.system.MemoryUtil.*;
import static org.lwjgl.vulkan.KHRAccelerationStructure.*;
import static org.lwjgl.vulkan.KHRSynchronization2.VK_ACCESS_2_ACCELERATION_STRUCTURE_READ_BIT_KHR;
import static org.lwjgl.vulkan.KHRSynchronization2.VK_ACCESS_2_ACCELERATION_STRUCTURE_WRITE_BIT_KHR;
import static org.lwjgl.vulkan.KHRSynchronization2.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR;
import static org.lwjgl.vulkan.VK13.*;

/**
 * P0.4 (Werkbuch 12): Strahlabfrage über einer DGM1-Kachel (1 × 1 km zu 1 m, rund 2 Mio. Dreiecke). Gemessen werden der
 * Bau der Beschleunigungsstruktur (Zeit, Größe, verdichtet) und Strahlen pro Sekunde: zusammenhängend (Kamera 1920 × 1080
 * mit Schattenstrahl zur Sonne) und unzusammenhängend (zufällige Strahlen). Dazu ein Bild nach docs/status/P0_Strahl.png.
 * <p>
 * Kachel: {@code -Dp0.dgm1=<pfad.xyz>}; sonst die Kachel der Hanswarft im Ordner von {@code HALLIGHOOGE_DOWNLOAD} oder
 * {@code D:\Daten\HalligHooge}; fehlt sie, ein gerechnetes Gelände.
 */
public final class P0Strahl {
    private P0Strahl() {}

    static final int W = 1920, H = 1080, WARM = 5, MESS = 20;

    public static void main(String[] a) {
        Bericht b = new Bericht();
        messen(b);
        Path p = b.schreiben("P0_Strahl.md", "P0.4 – Strahlabfrage über einer DGM1-Kachel");
        System.out.println();
        System.out.println("Bericht: " + p);
        System.out.println(b.verstoesse() == 0 ? "Alles in Ordnung." : b.verstoesse() + " Verstöße.");
    }

    static void messen(Bericht b) {
        b.teil("P0.4 Strahlabfrage");
        float[] z;
        String quelle;
        try {
            Object[] k = kachel();
            z = (float[]) k[0];
            quelle = (String) k[1];
        } catch (IOException e) {
            b.fehler(e);
            return;
        }
        b.info("Gelände", quelle);
        try (Vulkan vk = new Vulkan(new Vulkan.Optionen())) {
            if (!b.pruefe(vk.strahlen, "Strahlabfrage eingeschaltet", Vulkan.version(vk.apiVersion) + ", " + vk.name, "ja")) return;
            lauf(vk, b, z);
        } catch (Throwable e) {
            b.fehler(e);
        }
    }

    private static void lauf(Vulkan vk, Bericht b, float[] hoehe) {
        final int n = 1000, nv = n * n, nt = 2 * (n - 1) * (n - 1);
        // Ecken (x Ost, y Nord, z oben; Ursprung Südwestecke der Kachel) und Dreiecke
        ByteBuffer ev = memAlloc(nv * 12), ei = memAlloc(nt * 12);
        float zmin = Float.MAX_VALUE, zmax = -Float.MAX_VALUE;
        for (int j = 0; j < n; j++)
            for (int i = 0; i < n; i++) {
                float h = hoehe[j * n + i];
                zmin = Math.min(zmin, h);
                zmax = Math.max(zmax, h);
                ev.putFloat(i + 0.5f).putFloat(j + 0.5f).putFloat(h);
            }
        ev.flip();
        for (int j = 0; j < n - 1; j++)
            for (int i = 0; i < n - 1; i++) {
                int a = j * n + i, bb = a + 1, c = a + n, d = c + 1;
                ei.putInt(a).putInt(bb).putInt(d);
                ei.putInt(a).putInt(d).putInt(c);
            }
        ei.flip();
        b.info("Dreiecke", f("%,d (%,d Ecken), Höhen %.2f … %.2f m", nt, nv, zmin, zmax));
        int eingabe = VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT
                | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
        try (MemoryStack s = stackPush();
             Puffer pv = Puffer.geraet(vk, ev.remaining(), eingabe);
             Puffer pi = Puffer.geraet(vk, ei.remaining(), eingabe)) {
            pv.schreiben(ev, 0);
            pi.schreiben(ei, 0);
            memFree(ev);
            memFree(ei);
            VkPhysicalDeviceAccelerationStructurePropertiesKHR pas = VkPhysicalDeviceAccelerationStructurePropertiesKHR.calloc(s).sType$Default();
            vkGetPhysicalDeviceProperties2(vk.phys, VkPhysicalDeviceProperties2.calloc(s).sType$Default().pNext(pas.address()));
            int ausrichtung = Math.max(1, pas.minAccelerationStructureScratchOffsetAlignment());

            // ---------------------------------------------------------- BLAS
            VkAccelerationStructureGeometryKHR.Buffer geo = VkAccelerationStructureGeometryKHR.calloc(1, s);
            geo.get(0).sType$Default().geometryType(VK_GEOMETRY_TYPE_TRIANGLES_KHR).flags(VK_GEOMETRY_OPAQUE_BIT_KHR);
            geo.get(0).geometry().triangles().sType$Default()
                    .vertexFormat(VK_FORMAT_R32G32B32_SFLOAT).vertexStride(12).maxVertex(nv - 1)
                    .indexType(VK_INDEX_TYPE_UINT32);
            geo.get(0).geometry().triangles().vertexData().deviceAddress(pv.adresse());
            geo.get(0).geometry().triangles().indexData().deviceAddress(pi.adresse());
            Gebaut blas = bauen(vk, s, geo, nt, VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR, ausrichtung, true);
            b.info("Bau BLAS (schnell verfolgen, verdichtbar)", f("%.1f ms auf der Karte", blas.ms));
            b.info("Größe BLAS", f("%s, verdichtet %s, Kratzspeicher %s", Vulkan.mb(blas.groesse), Vulkan.mb(blas.verdichtet), Vulkan.mb(blas.kratz)));

            // ---------------------------------------------------------- TLAS mit einer Instanz
            long blasAdr = vkGetAccelerationStructureDeviceAddressKHR(vk.device,
                    VkAccelerationStructureDeviceAddressInfoKHR.calloc(s).sType$Default().accelerationStructure(blas.as));
            VkAccelerationStructureInstanceKHR inst = VkAccelerationStructureInstanceKHR.calloc(s);
            inst.transform().matrix(0, 1f).matrix(5, 1f).matrix(10, 1f);
            inst.instanceCustomIndex(0).mask(0xFF).instanceShaderBindingTableRecordOffset(0)
                    .flags(VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR).accelerationStructureReference(blasAdr);
            try (Puffer pinst = Puffer.geraet(vk, VkAccelerationStructureInstanceKHR.SIZEOF, eingabe)) {
                pinst.schreiben(memByteBuffer(inst.address(), VkAccelerationStructureInstanceKHR.SIZEOF), 0);
                VkAccelerationStructureGeometryKHR.Buffer gi = VkAccelerationStructureGeometryKHR.calloc(1, s);
                gi.get(0).sType$Default().geometryType(VK_GEOMETRY_TYPE_INSTANCES_KHR).flags(VK_GEOMETRY_OPAQUE_BIT_KHR);
                gi.get(0).geometry().instances().sType$Default().arrayOfPointers(false);
                gi.get(0).geometry().instances().data().deviceAddress(pinst.adresse());
                Gebaut tlas = bauen(vk, s, gi, 1, VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR, ausrichtung, false);
                b.info("Bau TLAS", f("%.2f ms, %s", tlas.ms, Vulkan.mb(tlas.groesse)));
                try {
                    verfolgen(vk, b, tlas.as, pv, pi);
                } finally {
                    tlas.close(vk);
                    blas.close(vk);
                }
            }
        }
    }

    // ------------------------------------------------------------------ Bau

    static final class Gebaut {
        long as;
        Puffer speicher;
        long groesse, verdichtet, kratz;
        double ms;

        void close(Vulkan vk) {
            vkDestroyAccelerationStructureKHR(vk.device, as, null);
            speicher.close();
        }
    }

    private static Gebaut bauen(Vulkan vk, MemoryStack s, VkAccelerationStructureGeometryKHR.Buffer geo, int anzahl, int typ, int ausrichtung, boolean verdichten) {
        VkAccelerationStructureBuildGeometryInfoKHR.Buffer bi = VkAccelerationStructureBuildGeometryInfoKHR.calloc(1, s);
        bi.get(0).sType$Default().type(typ)
                .flags(VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR | (verdichten ? VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_COMPACTION_BIT_KHR : 0))
                .mode(VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR)
                .geometryCount(1).pGeometries(geo);
        VkAccelerationStructureBuildSizesInfoKHR gr = VkAccelerationStructureBuildSizesInfoKHR.calloc(s).sType$Default();
        vkGetAccelerationStructureBuildSizesKHR(vk.device, VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR, bi.get(0), s.ints(anzahl), gr);
        Gebaut g = new Gebaut();
        g.groesse = gr.accelerationStructureSize();
        g.kratz = gr.buildScratchSize();
        g.speicher = Puffer.geraet(vk, g.groesse, VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);
        LongBuffer lb = s.mallocLong(1);
        Vulkan.ok(vkCreateAccelerationStructureKHR(vk.device, VkAccelerationStructureCreateInfoKHR.calloc(s).sType$Default()
                .buffer(g.speicher.handle).size(g.groesse).type(typ), null, lb), "vkCreateAccelerationStructureKHR");
        g.as = lb.get(0);
        try (Puffer kratz = Puffer.geraet(vk, g.kratz + ausrichtung, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT)) {
            long adr = (kratz.adresse() + ausrichtung - 1) / ausrichtung * ausrichtung;
            bi.get(0).dstAccelerationStructure(g.as).scratchData().deviceAddress(adr);
            VkAccelerationStructureBuildRangeInfoKHR.Buffer ri = VkAccelerationStructureBuildRangeInfoKHR.calloc(1, s);
            ri.get(0).primitiveCount(anzahl).primitiveOffset(0).firstVertex(0).transformOffset(0);
            PointerBuffer pri = s.pointers(ri.address());
            long zeit = vk.zeitAbfragen(2);
            long gr2 = verdichten ? abfrage(vk, s) : VK_NULL_HANDLE;
            vk.einmal(c -> {
                vkCmdResetQueryPool(c, zeit, 0, 2);
                if (gr2 != VK_NULL_HANDLE) vkCmdResetQueryPool(c, gr2, 0, 1);
                vkCmdWriteTimestamp2(c, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, zeit, 0);
                vkCmdBuildAccelerationStructuresKHR(c, bi, pri);
                vkCmdWriteTimestamp2(c, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, zeit, 1);
                try (MemoryStack t = stackPush()) {
                    VkMemoryBarrier2.Buffer m = VkMemoryBarrier2.calloc(1, t);
                    m.get(0).sType$Default()
                            .srcStageMask(VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR).srcAccessMask(VK_ACCESS_2_ACCELERATION_STRUCTURE_WRITE_BIT_KHR)
                            .dstStageMask(VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR | VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT)
                            .dstAccessMask(VK_ACCESS_2_ACCELERATION_STRUCTURE_READ_BIT_KHR);
                    vkCmdPipelineBarrier2(c, VkDependencyInfo.calloc(t).sType$Default().pMemoryBarriers(m));
                    if (gr2 != VK_NULL_HANDLE)
                        vkCmdWriteAccelerationStructuresPropertiesKHR(c, t.longs(g.as), VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR, gr2, 0);
                }
            });
            double[] ts = vk.zeiten(zeit, 0, 2);
            g.ms = (ts[1] - ts[0]) / 1e6;
            vkDestroyQueryPool(vk.device, zeit, null);
            if (gr2 != VK_NULL_HANDLE) {
                LongBuffer v = s.mallocLong(1);
                Vulkan.ok(vkGetQueryPoolResults(vk.device, gr2, 0, 1, v, 8, VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT), "Verdichtete Größe");
                g.verdichtet = v.get(0);
                vkDestroyQueryPool(vk.device, gr2, null);
                verdichten(vk, s, g, typ);
            } else g.verdichtet = g.groesse;
        }
        return g;
    }

    private static long abfrage(Vulkan vk, MemoryStack s) {
        LongBuffer lb = s.mallocLong(1);
        Vulkan.ok(vkCreateQueryPool(vk.device, VkQueryPoolCreateInfo.calloc(s).sType$Default()
                .queryType(VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR).queryCount(1), null, lb), "vkCreateQueryPool (verdichtet)");
        return lb.get(0);
    }

    /** Ersetzt die Struktur durch ihre verdichtete Kopie. */
    private static void verdichten(Vulkan vk, MemoryStack s, Gebaut g, int typ) {
        Puffer neu = Puffer.geraet(vk, g.verdichtet, VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);
        LongBuffer lb = s.mallocLong(1);
        Vulkan.ok(vkCreateAccelerationStructureKHR(vk.device, VkAccelerationStructureCreateInfoKHR.calloc(s).sType$Default()
                .buffer(neu.handle).size(g.verdichtet).type(typ), null, lb), "vkCreateAccelerationStructureKHR (verdichtet)");
        long as = lb.get(0);
        vk.einmal(c -> {
            try (MemoryStack t = stackPush()) {
                vkCmdCopyAccelerationStructureKHR(c, VkCopyAccelerationStructureInfoKHR.calloc(t).sType$Default()
                        .src(g.as).dst(as).mode(VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR));
            }
        });
        g.close(vk);
        g.as = as;
        g.speicher = neu;
    }

    // ------------------------------------------------------------------ Verfolgen

    private static void verfolgen(Vulkan vk, Bericht b, long tlas, Puffer pv, Puffer pi) {
        Shader.Spirv sp = Shader.laden("/com/dan/hallighooge/p0/strahl.comp");
        int sb = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        try (Kernel k = new Kernel(vk, sp.code, new int[]{VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, sb, sb, sb, sb}, 80);
             Puffer bild = Puffer.speicher(vk, (long) W * H * 4);
             Puffer zaehler = Puffer.speicher(vk, 16);
             MemoryStack s = stackPush()) {
            long set = k.satz(tlas, bild.handle, zaehler.handle, pv.handle, pi.handle);
            // Kamera 450 m über der Kachel, steil nach Norden hinab: jeder Strahl trifft die Kachel (der erste Lauf blickte über den
            // Horizont, 34 % Treffer, und schönte die Zahl mit billigen Fehlstrahlen); Sonne tief aus Südwest
            double el = Math.toRadians(12), az = Math.toRadians(225);
            float[] sonne = {(float) (Math.cos(el) * Math.sin(az)), (float) (Math.cos(el) * Math.cos(az)), (float) Math.sin(el)};
            float[] auge = {500f, 420f, 450f}, ziel = {500f, 520f, 0f};
            float[] vor = {ziel[0] - auge[0], ziel[1] - auge[1], ziel[2] - auge[2]};
            String[] namen = {"zusammenhängend (Kamera 1920 × 1080, Schatten)", "unzusammenhängend (4 zufällige je Faden)"};
            for (int modus = 0; modus < 2; modus++) {
                final int m = modus;
                ByteBuffer pc = s.calloc(80);
                pc.putFloat(0, auge[0]).putFloat(4, auge[1]).putFloat(8, auge[2]).putFloat(12, (float) Math.tan(Math.toRadians(30)));
                pc.putFloat(16, vor[0]).putFloat(20, vor[1]).putFloat(24, vor[2]).putFloat(28, W / (float) H);
                pc.putFloat(32, sonne[0]).putFloat(36, sonne[1]).putFloat(40, sonne[2]).putFloat(44, 1f);
                pc.putInt(48, W).putInt(52, H).putInt(56, m).putInt(60, 0);
                pc.putFloat(64, 0f).putFloat(68, 0f).putFloat(72, 1000f).putFloat(76, 60f);
                long zeit = vk.zeitAbfragen(2 * MESS);
                vk.einmal(c -> {
                    for (int i = 0; i < WARM; i++) { pc.putInt(60, 1000 + i); k.aufnehmen(c, set, pc, W / 8, H / 8, 1); }
                    vkCmdFillBuffer(c, zaehler.handle, 0, VK_WHOLE_SIZE, 0);
                    Vulkan.sperre(c);
                    vkCmdResetQueryPool(c, zeit, 0, 2 * MESS);
                    for (int i = 0; i < MESS; i++) {
                        pc.putInt(60, i);
                        vkCmdWriteTimestamp2(c, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, zeit, 2 * i);
                        k.aufnehmen(c, set, pc, W / 8, H / 8, 1);
                        vkCmdWriteTimestamp2(c, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, zeit, 2 * i + 1);
                    }
                });
                double[] ts = vk.zeiten(zeit, 0, 2 * MESS);
                vkDestroyQueryPool(vk.device, zeit, null);
                double[] d = new double[MESS];
                for (int i = 0; i < MESS; i++) d[i] = (ts[2 * i + 1] - ts[2 * i]) / 1e6;
                Arrays.sort(d);
                double median = d[MESS / 2];
                int[] z = zaehler.ints(4);
                long strahlen = m == 0 ? (long) W * H + (z[1] & 0xffffffffL) / MESS : 4L * W * H;
                double mrs = strahlen / (median / 1e3) / 1e6;
                if (m == 0) {
                    b.pruefe(z[0] != 0, "Treffer " + namen[m], f("%.0f %% der Bildpunkte", 100.0 * (z[0] & 0xffffffffL) / MESS / W / H), "> 0");
                    b.info("Strahlen " + namen[m], f("%.0f Mio./s (%.2f ms je Bild, %,d Strahlen, %.0f %% Treffer, %.0f %% im Schatten)",
                            mrs, median, strahlen, 100.0 * (z[0] & 0xffffffffL) / MESS / W / H,
                            z[1] == 0 ? 0 : 100.0 * (z[2] & 0xffffffffL) / (z[1] & 0xffffffffL)));
                    bildSchreiben(bild.ints(W * H));
                } else {
                    b.info("Strahlen " + namen[m], f("%.0f Mio./s (%.2f ms je Durchgang, %,d Strahlen, %.0f %% Treffer)",
                            mrs, median, strahlen, 100.0 * (z[3] & 0xffffffffL) / MESS / strahlen));
                }
            }
        } finally {
            sp.frei();
        }
    }

    private static void bildSchreiben(int[] px) {
        BufferedImage img = new BufferedImage(W, H, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                int v = px[y * W + x];
                int rgb;
                if ((v & 0x100) == 0) {
                    double t = y / (double) H;
                    rgb = ((int) (150 + 60 * t) << 16) | ((int) (180 + 50 * t) << 8) | (int) (215 + 30 * t);
                } else {
                    int g = v & 0xff;
                    rgb = ((int) (g * 0.92) << 16) | ((int) (g * 0.95) << 8) | g;
                }
                img.setRGB(x, y, rgb);
            }
        try {
            Path p = Path.of("docs", "status", "P0_Strahl.png");
            Files.createDirectories(p.getParent());
            ImageIO.write(img, "png", p.toFile());
        } catch (IOException e) {
            System.out.println("  (Bild nicht geschrieben: " + e.getMessage() + ")");
        }
    }

    // ------------------------------------------------------------------ Kachel

    /** {Höhen 1000 × 1000 (Zeile j = Nord-Index von Süden), Quelle}. */
    static Object[] kachel() throws IOException {
        Path p = null;
        String vorgabe = System.getProperty("p0.dgm1");
        if (vorgabe != null) p = Path.of(vorgabe);
        else {
            String basis = System.getenv().getOrDefault("HALLIGHOOGE_DOWNLOAD", "D:\\Daten\\HalligHooge");
            Path k = Path.of(basis, "hoehe", "dgm1", "dgm1_32_470_6047_1_sh_2024.xyz");
            if (Files.exists(k)) p = k;
        }
        float[] z = new float[1000 * 1000];
        if (p == null || !Files.exists(p)) {
            for (int j = 0; j < 1000; j++)
                for (int i = 0; i < 1000; i++)
                    z[j * 1000 + i] = (float) (1.2 + 0.8 * Math.sin(i / 37.0) * Math.cos(j / 53.0)
                            + 3.5 * Math.exp(-((i - 500) * (i - 500) + (j - 520) * (j - 520)) / 900.0));
            return new Object[]{z, "gerechnet (keine DGM1-Kachel gefunden; -Dp0.dgm1=<datei.xyz>)"};
        }
        Arrays.fill(z, Float.NaN);
        long t0 = System.nanoTime();
        double e0 = Double.NaN, n0 = Double.NaN;
        int punkte = 0;
        try (BufferedReader r = Files.newBufferedReader(p, StandardCharsets.US_ASCII)) {
            String zeile;
            while ((zeile = r.readLine()) != null) {
                String[] t = zeile.trim().split("[\\s,;]+");
                if (t.length < 3) continue;
                double x = Double.parseDouble(t[0]), y = Double.parseDouble(t[1]);
                float h = Float.parseFloat(t[2]);
                if (Double.isNaN(e0)) {
                    e0 = Math.floor(x / 1000) * 1000;
                    n0 = Math.floor(y / 1000) * 1000;
                }
                int i = (int) Math.floor(x - e0), j = (int) Math.floor(y - n0);
                if (i < 0 || i >= 1000 || j < 0 || j >= 1000) continue;
                z[j * 1000 + i] = h;
                punkte++;
            }
        }
        int luecken = 0;
        float mittel = 0;
        for (float v : z) if (!Float.isNaN(v)) mittel += v;
        mittel /= Math.max(1, punkte);
        for (int c = 0; c < z.length; c++) if (Float.isNaN(z[c])) { z[c] = mittel; luecken++; }
        return new Object[]{z, f("%s (%,d Punkte, %d Lücken gefüllt, gelesen in %.1f s)", p.getFileName(), punkte, luecken, (System.nanoTime() - t0) / 1e9)};
    }
}
