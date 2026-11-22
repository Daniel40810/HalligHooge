package com.dan.hallighooge.p0;

import com.dan.fcombobox.FComboBox;
import com.dan.fframe.FFrame;
import com.dan.fslider.FSlider;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.jawt.JAWT;
import org.lwjgl.system.jawt.JAWTDrawingSurface;
import org.lwjgl.system.jawt.JAWTDrawingSurfaceInfo;
import org.lwjgl.system.jawt.JAWTWin32DrawingSurfaceInfo;
import org.lwjgl.system.windows.WinBase;
import org.lwjgl.vulkan.*;

import javax.swing.*;
import java.awt.*;
import java.awt.event.ComponentAdapter;
import java.awt.event.ComponentEvent;
import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;
import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.nio.LongBuffer;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static com.dan.hallighooge.p0.Bericht.f;
import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.system.MemoryUtil.NULL;
import static org.lwjgl.system.jawt.JAWTFunctions.*;
import static org.lwjgl.vulkan.KHRSurface.*;
import static org.lwjgl.vulkan.KHRSwapchain.*;
import static org.lwjgl.vulkan.KHRWin32Surface.vkCreateWin32SurfaceKHR;
import static org.lwjgl.vulkan.VK13.*;

/**
 * P0.2 (Werkbuch 12, F8): eine Vulkan-Fläche im FFrame. Ein schwergewichtiges AWT-{@link Canvas} liefert über JAWT sein
 * Fenster-Handle, daraus wird eine Win32-Fläche mit Swapchain; gezeichnet wird mit dynamischem Rendern in einem eigenen
 * Faden. Gemessen: Bilder pro Sekunde je Darstellungsart (FIFO = Bildsynchron, MAILBOX, IMMEDIATE), Zeit je Bild auf
 * Prozessor und Karte, Neuaufbau der Swapchain beim Ändern der Größe. Beim Schließen nach docs/status/P0_Flaeche.md.
 */
public final class P0Flaeche {
    static final Color BG = new Color(11, 17, 24), TEXT = new Color(230, 234, 238), LEISE = new Color(150, 160, 172);
    static final int BILDER = 2;   // Bilder in Arbeit

    // Bedienung → Zeichenfaden
    private volatile boolean laeuft = true, neuBauen;
    private volatile int wunschModus = VK_PRESENT_MODE_FIFO_KHR, last;
    // Zeichenfaden → Anzeige
    private volatile String status = "startet …";
    private volatile List<Integer> modi = List.of();
    private final Map<String, Double> bestFps = new LinkedHashMap<>();
    private final Bericht bericht = new Bericht();
    private volatile Throwable fehler;
    private Thread faden;
    private boolean geschrieben;

    /** Leinwand ohne eigenes Malen (Vulkan zeichnet). */
    static final class Leinwand extends Canvas {
        Leinwand() { setBackground(BG); setIgnoreRepaint(true); }
        @Override public void paint(Graphics g) {}
        @Override public void update(Graphics g) {}
    }

    public static void main(String[] a) {
        System.setProperty("sun.awt.noerasebackground", "true");
        SwingUtilities.invokeLater(() -> new P0Flaeche().oeffnen());
    }

