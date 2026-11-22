package com.dan.hallighooge.p0;

import org.lwjgl.system.MemoryStack;
import org.lwjgl.util.vma.VmaBudget;
import org.lwjgl.vulkan.*;

import java.nio.IntBuffer;
import java.nio.LongBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import static com.dan.hallighooge.p0.Bericht.f;
import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.util.vma.Vma.vmaGetHeapBudgets;
import static org.lwjgl.vulkan.VK13.*;

/**
 * P0.1 und P0.5 (Werkbuch 12): Was das Gerät meldet – Warteschlangen, Heaps, Erweiterungen, Merkmale, Untergruppen,
 * Grenzen – und ob der Bau trägt: JDK, shaderc mit Include, ein Probe-Kernel mit float16 und Untergruppen auf der Karte,
 * Zeitleisten-Semaphor über zwei Warteschlangen, SPIR-V aus dem Ant-Ziel.
 */
public final class P0Geraet {
    private P0Geraet() {}

    public static void main(String[] a) {
        Bericht b = new Bericht();
        messen(b);
        Path p = b.schreiben("P0_Geraet.md", "P0.1 und P0.5 – Gerät und Bau");
        System.out.println();
        System.out.println("Bericht: " + p);
        System.out.println(b.verstoesse() == 0 ? "Alles in Ordnung." : b.verstoesse() + " Verstöße.");
    }

