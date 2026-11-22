package com.dan.hallighooge.p0;

import org.lwjgl.PointerBuffer;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.util.vma.VmaAllocatorCreateInfo;
import org.lwjgl.util.vma.VmaVulkanFunctions;
import org.lwjgl.vulkan.*;

import java.nio.IntBuffer;
import java.nio.LongBuffer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;

import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.system.MemoryUtil.NULL;
import static org.lwjgl.system.MemoryUtil.memUTF8;
import static org.lwjgl.util.vma.Vma.*;
import static org.lwjgl.vulkan.EXTDebugUtils.*;
import static org.lwjgl.vulkan.VK13.*;

/**
 * Vulkan für P0 (Werkbuch 12): Instanz, Gerät, Warteschlangen, VMA, Befehle, Zeitstempel. Bewusst schlicht: Der
 * Unterbau des Renderers entsteht in P2 als {@code com.dan.core.gpu}; hier wird nur gemessen, was er können muss.
 * <p>
 * Eingeschaltet wird jedes Merkmal, das das Gerät kann, außer den Robustheits-Merkmalen (sie kosten Zeit und würden
 * die Messung verfälschen). Validierung nur mit {@code -Dp0.validierung=true} (sie verfälscht die Zeiten ebenso).
 */
final class Vulkan implements AutoCloseable {

    /** Was das Gerät mitbringen soll. */
    static final class Optionen {
        boolean validierung = Boolean.getBoolean("p0.validierung");
        /** Instanz-Erweiterungen für eine Fläche unter Windows (VK_KHR_surface, VK_KHR_win32_surface) und Swapchain. */
        boolean flaeche;
        /** Strahlabfrage und Beschleunigungsstrukturen, wenn das Gerät sie kann. */
        boolean strahlen = true;
    }

    final VkInstance instance;
    final VkPhysicalDevice phys;
    final VkDevice device;
    final String name;
    final int apiVersion;
    /** Familie mit Grafik und Rechnen; reine Rechen-Familie (asynchron) oder −1. */
    final int familieAlle, familieRechnen;
    final VkQueue queue, queueRechnen;
    final long pool, poolRechnen;
    final long vma;
    /** Nanosekunden je Zeitstempel-Takt; gültige Bits der Zeitstempel der Haupt-Familie. */
    final float timestampPeriod;
    final int timestampBits;
    final boolean validierung, strahlen, adressen, budget;
    final Set<String> erweiterungen;
    final List<String> meldungen = Collections.synchronizedList(new ArrayList<>());
    volatile int validierungsFehler;
    private long messenger;
    private VkDebugUtilsMessengerCallbackEXT rueckruf;