    private void oeffnen() {
        Leinwand lw = new Leinwand();
        lw.setPreferredSize(new Dimension(1280, 720));
        FFrame f = new FFrame("P0.2 · Vulkan-Fläche im FFrame");
        JPanel root = f.getComponentPane();
        root.setLayout(new BorderLayout(10, 10));
        root.setBackground(BG);
        root.setBorder(BorderFactory.createEmptyBorder(10, 10, 10, 10));
        root.add(lw, BorderLayout.CENTER);

        FComboBox modus = new FComboBox(new Object[]{"FIFO (bildsynchron)", "MAILBOX", "IMMEDIATE", "FIFO_RELAXED"});
        int[] modusWert = {VK_PRESENT_MODE_FIFO_KHR, VK_PRESENT_MODE_MAILBOX_KHR, VK_PRESENT_MODE_IMMEDIATE_KHR, VK_PRESENT_MODE_FIFO_RELAXED_KHR};
        modus.addActionListener(e -> { wunschModus = modusWert[modus.getSelectedIndex()]; neuBauen = true; });
        FSlider lastRegler = new FSlider(0, 400, 0);
        lastRegler.addChangeListener(e -> last = lastRegler.getValue());
        JLabel lStatus = label(""), lModi = label("");
        lStatus.setForeground(TEXT);
        lModi.setForeground(LEISE);
        JPanel zeile1 = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        zeile1.setBackground(BG);
        zeile1.add(label("Darstellung"));
        zeile1.add(modus);
        zeile1.add(label("   Last (Wellen)"));
        zeile1.add(lastRegler);
        zeile1.add(lModi);
        JPanel south = new JPanel(new GridLayout(2, 1, 0, 4));
        south.setBackground(BG);
        south.add(zeile1);
        south.add(lStatus);
        root.add(south, BorderLayout.SOUTH);
        // deckend: ein schwergewichtiges Canvas in einem durchsichtigen Fenster bleibt unter Windows leer (wie GLCanvas)
        f.setBackground(BG);
        f.setPreferredFrameSize(new Dimension(1340, 860));
        lw.addComponentListener(new ComponentAdapter() {
            @Override public void componentResized(ComponentEvent e) { neuBauen = true; }
        });
        f.addWindowListener(new WindowAdapter() {
            @Override public void windowClosing(WindowEvent e) { beenden(); }
        });
        Runtime.getRuntime().addShutdownHook(new Thread(this::beenden, "p0-flaeche-ende"));
        f.setVisible(true);
        // erst wenn das Fenster steht: dann hat das Canvas sein natives Fenster
        SwingUtilities.invokeLater(() -> starten(lw, lStatus, lModi));
    }

    private void starten(Leinwand lw, JLabel lStatus, JLabel lModi) {
        long hwnd;
        try {
            hwnd = hwnd(lw);
        } catch (Throwable e) {
            bericht.teil("P0.2 Vulkan-Fläche im FFrame");
            bericht.fehler(e);
            lStatus.setText("Kein Fenster-Handle: " + e.getMessage());
            return;
        }
        faden = new Thread(() -> zeichnen(hwnd), "p0-vulkan");
        faden.start();
        new Timer(500, e -> {
            lStatus.setText(status);
            StringBuilder b = new StringBuilder();
            for (int m : modi) b.append(b.length() == 0 ? "angeboten: " : ", ").append(modusName(m));
            lModi.setText(b.toString());
        }).start();
    }

    private synchronized void beenden() {
        laeuft = false;
        if (faden != null && faden != Thread.currentThread()) {
            try { faden.join(3000); } catch (InterruptedException ignored) {}
        }
        if (geschrieben) return;
        geschrieben = true;
        if (bericht.zeilen.isEmpty()) bericht.teil("P0.2 Vulkan-Fläche im FFrame");
        for (Map.Entry<String, Double> e : bestFps.entrySet()) bericht.info("höchste Bilder/s " + e.getKey(), f("%.1f", e.getValue()));
        if (fehler != null) bericht.fehler(fehler);
        Path p = bericht.schreiben("P0_Flaeche.md", "P0.2 – Vulkan-Fläche im FFrame");
        System.out.println("Bericht: " + p);
    }

    // ------------------------------------------------------------------ Fenster-Handle über JAWT

    static long hwnd(Canvas c) {
        try (MemoryStack s = stackPush()) {
            JAWT awt = JAWT.calloc(s).version(JAWT_VERSION_1_4);
            if (!JAWT_GetAWT(awt)) throw new IllegalStateException("JAWT nicht verfügbar");
            JAWTDrawingSurface ds = JAWT_GetDrawingSurface(c, awt.GetDrawingSurface());
            if (ds == null) throw new IllegalStateException("JAWT: keine Zeichenfläche");
            try {
                int lock = JAWT_DrawingSurface_Lock(ds, ds.Lock());
                if ((lock & JAWT_LOCK_ERROR) != 0) throw new IllegalStateException("JAWT: Zeichenfläche lässt sich nicht sperren");
                try {
                    JAWTDrawingSurfaceInfo dsi = JAWT_DrawingSurface_GetDrawingSurfaceInfo(ds, ds.GetDrawingSurfaceInfo());
                    if (dsi == null) throw new IllegalStateException("JAWT: keine Angaben zur Zeichenfläche");
                    try {
                        return JAWTWin32DrawingSurfaceInfo.create(dsi.platformInfo()).hwnd();
                    } finally {
                        JAWT_DrawingSurface_FreeDrawingSurfaceInfo(dsi, ds.FreeDrawingSurfaceInfo());
                    }
                } finally {
                    JAWT_DrawingSurface_Unlock(ds, ds.Unlock());
                }
            } finally {
                JAWT_FreeDrawingSurface(ds, awt.FreeDrawingSurface());
            }
        }
    }