    static void messen(Bericht b) {
        b.teil("P0.1 Gerät");
        int iv = VK.getInstanceVersionSupported();
        b.pruefe(iv >= VK_API_VERSION_1_3, "Vulkan-Lader", Vulkan.version(iv), "≥ 1.3");
        b.info("Validierungsschicht", Vulkan.hatSchicht("VK_LAYER_KHRONOS_validation") ? "vorhanden" : "fehlt (Vulkan SDK von LunarG; nur für die Entwicklung)");
        try (Vulkan vk = new Vulkan(new Vulkan.Optionen()); MemoryStack s = stackPush()) {
            // alle Geräte
            List<String> alle = new ArrayList<>();
            for (VkPhysicalDevice d : Vulkan.geraete(vk.instance)) {
                VkPhysicalDeviceProperties p = VkPhysicalDeviceProperties.malloc(s);
                vkGetPhysicalDeviceProperties(d, p);
                alle.add(p.deviceNameString() + " (" + typ(p.deviceType()) + ", Vulkan " + Vulkan.version(p.apiVersion()) + ")");
            }
            b.info("Geräte", String.join("; ", alle));

            // Eigenschaften
            VkPhysicalDeviceProperties2 p2 = VkPhysicalDeviceProperties2.calloc(s).sType$Default();
            VkPhysicalDeviceVulkan11Properties p11 = VkPhysicalDeviceVulkan11Properties.calloc(s).sType$Default();
            VkPhysicalDeviceVulkan12Properties p12 = VkPhysicalDeviceVulkan12Properties.calloc(s).sType$Default();
            VkPhysicalDeviceVulkan13Properties p13 = VkPhysicalDeviceVulkan13Properties.calloc(s).sType$Default();
            VkPhysicalDeviceAccelerationStructurePropertiesKHR pas = VkPhysicalDeviceAccelerationStructurePropertiesKHR.calloc(s).sType$Default();
            Set<String> ext = Vulkan.geraeteErweiterungen(vk.phys, s);
            boolean asDa = ext.contains(KHRAccelerationStructure.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME);
            p2.pNext(p11.address());
            p11.pNext(p12.address());
            p12.pNext(p13.address());
            if (asDa) p13.pNext(pas.address());
            vkGetPhysicalDeviceProperties2(vk.phys, p2);
            VkPhysicalDeviceProperties p = p2.properties();
            VkPhysicalDeviceLimits l = p.limits();
            VkConformanceVersion cv = p12.conformanceVersion();
            b.pruefe(p.apiVersion() >= VK_API_VERSION_1_3, "Gerät", p.deviceNameString() + ", Vulkan " + Vulkan.version(p.apiVersion()), "Vulkan ≥ 1.3");
            b.info("Treiber", p12.driverNameString() + " " + p12.driverInfoString() + f(" (Konformität %d.%d.%d.%d)", cv.major(), cv.minor(), cv.subminor(), cv.patch()));

            // Warteschlangen
            VkQueueFamilyProperties.Buffer fam = Vulkan.familien(vk.phys, s);
            StringBuilder q = new StringBuilder();
            for (int i = 0; i < fam.capacity(); i++) {
                VkQueueFamilyProperties x = fam.get(i);
                q.append(i == 0 ? "" : "; ").append(i).append(": ").append(x.queueCount()).append(" × ").append(flags(x.queueFlags()))
                        .append(", Zeitstempel ").append(x.timestampValidBits()).append(" Bit");
            }
            b.info("Familien", q.toString());
            b.pruefe(vk.familieRechnen >= 0, "eigene Rechen-Warteschlange (Physik neben dem Bild)", vk.familieRechnen >= 0 ? "Familie " + vk.familieRechnen : "keine", "vorhanden");

            // Speicher
            VkPhysicalDeviceMemoryProperties mp = VkPhysicalDeviceMemoryProperties.malloc(s);
            vkGetPhysicalDeviceMemoryProperties(vk.phys, mp);
            VmaBudget.Buffer bud = VmaBudget.calloc(VK_MAX_MEMORY_HEAPS, s);
            vmaGetHeapBudgets(vk.vma, bud);
            for (int h = 0; h < mp.memoryHeapCount(); h++) {
                VkMemoryHeap heap = mp.memoryHeaps(h);
                StringBuilder ty = new StringBuilder();
                for (int t = 0; t < mp.memoryTypeCount(); t++) {
                    VkMemoryType mt = mp.memoryTypes(t);
                    if (mt.heapIndex() == h) ty.append(ty.length() == 0 ? "" : ", ").append(t).append(' ').append(speicherFlags(mt.propertyFlags()));
                }
                b.info("Heap " + h, f("%s, %s; Budget %s, belegt %s; Typen: %s", Vulkan.mb(heap.size()),
                        (heap.flags() & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) != 0 ? "gerätelokal" : "Hauptspeicher",
                        Vulkan.mb(bud.get(h).budget()), Vulkan.mb(bud.get(h).usage()), ty));
            }
            boolean ohneKopie = false;
            for (int t = 0; t < mp.memoryTypeCount(); t++) {
                int fl = mp.memoryTypes(t).propertyFlags();
                if ((fl & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) != 0 && (fl & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0) ohneKopie = true;
            }
            b.info("gerätelokal und vom Prozessor sichtbar", ohneKopie ? "ja (Felder ohne Kopie möglich)" : "nein");
            b.info("größte Zuteilung", Vulkan.mb(p11.maxMemoryAllocationSize()) + f(", größter Speicherpuffer %s, höchstens %s Zuteilungen",
                    Vulkan.mb(l.maxStorageBufferRange() & 0xffffffffL), Integer.toUnsignedString(l.maxMemoryAllocationCount())));

            // Erweiterungen
            b.pruefe(ext.contains(KHRRayQuery.VK_KHR_RAY_QUERY_EXTENSION_NAME), "VK_KHR_ray_query", da(ext, KHRRayQuery.VK_KHR_RAY_QUERY_EXTENSION_NAME), "vorhanden");
            b.pruefe(asDa, "VK_KHR_acceleration_structure", da(ext, KHRAccelerationStructure.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME), "vorhanden");
            StringBuilder weitere = new StringBuilder();
            for (String e : new String[]{"VK_KHR_ray_tracing_pipeline", "VK_KHR_push_descriptor", "VK_EXT_memory_budget", "VK_EXT_external_memory_host",
                    "VK_EXT_descriptor_buffer", "VK_EXT_mesh_shader", "VK_EXT_shader_atomic_float", "VK_KHR_cooperative_matrix",
                    "VK_KHR_maintenance5", "VK_KHR_maintenance6", "VK_EXT_shader_object", "VK_KHR_external_memory_win32", "VK_AMD_shader_core_properties2"})
                weitere.append(weitere.length() == 0 ? "" : ", ").append(e.substring(3)).append(ext.contains(e) ? " ja" : " nein");
            b.info("weitere Erweiterungen", weitere.toString());
            b.info("Erweiterungen gesamt", String.valueOf(ext.size()));

            // Merkmale
            VkPhysicalDeviceFeatures2 f2 = VkPhysicalDeviceFeatures2.calloc(s).sType$Default();
            VkPhysicalDeviceVulkan11Features f11 = VkPhysicalDeviceVulkan11Features.calloc(s).sType$Default();
            VkPhysicalDeviceVulkan12Features f12 = VkPhysicalDeviceVulkan12Features.calloc(s).sType$Default();
            VkPhysicalDeviceVulkan13Features f13 = VkPhysicalDeviceVulkan13Features.calloc(s).sType$Default();
            VkPhysicalDeviceAccelerationStructureFeaturesKHR fas = VkPhysicalDeviceAccelerationStructureFeaturesKHR.calloc(s).sType$Default();
            VkPhysicalDeviceRayQueryFeaturesKHR frq = VkPhysicalDeviceRayQueryFeaturesKHR.calloc(s).sType$Default();
            f2.pNext(f11.address());
            f11.pNext(f12.address());
            f12.pNext(f13.address());
            if (asDa) { f13.pNext(fas.address()); fas.pNext(frq.address()); }
            vkGetPhysicalDeviceFeatures2(vk.phys, f2);
            b.pruefe(fas.accelerationStructure() && frq.rayQuery(), "Strahlabfrage (Merkmal)", ja(fas.accelerationStructure() && frq.rayQuery()), "ja");
            b.pruefe(f12.descriptorIndexing() && f12.runtimeDescriptorArray() && f12.descriptorBindingPartiallyBound()
                            && f12.shaderStorageBufferArrayNonUniformIndexing() && f12.descriptorBindingVariableDescriptorCount(),
                    "Deskriptor-Indizes (bindlos)", f("Indizes %s, Laufzeit-Felder %s, teilweise gebunden %s, ungleichförmig %s, veränderliche Zahl %s",
                            ja(f12.descriptorIndexing()), ja(f12.runtimeDescriptorArray()), ja(f12.descriptorBindingPartiallyBound()),
                            ja(f12.shaderStorageBufferArrayNonUniformIndexing()), ja(f12.descriptorBindingVariableDescriptorCount())), "alle ja");
            b.pruefe(f12.timelineSemaphore(), "Zeitleisten-Semaphoren", ja(f12.timelineSemaphore()), "ja");
            b.pruefe(f12.shaderFloat16() && f11.storageBuffer16BitAccess(), "float16", f("Rechnen %s, Speicher %s", ja(f12.shaderFloat16()), ja(f11.storageBuffer16BitAccess())), "beide ja");
            b.pruefe(f12.bufferDeviceAddress(), "Puffer-Adressen", ja(f12.bufferDeviceAddress()), "ja");
            b.pruefe(f13.synchronization2() && f13.dynamicRendering(), "Synchronisation 2, dynamisches Rendern",
                    ja(f13.synchronization2()) + ", " + ja(f13.dynamicRendering()), "beide ja");
            b.info("weitere Merkmale", f("scalarBlockLayout %s, shaderInt8 %s, shaderInt64 %s, shaderFloat64 %s, subgroupSizeControl %s, computeFullSubgroups %s, maintenance4 %s",
                    ja(f12.scalarBlockLayout()), ja(f12.shaderInt8()), ja(f2.features().shaderInt64()), ja(f2.features().shaderFloat64()),
                    ja(f13.subgroupSizeControl()), ja(f13.computeFullSubgroups()), ja(f13.maintenance4())));

            // Untergruppen
            int ops = p11.subgroupSupportedOperations();
            boolean rechnenUg = (p11.subgroupSupportedStages() & VK_SHADER_STAGE_COMPUTE_BIT) != 0;
            boolean noetig = (ops & VK11.VK_SUBGROUP_FEATURE_ARITHMETIC_BIT) != 0 && (ops & VK11.VK_SUBGROUP_FEATURE_BALLOT_BIT) != 0
                    && (ops & VK11.VK_SUBGROUP_FEATURE_SHUFFLE_BIT) != 0;
            b.pruefe(rechnenUg && noetig, "Untergruppen im Rechnen", f("Größe %d (%d–%d), %s", p11.subgroupSize(), p13.minSubgroupSize(), p13.maxSubgroupSize(), ugOps(ops)),
                    "Arithmetik, Ballot, Shuffle");

            // Grenzen
            b.pruefe(l.timestampComputeAndGraphics(), "Zeitstempel in Grafik und Rechnen", f("%s, %.2f ns je Takt", ja(l.timestampComputeAndGraphics()), l.timestampPeriod()), "ja");
            b.pruefe(l.maxPushConstantsSize() >= 128, "Push-Konstanten", l.maxPushConstantsSize() + " Byte", "≥ 128");
            b.info("Rechengruppen", f("höchstens %d Fäden, %d kB geteilter Speicher, Gruppen %s × %s × %s",
                    l.maxComputeWorkGroupInvocations(), l.maxComputeSharedMemorySize() / 1024, Integer.toUnsignedString(l.maxComputeWorkGroupCount(0)),
                    Integer.toUnsignedString(l.maxComputeWorkGroupCount(1)), Integer.toUnsignedString(l.maxComputeWorkGroupCount(2))));
            if (asDa) b.info("Beschleunigungsstrukturen", f("höchstens %,d Dreiecke je Geometrie, %,d Instanzen, Kratzspeicher ausgerichtet auf %d Byte",
                    pas.maxPrimitiveCount(), pas.maxInstanceCount(), pas.minAccelerationStructureScratchOffsetAlignment()));

            // Zeitleiste über zwei Warteschlangen (Rechnen signalisiert, Prozessor wartet)
            b.pruefe(zeitleiste(vk), "Zeitleiste: Rechen-Warteschlange signalisiert 7, Prozessor wartet", "erreicht", "erreicht");

            // Probe-Kernel: Include, float16, Untergruppen-Summe; Ergebnis = 2 × tatsächliche Untergruppengröße
            b.teil("P0.5 Bau");
            probe(vk, b, p11.subgroupSize(), p13.minSubgroupSize(), p13.maxSubgroupSize());
        } catch (Throwable e) {
            b.fehler(e);
        }
        bau(b);
    }

    private static boolean zeitleiste(Vulkan vk) {
        try (MemoryStack s = stackPush()) {
            VkSemaphoreTypeCreateInfo ti = VkSemaphoreTypeCreateInfo.calloc(s).sType$Default().semaphoreType(VK_SEMAPHORE_TYPE_TIMELINE).initialValue(0);
            LongBuffer lb = s.mallocLong(1);
            Vulkan.ok(vkCreateSemaphore(vk.device, VkSemaphoreCreateInfo.calloc(s).sType$Default().pNext(ti.address()), null, lb), "vkCreateSemaphore (Zeitleiste)");
            long sem = lb.get(0);
            try {
                VkSubmitInfo2.Buffer si = VkSubmitInfo2.calloc(1, s);
                si.get(0).sType$Default().pSignalSemaphoreInfos(VkSemaphoreSubmitInfo.calloc(1, s).sType$Default()
                        .semaphore(sem).value(7).stageMask(VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT));
                Vulkan.ok(vkQueueSubmit2(vk.queueRechnen != null ? vk.queueRechnen : vk.queue, si, VK_NULL_HANDLE), "vkQueueSubmit2");
                int r = vkWaitSemaphores(vk.device, VkSemaphoreWaitInfo.calloc(s).sType$Default().semaphoreCount(1)
                        .pSemaphores(s.longs(sem)).pValues(s.longs(7)), 2_000_000_000L);
                Vulkan.ok(vkGetSemaphoreCounterValue(vk.device, sem, lb), "vkGetSemaphoreCounterValue");
                return r == VK_SUCCESS && lb.get(0) == 7;
            } finally {
                vkDeviceWaitIdle(vk.device);
                vkDestroySemaphore(vk.device, sem, null);
            }
        }
    }

    private static void probe(Vulkan vk, Bericht b, int ug, int ugMin, int ugMax) {
        Shader.Spirv sp = Shader.laden("/com/dan/hallighooge/p0/probe.comp");
        b.pruefe(true, "shaderc mit #include, float16, Untergruppen", sp.woher + (sp.ms > 0 ? ", " + Shader.ms(sp.ms) : "") + f(", %d Byte SPIR-V", sp.code.remaining()), "übersetzt");
        int n = 256;
        try (Kernel k = new Kernel(vk, sp.code, new int[]{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER}, 0);
             Puffer d = Puffer.speicher(vk, n * 4L)) {
            float[] eins = new float[n];
            java.util.Arrays.fill(eins, 1f);
            d.schreiben(eins);
            long set = k.satz(d.handle);
            vk.einmal(c -> k.aufnehmen(c, set, null, n / 64, 1, 1));
            float[] r = d.floats(n);
            int tats = Math.round(r[0] / 2);
            boolean gleich = true;
            for (float v : r) gleich &= v == r[0];
            b.pruefe(gleich && tats >= ugMin && tats <= ugMax, "Probe-Kernel auf der Karte", f("Untergruppe tatsächlich %d (gemeldet %d)", tats, ug), "einheitlich, im Bereich");
        } finally {
            sp.frei();
        }
        // Strahlabfrage-Shader übersetzen (SPIR-V 1.6, GL_EXT_ray_query)
        Shader.Spirv st = Shader.laden("/com/dan/hallighooge/p0/strahl.comp");
        b.pruefe(true, "Strahlabfrage-Shader", st.woher + (st.ms > 0 ? ", " + Shader.ms(st.ms) : "") + f(", %d Byte", st.code.remaining()), "übersetzt");
        if (st.ms == 0) {
            // vorgebaut: zur Laufzeit noch einmal übersetzen und vergleichen
            Shader.Spirv neu = Shader.uebersetzen(Shader.text("/com/dan/hallighooge/p0/strahl.comp"), "/com/dan/hallighooge/p0/strahl.comp", Shader.art(".comp"));
            b.info("Ant gegen Laufzeit", neu.code.equals(st.code) ? "SPIR-V bytegleich" : "SPIR-V verschieden (andere shaderc-Version?)");
            neu.frei();
        }
        st.frei();
    }

    /** P0.5: JDK, Foreign Memory, Ant-Ziel spirv. */
    private static void bau(Bericht b) {
        Runtime.Version v = Runtime.version();
        b.pruefe(v.feature() >= 21, "JDK", System.getProperty("java.vm.vendor") + " " + v, "≥ 21");
        b.info("Foreign Memory (java.lang.foreign)", v.feature() >= 22 ? "fertig (JDK " + v.feature() + ")" : "Vorschau in JDK 21; fertig ab 22 (F9: JDK 25)");
        b.info("Speicher der JVM", Vulkan.mb(Runtime.getRuntime().maxMemory()));
        Path spv = Path.of("build", "classes", "com", "dan", "hallighooge", "p0", "strahl.comp.spv");
        b.info("Ant-Ziel spirv", Files.exists(spv) ? "gelaufen (" + spv + ")" : "noch nicht gelaufen (Clean and Build)");
    }

    // ------------------------------------------------------------------ Texte

    static String ja(boolean b) { return b ? "ja" : "nein"; }

    static String da(Set<String> ext, String e) { return ext.contains(e) ? "vorhanden" : "fehlt"; }

    static String typ(int t) {
        return switch (t) {
            case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU -> "integriert";
            case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU -> "eigene Karte";
            case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU -> "virtuell";
            case VK_PHYSICAL_DEVICE_TYPE_CPU -> "Prozessor";
            default -> "andere";
        };
    }

    static String flags(int f) {
        List<String> l = new ArrayList<>();
        if ((f & VK_QUEUE_GRAPHICS_BIT) != 0) l.add("Grafik");
        if ((f & VK_QUEUE_COMPUTE_BIT) != 0) l.add("Rechnen");
        if ((f & VK_QUEUE_TRANSFER_BIT) != 0) l.add("Übertragung");
        if ((f & VK_QUEUE_SPARSE_BINDING_BIT) != 0) l.add("dünn");
        return String.join("+", l);
    }

    static String speicherFlags(int f) {
        StringBuilder b = new StringBuilder();
        if ((f & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) != 0) b.append("G");
        if ((f & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0) b.append("S");
        if ((f & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0) b.append("K");
        if ((f & VK_MEMORY_PROPERTY_HOST_CACHED_BIT) != 0) b.append("Z");
        return b.length() == 0 ? "–" : b.toString();
    }

    static String ugOps(int o) {
        List<String> l = new ArrayList<>();
        if ((o & VK11.VK_SUBGROUP_FEATURE_BASIC_BIT) != 0) l.add("Basis");
        if ((o & VK11.VK_SUBGROUP_FEATURE_VOTE_BIT) != 0) l.add("Abstimmung");
        if ((o & VK11.VK_SUBGROUP_FEATURE_ARITHMETIC_BIT) != 0) l.add("Arithmetik");
        if ((o & VK11.VK_SUBGROUP_FEATURE_BALLOT_BIT) != 0) l.add("Ballot");
        if ((o & VK11.VK_SUBGROUP_FEATURE_SHUFFLE_BIT) != 0) l.add("Shuffle");
        if ((o & VK11.VK_SUBGROUP_FEATURE_SHUFFLE_RELATIVE_BIT) != 0) l.add("Shuffle relativ");
        if ((o & VK11.VK_SUBGROUP_FEATURE_CLUSTERED_BIT) != 0) l.add("Gruppen");
        if ((o & VK11.VK_SUBGROUP_FEATURE_QUAD_BIT) != 0) l.add("Quad");
        return String.join(", ", l);
    }

    static int ints(IntBuffer b) { return b.get(0); }
}
