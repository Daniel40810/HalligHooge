package com.dan.hallighooge.p0;

import org.lwjgl.PointerBuffer;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.util.vma.VmaAllocationCreateInfo;
import org.lwjgl.util.vma.VmaAllocationInfo;
import org.lwjgl.vulkan.VkBufferCopy;
import org.lwjgl.vulkan.VkBufferCreateInfo;
import org.lwjgl.vulkan.VkBufferDeviceAddressInfo;

import java.nio.ByteBuffer;
import java.nio.LongBuffer;

import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.system.MemoryUtil.*;
import static org.lwjgl.util.vma.Vma.*;
import static org.lwjgl.vulkan.VK13.*;

/**
 * Ein Puffer über VMA: auf dem Gerät (nicht abgebildet, Daten über einen Zwischenpuffer) oder beim Prozessor (abgebildet,
 * zwischengespeichert, für Rückgabe und Zwischenpuffer). Die 680M teilt den Hauptspeicher, aber nur der gerätelokale Teil
 * ist für die Messung maßgeblich.
 */
final class Puffer implements AutoCloseable {
    final Vulkan vk;
    final long handle, allocation, groesse;
    /** Abgebildeter Zeiger (nur beim Prozessor), sonst 0. */
    final long abbild;
    private boolean zu;

    private Puffer(Vulkan vk, long groesse, int nutzung, boolean wirt) {
        this.vk = vk;
        this.groesse = groesse;
        try (MemoryStack s = stackPush()) {
            int u = nutzung | VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
            if (!vk.adressen) u &= ~VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
            VkBufferCreateInfo bi = VkBufferCreateInfo.calloc(s).sType$Default()
                    .size(groesse).usage(u).sharingMode(VK_SHARING_MODE_EXCLUSIVE);
            VmaAllocationCreateInfo ai = VmaAllocationCreateInfo.calloc(s);
            if (wirt) ai.usage(VMA_MEMORY_USAGE_AUTO_PREFER_HOST).flags(VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT | VMA_ALLOCATION_CREATE_MAPPED_BIT);
            else ai.usage(VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE);
            LongBuffer lb = s.mallocLong(1);
            PointerBuffer pa = s.mallocPointer(1);
            VmaAllocationInfo info = VmaAllocationInfo.calloc(s);
            Vulkan.ok(vmaCreateBuffer(vk.vma, bi, ai, lb, pa, info), "vmaCreateBuffer (" + Vulkan.mb(groesse) + ")");
            handle = lb.get(0);
            allocation = pa.get(0);
            abbild = wirt ? info.pMappedData() : NULL;
        }
    }

    /** Auf dem Gerät; Nutzung zusätzlich zu Übertragung hin und zurück. */
    static Puffer geraet(Vulkan vk, long groesse, int nutzung) { return new Puffer(vk, Math.max(16, groesse), nutzung, false); }

    /** Beim Prozessor, abgebildet. */
    static Puffer wirt(Vulkan vk, long groesse, int nutzung) { return new Puffer(vk, Math.max(16, groesse), nutzung, true); }

    static Puffer speicher(Vulkan vk, long groesse) { return geraet(vk, groesse, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT); }

    long adresse() {
        try (MemoryStack s = stackPush()) {
            return vkGetBufferDeviceAddress(vk.device, VkBufferDeviceAddressInfo.calloc(s).sType$Default().buffer(handle));
        }
    }

    // ------------------------------------------------------------------ Daten

    void schreiben(ByteBuffer daten, long versatz) {
        long n = daten.remaining();
        if (abbild != NULL) {
            memCopy(memAddress(daten), abbild + versatz, n);
            vmaFlushAllocation(vk.vma, allocation, versatz, n);
            return;
        }
        try (Puffer z = wirt(vk, n, 0)) {
            memCopy(memAddress(daten), z.abbild, n);
            vmaFlushAllocation(vk.vma, z.allocation, 0, n);
            vk.einmal(c -> {
                try (MemoryStack s = stackPush()) {
                    vkCmdCopyBuffer(c, z.handle, handle, VkBufferCopy.calloc(1, s).srcOffset(0).dstOffset(versatz).size(n));
                }
            });
        }
    }

    void lesen(ByteBuffer ziel, long versatz) {
        long n = ziel.remaining();
        if (abbild != NULL) {
            vmaInvalidateAllocation(vk.vma, allocation, versatz, n);
            memCopy(abbild + versatz, memAddress(ziel), n);
            return;
        }
        try (Puffer z = wirt(vk, n, 0)) {
            vk.einmal(c -> {
                try (MemoryStack s = stackPush()) {
                    vkCmdCopyBuffer(c, handle, z.handle, VkBufferCopy.calloc(1, s).srcOffset(versatz).dstOffset(0).size(n));
                }
            });
            vmaInvalidateAllocation(vk.vma, z.allocation, 0, n);
            memCopy(z.abbild, memAddress(ziel), n);
        }
    }

    void schreiben(float[] f) {
        ByteBuffer b = memAlloc(f.length * 4);
        try {
            b.asFloatBuffer().put(f);
            schreiben(b, 0);
        } finally { memFree(b); }
    }

    void schreiben(int[] f) {
        ByteBuffer b = memAlloc(f.length * 4);
        try {
            b.asIntBuffer().put(f);
            schreiben(b, 0);
        } finally { memFree(b); }
    }

    float[] floats(int n) {
        ByteBuffer b = memAlloc(n * 4);
        try {
            lesen(b, 0);
            float[] f = new float[n];
            b.asFloatBuffer().get(f);
            return f;
        } finally { memFree(b); }
    }

    int[] ints(int n) {
        ByteBuffer b = memAlloc(n * 4);
        try {
            lesen(b, 0);
            int[] f = new int[n];
            b.asIntBuffer().get(f);
            return f;
        } finally { memFree(b); }
    }

    /** Auf dem Gerät mit Nullen füllen. */
    void nullen() { vk.einmal(c -> vkCmdFillBuffer(c, handle, 0, VK_WHOLE_SIZE, 0)); }

    @Override public void close() {
        if (zu) return;
        zu = true;
        vmaDestroyBuffer(vk.vma, handle, allocation);
    }
}