    // ------------------------------------------------------------------ Zeichenfaden

    /** Swapchain samt Bildansichten und je Bild einem Semaphor „fertig“. */
    private static final class Kette {
        long handle;
        int format, breite, hoehe, modus;
        long[] bilder, ansichten, fertig;
    }

    private void zeichnen(long hwnd) {
        Bericht b = bericht;
        b.teil("P0.2 Vulkan-Fläche im FFrame");
        Vulkan.Optionen o = new Vulkan.Optionen();
        o.flaeche = true;
        o.strahlen = false;
        Vulkan vk = null;
        long flaeche = NULL;
        Kette k = null;
        long layout = NULL, pipeline = NULL, abfragen = NULL;
        long[] bereit = new long[BILDER], zaeune = new long[BILDER];
        VkCommandBuffer[] cmd = new VkCommandBuffer[BILDER];
        try (MemoryStack s0 = stackPush()) {
            vk = new Vulkan(o);
            b.info("Gerät", vk.name);
            LongBuffer lb = s0.mallocLong(1);
            VkWin32SurfaceCreateInfoKHR sci = VkWin32SurfaceCreateInfoKHR.calloc(s0).sType$Default()
                    .hinstance(WinBase.nGetModuleHandle(NULL, NULL)).hwnd(hwnd);
            Vulkan.ok(vkCreateWin32SurfaceKHR(vk.instance, sci, null, lb), "vkCreateWin32SurfaceKHR");
            flaeche = lb.get(0);
            IntBuffer ib = s0.mallocInt(1);
            vkGetPhysicalDeviceSurfaceSupportKHR(vk.phys, vk.familieAlle, flaeche, ib);
            if (!b.pruefe(ib.get(0) == VK_TRUE, "Fläche aus dem Fenster-Handle des Canvas", f("HWND 0x%x, Familie %d kann darstellen", hwnd, vk.familieAlle), "darstellbar")) return;
            modi = darstellungsArten(vk, flaeche);
            List<String> mn = new ArrayList<>();
            for (int m : modi) mn.add(modusName(m));
            b.info("Darstellungsarten", String.join(", ", mn));

            k = kette(vk, flaeche, null, wunschModus);
            b.info("Format", f("%d (%s), %d Bilder", k.format, k.format == VK_FORMAT_B8G8R8A8_SRGB ? "BGRA8 sRGB" : "anderes", k.bilder.length));
            // Pipeline
            Shader.Spirv sv = Shader.laden("/com/dan/hallighooge/p0/flaeche.vert"), sf = Shader.laden("/com/dan/hallighooge/p0/flaeche.frag");
            long mv = modul(vk, sv.code), mf = modul(vk, sf.code);
            sv.frei();
            sf.frei();
            VkPipelineLayoutCreateInfo li = VkPipelineLayoutCreateInfo.calloc(s0).sType$Default()
                    .pPushConstantRanges(VkPushConstantRange.calloc(1, s0).stageFlags(VK_SHADER_STAGE_FRAGMENT_BIT).offset(0).size(16));
            Vulkan.ok(vkCreatePipelineLayout(vk.device, li, null, lb), "vkCreatePipelineLayout");
            layout = lb.get(0);
            pipeline = pipeline(vk, layout, mv, mf, k.format);
            vkDestroyShaderModule(vk.device, mv, null);
            vkDestroyShaderModule(vk.device, mf, null);
            abfragen = vk.zeitAbfragen(2 * BILDER);
            for (int i = 0; i < BILDER; i++) {
                bereit[i] = vk.semaphor();
                zaeune[i] = vk.zaun(true);
                cmd[i] = vk.befehle(vk.pool);
            }
            boolean[] gemessen = new boolean[BILDER];
            int bild = 0, neu = 0, bilderSek = 0;
            double neuMs = 0, cpuSumme = 0, gpuSumme = 0, gpuLetzt = 0;
            long t0 = System.nanoTime(), sek = t0;
            b.pruefe(true, "Swapchain", f("%d × %d, %s", k.breite, k.hoehe, modusName(k.modus)), "angelegt");

            while (laeuft) {
                if (neuBauen) {
                    neuBauen = false;
                    long n0 = System.nanoTime();
                    vkDeviceWaitIdle(vk.device);
                    Kette alt = k;
                    k = kette(vk, flaeche, alt, modi.contains(wunschModus) ? wunschModus : VK_PRESENT_MODE_FIFO_KHR);
                    weg(vk, alt);
                    neuMs = (System.nanoTime() - n0) / 1e6;
                    neu++;
                    bilderSek = 0;
                    cpuSumme = gpuSumme = 0;
                    sek = System.nanoTime();
                }
                if (k.breite == 0 || k.hoehe == 0) {   // klein gemacht
                    Thread.sleep(50);
                    neuBauen = true;
                    continue;
                }
                int f = bild % BILDER;
                try (MemoryStack s = stackPush()) {
                    Vulkan.ok(vkWaitForFences(vk.device, zaeune[f], true, Long.MAX_VALUE), "vkWaitForFences");
                    if (gemessen[f]) {
                        double[] ts = vk.zeiten(abfragen, 2 * f, 2);
                        gpuLetzt = (ts[1] - ts[0]) / 1e6;
                    }
                    long c0 = System.nanoTime();
                    IntBuffer idx = s.mallocInt(1);
                    int r = vkAcquireNextImageKHR(vk.device, k.handle, Long.MAX_VALUE, bereit[f], VK_NULL_HANDLE, idx);
                    if (r == VK_ERROR_OUT_OF_DATE_KHR) { neuBauen = true; continue; }
                    if (r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR) Vulkan.ok(r, "vkAcquireNextImageKHR");
                    int i = idx.get(0);
                    vkResetFences(vk.device, zaeune[f]);
                    VkCommandBuffer c = cmd[f];
                    vkResetCommandBuffer(c, 0);
                    Vulkan.beginne(c, true);
                    vkCmdResetQueryPool(c, abfragen, 2 * f, 2);
                    vkCmdWriteTimestamp2(c, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, abfragen, 2 * f);
                    uebergang(c, s, k.bilder[i], VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                            VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 0,
                            VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
                    VkRenderingAttachmentInfo.Buffer ca = VkRenderingAttachmentInfo.calloc(1, s);
                    ca.get(0).sType$Default().imageView(k.ansichten[i]).imageLayout(VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
                            .loadOp(VK_ATTACHMENT_LOAD_OP_DONT_CARE).storeOp(VK_ATTACHMENT_STORE_OP_STORE);
                    VkRenderingInfo ri = VkRenderingInfo.calloc(s).sType$Default().layerCount(1).pColorAttachments(ca);
                    ri.renderArea().offset().set(0, 0);
                    ri.renderArea().extent().set(k.breite, k.hoehe);
                    vkCmdBeginRendering(c, ri);
                    vkCmdBindPipeline(c, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
                    vkCmdSetViewport(c, 0, VkViewport.calloc(1, s).x(0).y(0).width(k.breite).height(k.hoehe).minDepth(0).maxDepth(1));
                    VkRect2D.Buffer sc = VkRect2D.calloc(1, s);
                    sc.get(0).extent().set(k.breite, k.hoehe);
                    vkCmdSetScissor(c, 0, sc);
                    ByteBuffer pc = s.malloc(16);
                    pc.putFloat(0, (float) ((System.nanoTime() - t0) / 1e9)).putFloat(4, k.breite).putFloat(8, k.hoehe).putFloat(12, last);
                    vkCmdPushConstants(c, layout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, pc);
                    vkCmdDraw(c, 3, 1, 0, 0);
                    vkCmdEndRendering(c);
                    uebergang(c, s, k.bilder[i], VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                            VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                            VK_PIPELINE_STAGE_2_NONE, 0);
                    vkCmdWriteTimestamp2(c, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, abfragen, 2 * f + 1);
                    Vulkan.ok(vkEndCommandBuffer(c), "vkEndCommandBuffer");

                    VkSubmitInfo2.Buffer si = VkSubmitInfo2.calloc(1, s);
                    si.get(0).sType$Default()
                            .pWaitSemaphoreInfos(VkSemaphoreSubmitInfo.calloc(1, s).sType$Default().semaphore(bereit[f])
                                    .stageMask(VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT))
                            .pCommandBufferInfos(VkCommandBufferSubmitInfo.calloc(1, s).sType$Default().commandBuffer(c))
                            .pSignalSemaphoreInfos(VkSemaphoreSubmitInfo.calloc(1, s).sType$Default().semaphore(k.fertig[i])
                                    .stageMask(VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT));
                    Vulkan.ok(vkQueueSubmit2(vk.queue, si, zaeune[f]), "vkQueueSubmit2");
                    gemessen[f] = true;
                    VkPresentInfoKHR pi = VkPresentInfoKHR.calloc(s).sType$Default()
                            .pWaitSemaphores(s.longs(k.fertig[i])).swapchainCount(1).pSwapchains(s.longs(k.handle)).pImageIndices(s.ints(i));
                    r = vkQueuePresentKHR(vk.queue, pi);
                    if (r == VK_ERROR_OUT_OF_DATE_KHR || r == VK_SUBOPTIMAL_KHR) neuBauen = true;
                    else Vulkan.ok(r, "vkQueuePresentKHR");
                    cpuSumme += (System.nanoTime() - c0) / 1e6;
                    gpuSumme += gpuLetzt;
                }
                bild++;
                bilderSek++;
                long jetzt = System.nanoTime();
                if (jetzt - sek >= 1_000_000_000L) {
                    double fps = bilderSek / ((jetzt - sek) / 1e9);
                    String art = modusName(k.modus) + (last > 0 ? f(" + Last %d", last) : "");
                    if (last == 0) bestFps.merge(modusName(k.modus) + f(" (%d × %d)", k.breite, k.hoehe), fps, Math::max);
                    status = f("%d × %d · %s · %.1f Bilder/s · Bild %.2f ms (Prozessor %.2f ms, Karte %.2f ms) · Neuaufbau %d× (zuletzt %.1f ms)",
                            k.breite, k.hoehe, art, fps, 1000 / fps, cpuSumme / bilderSek, gpuSumme / bilderSek, neu, neuMs);
                    bilderSek = 0;
                    cpuSumme = gpuSumme = 0;
                    sek = jetzt;
                }
            }
            b.pruefe(neu > 0, "Größe geändert, Swapchain neu", f("%d× , zuletzt %.1f ms", neu, neuMs), "mindestens einmal (Fenster ziehen)");
            Double fifo = null;
            for (Map.Entry<String, Double> e : bestFps.entrySet()) if (e.getKey().startsWith("FIFO (")) fifo = fifo == null ? e.getValue() : Math.max(fifo, e.getValue());
            b.pruefe(fifo != null && fifo >= 59, "bildsynchron (FIFO)", fifo == null ? "nicht gemessen" : f("%.1f Bilder/s", fifo), "≥ 59 (60 Hz)");
            b.info("Fehler der Validierung", vk.validierung ? String.valueOf(vk.validierungsFehler) : "nicht eingeschaltet");
        } catch (Throwable e) {
            fehler = e;
            status = "Fehler: " + e.getMessage();
            e.printStackTrace();
        } finally {
            if (vk != null) {
                vkDeviceWaitIdle(vk.device);
                for (int i = 0; i < BILDER; i++) {
                    if (bereit[i] != NULL) vkDestroySemaphore(vk.device, bereit[i], null);
                    if (zaeune[i] != NULL) vkDestroyFence(vk.device, zaeune[i], null);
                }
                if (abfragen != NULL) vkDestroyQueryPool(vk.device, abfragen, null);
                if (pipeline != NULL) vkDestroyPipeline(vk.device, pipeline, null);
                if (layout != NULL) vkDestroyPipelineLayout(vk.device, layout, null);
                if (k != null) weg(vk, k);
                if (flaeche != NULL) vkDestroySurfaceKHR(vk.instance, flaeche, null);
                vk.close();
            }
        }
    }

    // ------------------------------------------------------------------ Swapchain

    private static List<Integer> darstellungsArten(Vulkan vk, long flaeche) {
        try (MemoryStack s = stackPush()) {
            IntBuffer n = s.mallocInt(1);
            vkGetPhysicalDeviceSurfacePresentModesKHR(vk.phys, flaeche, n, null);
            IntBuffer m = s.mallocInt(n.get(0));
            vkGetPhysicalDeviceSurfacePresentModesKHR(vk.phys, flaeche, n, m);
            List<Integer> out = new ArrayList<>();
            for (int i = 0; i < m.capacity(); i++) out.add(m.get(i));
            return out;
        }
    }

    private static Kette kette(Vulkan vk, long flaeche, Kette alt, int modus) {
        try (MemoryStack s = stackPush()) {
            VkSurfaceCapabilitiesKHR cap = VkSurfaceCapabilitiesKHR.malloc(s);
            Vulkan.ok(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk.phys, flaeche, cap), "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
            Kette k = new Kette();
            k.modus = modus;
            // Format: BGRA8 sRGB, sonst das erste
            IntBuffer n = s.mallocInt(1);
            vkGetPhysicalDeviceSurfaceFormatsKHR(vk.phys, flaeche, n, null);
            VkSurfaceFormatKHR.Buffer fm = VkSurfaceFormatKHR.malloc(n.get(0), s);
            vkGetPhysicalDeviceSurfaceFormatsKHR(vk.phys, flaeche, n, fm);
            int format = fm.get(0).format(), raum = fm.get(0).colorSpace();
            for (int i = 0; i < fm.capacity(); i++)
                if (fm.get(i).format() == VK_FORMAT_B8G8R8A8_SRGB && fm.get(i).colorSpace() == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) { format = VK_FORMAT_B8G8R8A8_SRGB; raum = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR; }
            if (alt != null) format = alt.format;     // die Pipeline kennt das Format
            k.format = format;
            k.breite = cap.currentExtent().width();
            k.hoehe = cap.currentExtent().height();
            if (k.breite == 0xFFFFFFFF) { k.breite = 1280; k.hoehe = 720; }
            if (k.breite == 0 || k.hoehe == 0) {
                k.bilder = k.ansichten = k.fertig = new long[0];
                return k;
            }
            int anzahl = Math.max(cap.minImageCount() + 1, 3);
            if (cap.maxImageCount() > 0) anzahl = Math.min(anzahl, cap.maxImageCount());
            VkSwapchainCreateInfoKHR ci = VkSwapchainCreateInfoKHR.calloc(s).sType$Default()
                    .surface(flaeche).minImageCount(anzahl).imageFormat(format).imageColorSpace(raum)
                    .imageArrayLayers(1).imageUsage(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT)
                    .imageSharingMode(VK_SHARING_MODE_EXCLUSIVE).preTransform(cap.currentTransform())
                    .compositeAlpha(VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR).presentMode(modus).clipped(true)
                    .oldSwapchain(alt != null ? alt.handle : VK_NULL_HANDLE);
            ci.imageExtent().set(k.breite, k.hoehe);
            LongBuffer lb = s.mallocLong(1);
            Vulkan.ok(vkCreateSwapchainKHR(vk.device, ci, null, lb), "vkCreateSwapchainKHR");
            k.handle = lb.get(0);
            vkGetSwapchainImagesKHR(vk.device, k.handle, n, null);
            LongBuffer bl = s.mallocLong(n.get(0));
            vkGetSwapchainImagesKHR(vk.device, k.handle, n, bl);
            k.bilder = new long[bl.capacity()];
            k.ansichten = new long[bl.capacity()];
            k.fertig = new long[bl.capacity()];
            for (int i = 0; i < k.bilder.length; i++) {
                k.bilder[i] = bl.get(i);
                VkImageViewCreateInfo vi = VkImageViewCreateInfo.calloc(s).sType$Default().image(k.bilder[i])
                        .viewType(VK_IMAGE_VIEW_TYPE_2D).format(format);
                vi.subresourceRange().aspectMask(VK_IMAGE_ASPECT_COLOR_BIT).baseMipLevel(0).levelCount(1).baseArrayLayer(0).layerCount(1);
                Vulkan.ok(vkCreateImageView(vk.device, vi, null, lb), "vkCreateImageView");
                k.ansichten[i] = lb.get(0);
                k.fertig[i] = vk.semaphor();
            }
            return k;
        }
    }

    private static void weg(Vulkan vk, Kette k) {
        for (long v : k.ansichten) vkDestroyImageView(vk.device, v, null);
        for (long f : k.fertig) vkDestroySemaphore(vk.device, f, null);
        if (k.handle != VK_NULL_HANDLE) vkDestroySwapchainKHR(vk.device, k.handle, null);
    }

    // ------------------------------------------------------------------ Pipeline

    private static long modul(Vulkan vk, ByteBuffer code) {
        try (MemoryStack s = stackPush()) {
            LongBuffer lb = s.mallocLong(1);
            Vulkan.ok(vkCreateShaderModule(vk.device, VkShaderModuleCreateInfo.calloc(s).sType$Default().pCode(code), null, lb), "vkCreateShaderModule");
            return lb.get(0);
        }
    }

    private static long pipeline(Vulkan vk, long layout, long mv, long mf, int format) {
        try (MemoryStack s = stackPush()) {
            VkPipelineShaderStageCreateInfo.Buffer st = VkPipelineShaderStageCreateInfo.calloc(2, s);
            st.get(0).sType$Default().stage(VK_SHADER_STAGE_VERTEX_BIT).module(mv).pName(s.UTF8("main"));
            st.get(1).sType$Default().stage(VK_SHADER_STAGE_FRAGMENT_BIT).module(mf).pName(s.UTF8("main"));
            VkPipelineColorBlendAttachmentState.Buffer blend = VkPipelineColorBlendAttachmentState.calloc(1, s);
            blend.get(0).colorWriteMask(VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT);
            VkPipelineRenderingCreateInfo rci = VkPipelineRenderingCreateInfo.calloc(s).sType$Default()
                    .colorAttachmentCount(1).pColorAttachmentFormats(s.ints(format));
            VkGraphicsPipelineCreateInfo.Buffer gp = VkGraphicsPipelineCreateInfo.calloc(1, s);
            gp.get(0).sType$Default()
                    .pNext(rci.address())
                    .pStages(st)
                    .pVertexInputState(VkPipelineVertexInputStateCreateInfo.calloc(s).sType$Default())
                    .pInputAssemblyState(VkPipelineInputAssemblyStateCreateInfo.calloc(s).sType$Default().topology(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST))
                    .pViewportState(VkPipelineViewportStateCreateInfo.calloc(s).sType$Default().viewportCount(1).scissorCount(1))
                    .pRasterizationState(VkPipelineRasterizationStateCreateInfo.calloc(s).sType$Default()
                            .polygonMode(VK_POLYGON_MODE_FILL).cullMode(VK_CULL_MODE_NONE).frontFace(VK_FRONT_FACE_COUNTER_CLOCKWISE).lineWidth(1f))
                    .pMultisampleState(VkPipelineMultisampleStateCreateInfo.calloc(s).sType$Default().rasterizationSamples(VK_SAMPLE_COUNT_1_BIT))
                    .pColorBlendState(VkPipelineColorBlendStateCreateInfo.calloc(s).sType$Default().pAttachments(blend))
                    .pDynamicState(VkPipelineDynamicStateCreateInfo.calloc(s).sType$Default().pDynamicStates(s.ints(VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR)))
                    .layout(layout);
            LongBuffer lb = s.mallocLong(1);
            Vulkan.ok(vkCreateGraphicsPipelines(vk.device, VK_NULL_HANDLE, gp, null, lb), "vkCreateGraphicsPipelines");
            return lb.get(0);
        }
    }

    private static void uebergang(VkCommandBuffer c, MemoryStack s, long bild, int von, int nach, long srcStage, long srcAccess, long dstStage, long dstAccess) {
        VkImageMemoryBarrier2.Buffer ib = VkImageMemoryBarrier2.calloc(1, s);
        ib.get(0).sType$Default().srcStageMask(srcStage).srcAccessMask(srcAccess).dstStageMask(dstStage).dstAccessMask(dstAccess)
                .oldLayout(von).newLayout(nach).srcQueueFamilyIndex(VK_QUEUE_FAMILY_IGNORED).dstQueueFamilyIndex(VK_QUEUE_FAMILY_IGNORED).image(bild);
        ib.get(0).subresourceRange().aspectMask(VK_IMAGE_ASPECT_COLOR_BIT).baseMipLevel(0).levelCount(1).baseArrayLayer(0).layerCount(1);
        vkCmdPipelineBarrier2(c, VkDependencyInfo.calloc(s).sType$Default().pImageMemoryBarriers(ib));
    }

    // ------------------------------------------------------------------ Texte

    static String modusName(int m) {
        return switch (m) {
            case VK_PRESENT_MODE_FIFO_KHR -> "FIFO";
            case VK_PRESENT_MODE_MAILBOX_KHR -> "MAILBOX";
            case VK_PRESENT_MODE_IMMEDIATE_KHR -> "IMMEDIATE";
            case VK_PRESENT_MODE_FIFO_RELAXED_KHR -> "FIFO_RELAXED";
            default -> "Art " + m;
        };
    }

    static JLabel label(String t) {
        JLabel l = new JLabel(t);
        l.setForeground(TEXT);
        return l;
    }
}
