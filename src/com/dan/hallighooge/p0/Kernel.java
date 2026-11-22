package com.dan.hallighooge.p0;

import org.lwjgl.system.MemoryStack;
import org.lwjgl.vulkan.*;

import java.nio.ByteBuffer;
import java.nio.LongBuffer;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.vulkan.KHRAccelerationStructure.VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;
import static org.lwjgl.vulkan.VK13.*;

/**
 * Eine Rechen-Pipeline: SPIR-V, Satz 0 mit festen Bindungen (Speicherpuffer oder Beschleunigungsstruktur), Push-Konstanten.
 * Deskriptorsätze werden je Belegung einmal angelegt und wiederverwendet ({@link #satz}).
 */
final class Kernel implements AutoCloseable {
    final Vulkan vk;
    final long modul, satzLayout, layout, pipeline, satzPool;
    final int[] typen;
    final int pushGroesse;
    private final Map<String, Long> saetze = new HashMap<>();

    /** typen: je Bindung VK_DESCRIPTOR_TYPE_STORAGE_BUFFER oder …_ACCELERATION_STRUCTURE_KHR. */
    Kernel(Vulkan vk, ByteBuffer spirv, int[] typen, int pushGroesse) {
        this.vk = vk;
        this.typen = typen.clone();
        this.pushGroesse = pushGroesse;
        try (MemoryStack s = stackPush()) {
            LongBuffer lb = s.mallocLong(1);
            VkShaderModuleCreateInfo mi = VkShaderModuleCreateInfo.calloc(s).sType$Default().pCode(spirv);
            Vulkan.ok(vkCreateShaderModule(vk.device, mi, null, lb), "vkCreateShaderModule");
            modul = lb.get(0);

            VkDescriptorSetLayoutBinding.Buffer b = VkDescriptorSetLayoutBinding.calloc(typen.length, s);
            for (int i = 0; i < typen.length; i++)
                b.get(i).binding(i).descriptorType(typen[i]).descriptorCount(1).stageFlags(VK_SHADER_STAGE_COMPUTE_BIT);
            Vulkan.ok(vkCreateDescriptorSetLayout(vk.device, VkDescriptorSetLayoutCreateInfo.calloc(s).sType$Default().pBindings(b), null, lb),
                    "vkCreateDescriptorSetLayout");
            satzLayout = lb.get(0);

            VkPipelineLayoutCreateInfo li = VkPipelineLayoutCreateInfo.calloc(s).sType$Default().pSetLayouts(s.longs(satzLayout));
            if (pushGroesse > 0)
                li.pPushConstantRanges(VkPushConstantRange.calloc(1, s).stageFlags(VK_SHADER_STAGE_COMPUTE_BIT).offset(0).size(pushGroesse));
            Vulkan.ok(vkCreatePipelineLayout(vk.device, li, null, lb), "vkCreatePipelineLayout");
            layout = lb.get(0);

            VkComputePipelineCreateInfo.Buffer ci = VkComputePipelineCreateInfo.calloc(1, s);
            ci.get(0).sType$Default().layout(layout)
                    .stage(VkPipelineShaderStageCreateInfo.calloc(s).sType$Default().stage(VK_SHADER_STAGE_COMPUTE_BIT).module(modul).pName(s.UTF8("main")));
            Vulkan.ok(vkCreateComputePipelines(vk.device, VK_NULL_HANDLE, ci, null, lb), "vkCreateComputePipelines");
            pipeline = lb.get(0);

            int nSp = 0, nAs = 0;
            for (int t : typen) if (t == VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR) nAs++; else nSp++;
            int saetzeMax = 32;
            VkDescriptorPoolSize.Buffer ps = VkDescriptorPoolSize.calloc(nAs > 0 && nSp > 0 ? 2 : 1, s);
            int k = 0;
            if (nSp > 0) ps.get(k++).type(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER).descriptorCount(nSp * saetzeMax);
            if (nAs > 0) ps.get(k).type(VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR).descriptorCount(nAs * saetzeMax);
            Vulkan.ok(vkCreateDescriptorPool(vk.device, VkDescriptorPoolCreateInfo.calloc(s).sType$Default().maxSets(saetzeMax).pPoolSizes(ps), null, lb),
                    "vkCreateDescriptorPool");
            satzPool = lb.get(0);
        }
    }

    /**
     * Deskriptorsatz für diese Belegung (je Bindung ein Puffer-Handle, oder für eine Beschleunigungsstruktur deren Handle);
     * gleiche Belegung gibt denselben Satz.
     */
    long satz(long... handles) {
        String key = Arrays.toString(handles);
        Long da = saetze.get(key);
        if (da != null) return da;
        if (handles.length != typen.length) throw new IllegalArgumentException("Kernel: " + typen.length + " Bindungen, " + handles.length + " Handles");
        try (MemoryStack s = stackPush()) {
            LongBuffer lb = s.mallocLong(1);
            Vulkan.ok(vkAllocateDescriptorSets(vk.device, VkDescriptorSetAllocateInfo.calloc(s).sType$Default()
                    .descriptorPool(satzPool).pSetLayouts(s.longs(satzLayout)), lb), "vkAllocateDescriptorSets");
            long set = lb.get(0);
            VkWriteDescriptorSet.Buffer w = VkWriteDescriptorSet.calloc(typen.length, s);
            for (int i = 0; i < typen.length; i++) {
                VkWriteDescriptorSet x = w.get(i).sType$Default().dstSet(set).dstBinding(i).descriptorCount(1).descriptorType(typen[i]);
                if (typen[i] == VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR) {
                    VkWriteDescriptorSetAccelerationStructureKHR as = VkWriteDescriptorSetAccelerationStructureKHR.calloc(s).sType$Default()
                            .pAccelerationStructures(s.longs(handles[i]));
                    x.pNext(as.address());
                } else {
                    x.pBufferInfo(VkDescriptorBufferInfo.calloc(1, s).buffer(handles[i]).offset(0).range(VK_WHOLE_SIZE));
                }
            }
            vkUpdateDescriptorSets(vk.device, w, null);
            saetze.put(key, set);
            return set;
        }
    }

    /** Pipeline, Satz, Push-Konstanten (oder null) und Ausführung aufnehmen; danach eine {@link Vulkan#sperre}. */
    void aufnehmen(VkCommandBuffer c, long satz, ByteBuffer push, int gx, int gy, int gz) {
        try (MemoryStack s = stackPush()) {
            vkCmdBindPipeline(c, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            vkCmdBindDescriptorSets(c, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, s.longs(satz), null);
            if (push != null && pushGroesse > 0) {
                ByteBuffer p = push.duplicate();
                p.limit(Math.min(p.capacity(), pushGroesse)).position(0);
                vkCmdPushConstants(c, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, p);
            }
            vkCmdDispatch(c, gx, gy, gz);
        }
        Vulkan.sperre(c);
    }

    @Override public void close() {
        vkDestroyPipeline(vk.device, pipeline, null);
        vkDestroyPipelineLayout(vk.device, layout, null);
        vkDestroyDescriptorPool(vk.device, satzPool, null);
        vkDestroyDescriptorSetLayout(vk.device, satzLayout, null);
        vkDestroyShaderModule(vk.device, modul, null);
    }
}