    Vulkan(Optionen o) {
        try (MemoryStack s = stackPush()) {
            // ---------------------------------------------------------- Instanz
            boolean val = o.validierung && hatSchicht("VK_LAYER_KHRONOS_validation");
            if (o.validierung && !val) System.out.println("  (Validierung gewünscht, aber VK_LAYER_KHRONOS_validation fehlt – Vulkan SDK installieren)");
            validierung = val;
            List<String> iext = new ArrayList<>();
            if (val) iext.add(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
            if (o.flaeche) {
                iext.add(KHRSurface.VK_KHR_SURFACE_EXTENSION_NAME);
                iext.add(KHRWin32Surface.VK_KHR_WIN32_SURFACE_EXTENSION_NAME);
            }
            VkApplicationInfo app = VkApplicationInfo.calloc(s).sType$Default()
                    .pApplicationName(s.UTF8("HalligHooge P0")).applicationVersion(1)
                    .pEngineName(s.UTF8("com.dan.core")).engineVersion(1)
                    .apiVersion(VK_API_VERSION_1_3);
            VkInstanceCreateInfo ici = VkInstanceCreateInfo.calloc(s).sType$Default()
                    .pApplicationInfo(app)
                    .ppEnabledLayerNames(val ? s.pointers(s.UTF8("VK_LAYER_KHRONOS_validation")) : null)
                    .ppEnabledExtensionNames(namen(s, iext));
            VkDebugUtilsMessengerCreateInfoEXT dci = null;
            if (val) {
                rueckruf = VkDebugUtilsMessengerCallbackEXT.create((schwere, art, pDaten, nutzer) -> {
                    String m = VkDebugUtilsMessengerCallbackDataEXT.create(pDaten).pMessageString();
                    if ((schwere & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) != 0) validierungsFehler++;
                    if (meldungen.size() < 50) meldungen.add(m);
                    System.err.println("  Vulkan: " + m);
                    return VK_FALSE;
                });
                dci = VkDebugUtilsMessengerCreateInfoEXT.calloc(s).sType$Default()
                        .messageSeverity(VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT)
                        .messageType(VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT
                                | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT)
                        .pfnUserCallback(rueckruf);
            }
            PointerBuffer pp = s.mallocPointer(1);
            ok(vkCreateInstance(ici, null, pp), "vkCreateInstance");
            instance = new VkInstance(pp.get(0), ici);
            if (val) {
                LongBuffer lp = s.mallocLong(1);
                ok(vkCreateDebugUtilsMessengerEXT(instance, dci, null, lp), "vkCreateDebugUtilsMessengerEXT");
                messenger = lp.get(0);
            }

            // ---------------------------------------------------------- Gerät wählen
            List<VkPhysicalDevice> alle = geraete(instance);
            if (alle.isEmpty()) throw new IllegalStateException("Kein Vulkan-Gerät gefunden");
            int wahl = Integer.getInteger("p0.geraet", -1);
            VkPhysicalDevice gew = null;
            if (wahl >= 0) gew = alle.get(wahl);
            else {
                int best = -1;
                for (VkPhysicalDevice d : alle) {
                    VkPhysicalDeviceProperties p = VkPhysicalDeviceProperties.malloc(s);
                    vkGetPhysicalDeviceProperties(d, p);
                    int rang = (p.apiVersion() >= VK_API_VERSION_1_3 ? 10 : 0) + switch (p.deviceType()) {
                        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU -> 3;
                        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU -> 2;
                        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU -> 1;
                        default -> 0;
                    };
                    if (rang > best) { best = rang; gew = d; }
                }
            }
            phys = gew;
            VkPhysicalDeviceProperties prop = VkPhysicalDeviceProperties.malloc(s);
            vkGetPhysicalDeviceProperties(phys, prop);
            name = prop.deviceNameString();
            apiVersion = prop.apiVersion();
            if (apiVersion < VK_API_VERSION_1_3)
                throw new IllegalStateException(name + " meldet nur Vulkan " + version(apiVersion) + ", gebraucht wird 1.3");
            timestampPeriod = prop.limits().timestampPeriod();

            // ---------------------------------------------------------- Warteschlangen
            VkQueueFamilyProperties.Buffer fam = familien(phys, s);
            int alleF = -1, rechnenF = -1;
            for (int i = 0; i < fam.capacity(); i++) {
                int f = fam.get(i).queueFlags();
                boolean gr = (f & VK_QUEUE_GRAPHICS_BIT) != 0, re = (f & VK_QUEUE_COMPUTE_BIT) != 0;
                if (gr && re && alleF < 0) alleF = i;
                if (!gr && re && rechnenF < 0) rechnenF = i;
            }
            if (alleF < 0) throw new IllegalStateException(name + ": keine Familie mit Grafik und Rechnen");
            familieAlle = alleF;
            familieRechnen = rechnenF;
            timestampBits = fam.get(alleF).timestampValidBits();

            // ---------------------------------------------------------- Erweiterungen
            Set<String> da = geraeteErweiterungen(phys, s);
            List<String> dext = new ArrayList<>();
            if (o.flaeche) dext.add(KHRSwapchain.VK_KHR_SWAPCHAIN_EXTENSION_NAME);
            boolean rt = o.strahlen && da.contains(KHRAccelerationStructure.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME)
                    && da.contains(KHRRayQuery.VK_KHR_RAY_QUERY_EXTENSION_NAME)
                    && da.contains(KHRDeferredHostOperations.VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME);
            if (rt) {
                dext.add(KHRAccelerationStructure.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME);
                dext.add(KHRRayQuery.VK_KHR_RAY_QUERY_EXTENSION_NAME);
                dext.add(KHRDeferredHostOperations.VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME);
            }
            boolean bud = da.contains(EXTMemoryBudget.VK_EXT_MEMORY_BUDGET_EXTENSION_NAME);
            if (bud) dext.add(EXTMemoryBudget.VK_EXT_MEMORY_BUDGET_EXTENSION_NAME);
            erweiterungen = Collections.unmodifiableSet(new LinkedHashSet<>(dext));

            // ---------------------------------------------------------- Merkmale: alles, was das Gerät kann
            VkPhysicalDeviceFeatures2 f2 = VkPhysicalDeviceFeatures2.calloc(s).sType$Default();
            VkPhysicalDeviceVulkan11Features f11 = VkPhysicalDeviceVulkan11Features.calloc(s).sType$Default();
            VkPhysicalDeviceVulkan12Features f12 = VkPhysicalDeviceVulkan12Features.calloc(s).sType$Default();
            VkPhysicalDeviceVulkan13Features f13 = VkPhysicalDeviceVulkan13Features.calloc(s).sType$Default();
            VkPhysicalDeviceAccelerationStructureFeaturesKHR fas = VkPhysicalDeviceAccelerationStructureFeaturesKHR.calloc(s).sType$Default();
            VkPhysicalDeviceRayQueryFeaturesKHR frq = VkPhysicalDeviceRayQueryFeaturesKHR.calloc(s).sType$Default();
            f2.pNext(f11.address());
            f11.pNext(f12.address());
            f12.pNext(f13.address());
            if (rt) {
                f13.pNext(fas.address());
                fas.pNext(frq.address());
            }
            VK11.vkGetPhysicalDeviceFeatures2(phys, f2);
            f2.features().robustBufferAccess(false);
            f13.robustImageAccess(false);
            fas.accelerationStructureCaptureReplay(false).accelerationStructureHostCommands(false);
            rt = rt && fas.accelerationStructure() && frq.rayQuery() && f12.bufferDeviceAddress();
            strahlen = rt;
            adressen = f12.bufferDeviceAddress();
            budget = bud;

            // ---------------------------------------------------------- Gerät
            VkDeviceQueueCreateInfo.Buffer qci = VkDeviceQueueCreateInfo.calloc(rechnenF >= 0 ? 2 : 1, s);
            qci.get(0).sType$Default().queueFamilyIndex(alleF).pQueuePriorities(s.floats(1f));
            if (rechnenF >= 0) qci.get(1).sType$Default().queueFamilyIndex(rechnenF).pQueuePriorities(s.floats(1f));
            VkDeviceCreateInfo dci2 = VkDeviceCreateInfo.calloc(s).sType$Default()
                    .pNext(f2.address())
                    .pQueueCreateInfos(qci)
                    .ppEnabledExtensionNames(namen(s, dext));
            ok(vkCreateDevice(phys, dci2, null, pp), "vkCreateDevice");
            device = new VkDevice(pp.get(0), phys, dci2, VK_API_VERSION_1_3);
            vkGetDeviceQueue(device, alleF, 0, pp);
            queue = new VkQueue(pp.get(0), device);
            if (rechnenF >= 0) {
                vkGetDeviceQueue(device, rechnenF, 0, pp);
                queueRechnen = new VkQueue(pp.get(0), device);
            } else queueRechnen = null;
            pool = befehlsPool(alleF);
            poolRechnen = rechnenF >= 0 ? befehlsPool(rechnenF) : NULL;

            // ---------------------------------------------------------- VMA
            VmaVulkanFunctions vf = VmaVulkanFunctions.calloc(s).set(instance, device);
            VmaAllocatorCreateInfo aci = VmaAllocatorCreateInfo.calloc(s)
                    .flags((adressen ? VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT : 0) | (bud ? VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT : 0))
                    .physicalDevice(phys).device(device).instance(instance)
                    .pVulkanFunctions(vf)
                    .vulkanApiVersion(VK_API_VERSION_1_3);
            ok(vmaCreateAllocator(aci, pp), "vmaCreateAllocator");
            vma = pp.get(0);
        }
    }

    // ------------------------------------------------------------------ Befehle

    private long befehlsPool(int familie) {
        try (MemoryStack s = stackPush()) {
            VkCommandPoolCreateInfo ci = VkCommandPoolCreateInfo.calloc(s).sType$Default()
                    .flags(VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT).queueFamilyIndex(familie);
            LongBuffer lp = s.mallocLong(1);
            ok(vkCreateCommandPool(device, ci, null, lp), "vkCreateCommandPool");
            return lp.get(0);
        }
    }

    VkCommandBuffer befehle(long pool) {
        try (MemoryStack s = stackPush()) {
            VkCommandBufferAllocateInfo ai = VkCommandBufferAllocateInfo.calloc(s).sType$Default()
                    .commandPool(pool).level(VK_COMMAND_BUFFER_LEVEL_PRIMARY).commandBufferCount(1);
            PointerBuffer pp = s.mallocPointer(1);
            ok(vkAllocateCommandBuffers(device, ai, pp), "vkAllocateCommandBuffers");
            return new VkCommandBuffer(pp.get(0), device);
        }
    }

    static void beginne(VkCommandBuffer c, boolean einmal) {
        try (MemoryStack s = stackPush()) {
            VkCommandBufferBeginInfo bi = VkCommandBufferBeginInfo.calloc(s).sType$Default()
                    .flags(einmal ? VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT : 0);
            ok(vkBeginCommandBuffer(c, bi), "vkBeginCommandBuffer");
        }
    }

    /** Schickt c ab und wartet (Zaun); gibt die Wartezeit des Prozessors in ns zurück. */
    long abschicken(VkQueue q, VkCommandBuffer c) {
        try (MemoryStack s = stackPush()) {
            long zaun = zaun(false);
            VkSubmitInfo si = VkSubmitInfo.calloc(s).sType$Default().pCommandBuffers(s.pointers(c));
            long t0 = System.nanoTime();
            ok(vkQueueSubmit(q, si, zaun), "vkQueueSubmit");
            ok(vkWaitForFences(device, zaun, true, Long.MAX_VALUE), "vkWaitForFences");
            long t = System.nanoTime() - t0;
            vkDestroyFence(device, zaun, null);
            return t;
        }
    }

    /** Einmal-Befehle auf der Haupt-Warteschlange aufnehmen, abschicken und warten. */
    long einmal(Consumer<VkCommandBuffer> f) {
        VkCommandBuffer c = befehle(pool);
        beginne(c, true);
        f.accept(c);
        ok(vkEndCommandBuffer(c), "vkEndCommandBuffer");
        long t = abschicken(queue, c);
        vkFreeCommandBuffers(device, pool, c);
        return t;
    }

    long zaun(boolean signalisiert) {
        try (MemoryStack s = stackPush()) {
            VkFenceCreateInfo fi = VkFenceCreateInfo.calloc(s).sType$Default().flags(signalisiert ? VK_FENCE_CREATE_SIGNALED_BIT : 0);
            LongBuffer lp = s.mallocLong(1);
            ok(vkCreateFence(device, fi, null, lp), "vkCreateFence");
            return lp.get(0);
        }
    }

    long semaphor() {
        try (MemoryStack s = stackPush()) {
            LongBuffer lp = s.mallocLong(1);
            ok(vkCreateSemaphore(device, VkSemaphoreCreateInfo.calloc(s).sType$Default(), null, lp), "vkCreateSemaphore");
            return lp.get(0);
        }
    }

    /** Sperre zwischen zwei Durchgängen: alles Schreiben der Shader (und Kopien) vor allem Lesen und Schreiben danach. */
    static void sperre(VkCommandBuffer c) {
        try (MemoryStack s = stackPush()) {
            VkMemoryBarrier2.Buffer m = VkMemoryBarrier2.calloc(1, s);
            m.get(0).sType$Default()
                    .srcStageMask(VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT)
                    .srcAccessMask(VK_ACCESS_2_MEMORY_WRITE_BIT)
                    .dstStageMask(VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT)
                    .dstAccessMask(VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT);
            vkCmdPipelineBarrier2(c, VkDependencyInfo.calloc(s).sType$Default().pMemoryBarriers(m));
        }
    }

    // ------------------------------------------------------------------ Zeitstempel

    long zeitAbfragen(int anzahl) {
        try (MemoryStack s = stackPush()) {
            VkQueryPoolCreateInfo ci = VkQueryPoolCreateInfo.calloc(s).sType$Default().queryType(VK_QUERY_TYPE_TIMESTAMP).queryCount(anzahl);
            LongBuffer lp = s.mallocLong(1);
            ok(vkCreateQueryPool(device, ci, null, lp), "vkCreateQueryPool");
            return lp.get(0);
        }
    }

    /** Zeitstempel first … first+n−1 in ns (wartet, bis sie vorliegen). */
    double[] zeiten(long abfragen, int first, int n) {
        try (MemoryStack s = stackPush()) {
            LongBuffer lb = s.mallocLong(n);
            ok(vkGetQueryPoolResults(device, abfragen, first, n, lb, 8, VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT), "vkGetQueryPoolResults");
            double[] out = new double[n];
            long maske = timestampBits >= 64 ? -1L : (1L << timestampBits) - 1;
            for (int i = 0; i < n; i++) out[i] = (lb.get(i) & maske) * (double) timestampPeriod;
            return out;
        }
    }

    // ------------------------------------------------------------------ Hilfen

    static boolean hatSchicht(String name) {
        try (MemoryStack s = stackPush()) {
            IntBuffer n = s.mallocInt(1);
            vkEnumerateInstanceLayerProperties(n, null);
            VkLayerProperties.Buffer l = VkLayerProperties.malloc(n.get(0));
            try {
                vkEnumerateInstanceLayerProperties(n, l);
                for (int i = 0; i < l.capacity(); i++) if (l.get(i).layerNameString().equals(name)) return true;
                return false;
            } finally {
                l.free();
            }
        }
    }

    static List<VkPhysicalDevice> geraete(VkInstance inst) {
        try (MemoryStack s = stackPush()) {
            IntBuffer n = s.mallocInt(1);
            ok(vkEnumeratePhysicalDevices(inst, n, null), "vkEnumeratePhysicalDevices");
            PointerBuffer pp = s.mallocPointer(n.get(0));
            ok(vkEnumeratePhysicalDevices(inst, n, pp), "vkEnumeratePhysicalDevices");
            List<VkPhysicalDevice> out = new ArrayList<>();
            for (int i = 0; i < pp.capacity(); i++) out.add(new VkPhysicalDevice(pp.get(i), inst));
            return out;
        }
    }

    static VkQueueFamilyProperties.Buffer familien(VkPhysicalDevice d, MemoryStack s) {
        IntBuffer n = s.mallocInt(1);
        vkGetPhysicalDeviceQueueFamilyProperties(d, n, null);
        VkQueueFamilyProperties.Buffer f = VkQueueFamilyProperties.malloc(n.get(0), s);
        vkGetPhysicalDeviceQueueFamilyProperties(d, n, f);
        return f;
    }

    /** Erweiterungen des Geräts (die Liste liegt auf dem Heap: 150 Einträge zu 260 Byte sprengen den Stapel von LWJGL). */
    static Set<String> geraeteErweiterungen(VkPhysicalDevice d, MemoryStack s) {
        IntBuffer n = s.mallocInt(1);
        ok(vkEnumerateDeviceExtensionProperties(d, (String) null, n, null), "vkEnumerateDeviceExtensionProperties");
        VkExtensionProperties.Buffer e = VkExtensionProperties.malloc(n.get(0));
        try {
            ok(vkEnumerateDeviceExtensionProperties(d, (String) null, n, e), "vkEnumerateDeviceExtensionProperties");
            Set<String> out = new LinkedHashSet<>();
            for (int i = 0; i < e.capacity(); i++) out.add(e.get(i).extensionNameString());
            return out;
        } finally {
            e.free();
        }
    }

    private static PointerBuffer namen(MemoryStack s, List<String> l) {
        if (l.isEmpty()) return null;
        PointerBuffer pb = s.mallocPointer(l.size());
        for (String x : l) pb.put(s.UTF8(x));
        return pb.flip();
    }

    static String version(int v) {
        return VK_API_VERSION_MAJOR(v) + "." + VK_API_VERSION_MINOR(v) + "." + VK_API_VERSION_PATCH(v);
    }

    static void ok(int r, String was) {
        if (r != VK_SUCCESS) throw new IllegalStateException(was + ": " + fehler(r));
    }

    static String fehler(int r) {
        return switch (r) {
            case VK_NOT_READY -> "VK_NOT_READY";
            case VK_TIMEOUT -> "VK_TIMEOUT";
            case VK_INCOMPLETE -> "VK_INCOMPLETE";
            case VK_ERROR_OUT_OF_HOST_MEMORY -> "VK_ERROR_OUT_OF_HOST_MEMORY";
            case VK_ERROR_OUT_OF_DEVICE_MEMORY -> "VK_ERROR_OUT_OF_DEVICE_MEMORY";
            case VK_ERROR_INITIALIZATION_FAILED -> "VK_ERROR_INITIALIZATION_FAILED";
            case VK_ERROR_DEVICE_LOST -> "VK_ERROR_DEVICE_LOST";
            case VK_ERROR_LAYER_NOT_PRESENT -> "VK_ERROR_LAYER_NOT_PRESENT";
            case VK_ERROR_EXTENSION_NOT_PRESENT -> "VK_ERROR_EXTENSION_NOT_PRESENT";
            case VK_ERROR_FEATURE_NOT_PRESENT -> "VK_ERROR_FEATURE_NOT_PRESENT";
            case VK_ERROR_INCOMPATIBLE_DRIVER -> "VK_ERROR_INCOMPATIBLE_DRIVER (kein Vulkan-1.3-Treiber?)";
            case VK_ERROR_TOO_MANY_OBJECTS -> "VK_ERROR_TOO_MANY_OBJECTS";
            case VK_ERROR_FORMAT_NOT_SUPPORTED -> "VK_ERROR_FORMAT_NOT_SUPPORTED";
            case KHRSurface.VK_ERROR_SURFACE_LOST_KHR -> "VK_ERROR_SURFACE_LOST_KHR";
            case KHRSwapchain.VK_ERROR_OUT_OF_DATE_KHR -> "VK_ERROR_OUT_OF_DATE_KHR";
            case KHRSwapchain.VK_SUBOPTIMAL_KHR -> "VK_SUBOPTIMAL_KHR";
            default -> "Fehler " + r;
        };
    }

    @Override public void close() {
        vkDeviceWaitIdle(device);
        vmaDestroyAllocator(vma);
        vkDestroyCommandPool(device, pool, null);
        if (poolRechnen != NULL) vkDestroyCommandPool(device, poolRechnen, null);
        vkDestroyDevice(device, null);
        if (messenger != NULL) vkDestroyDebugUtilsMessengerEXT(instance, messenger, null);
        vkDestroyInstance(instance, null);
        if (rueckruf != null) rueckruf.free();
    }

    /** Für Meldungen: Bytes lesbar. */
    static String mb(long b) {
        return String.format(java.util.Locale.GERMAN, "%.1f MB", b / 1048576.0);
    }

    static String utf8(java.nio.ByteBuffer b) { return memUTF8(b); }
}
