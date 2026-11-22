import org.lwjgl.util.shaderc.ShadercIncludeResolve;
import org.lwjgl.util.shaderc.ShadercIncludeResult;
import org.lwjgl.util.shaderc.ShadercIncludeResultRelease;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

import static org.lwjgl.system.MemoryUtil.*;
import static org.lwjgl.util.shaderc.Shaderc.*;

/**
 * GLSL → SPIR-V für den Bau (HalligHooge P0.5, Werkbuch 6 „Bau“): übersetzt jede Datei {@code *.comp}, {@code *.vert},
 * {@code *.frag} unter der Quelle mit shaderc (Vulkan 1.3, SPIR-V 1.6, Optimierung auf Leistung) nach
 * {@code <ziel>/<pfad>.spv}. {@code #include "/com/dan/…"} wird gegen die Quelle aufgelöst, relativ zur Datei ohne
 * führenden Schrägstrich. Bricht mit der Meldung von shaderc ab. Aufruf aus Ant (Ziel {@code spirv}):
 * <pre>
 *   java -cp lib/lwjgl/lwjgl.jar;…shaderc… tools/SpirvBau.java src build/classes
 * </pre>
 * Nur Dateien unter einem Verzeichnis {@code p0/} oder mit {@code #version 450} oder höher werden übersetzt: Die
 * GLSL-430-Shader des Bestands (OpenGL) bleiben unberührt.
 */
public class SpirvBau {
    public static void main(String[] a) throws IOException {
        Path quelle = Path.of(a.length > 0 ? a[0] : "src"), ziel = Path.of(a.length > 1 ? a[1] : "build/classes");
        List<Path> dateien;
        try (Stream<Path> w = Files.walk(quelle)) {
            dateien = w.filter(p -> { String n = p.toString(); return n.endsWith(".comp") || n.endsWith(".vert") || n.endsWith(".frag"); }).sorted().collect(java.util.stream.Collectors.toList());
        }
        long compiler = shaderc_compiler_initialize();
        ShadercIncludeResolve aufloesen = ShadercIncludeResolve.create((nutzer, gewuenscht, typ, anfordernd, tiefe) -> {
            String w = memUTF8(gewuenscht), von = memUTF8(anfordernd);
            String rel = w.startsWith("/") ? w.substring(1) : Path.of(von).getParent() == null ? w : quelle.relativize(Path.of(von).getParent()).resolve(w).toString();
            Path p = quelle.resolve(rel);
            ShadercIncludeResult r = ShadercIncludeResult.calloc();
            try {
                r.source_name(memUTF8(p.toString(), false)).content(memUTF8(Files.readString(p, StandardCharsets.UTF_8), false));
            } catch (IOException e) {
                r.source_name(memUTF8("", false)).content(memUTF8("Include nicht gefunden: " + p, false));
            }
            return r.address();
        });
        ShadercIncludeResultRelease freigeben = ShadercIncludeResultRelease.create((nutzer, adresse) -> {
            ShadercIncludeResult r = ShadercIncludeResult.create(adresse);
            memFree(r.source_name());
            memFree(r.content());
            r.free();
        });
        int n = 0, ueber = 0;
        long t0 = System.nanoTime();
        try {
            for (Path d : dateien) {
                String text = Files.readString(d, StandardCharsets.UTF_8);
                boolean vulkan = d.toString().replace('\\', '/').contains("/p0/") || text.matches("(?s).*#version\\s+(4[5-9]0|460).*");
                if (!vulkan) { ueber++; continue; }
                String name = d.getFileName().toString();
                int art = name.endsWith(".comp") ? shaderc_compute_shader : name.endsWith(".vert") ? shaderc_vertex_shader : shaderc_fragment_shader;
                long opt = shaderc_compile_options_initialize();
                shaderc_compile_options_set_target_env(opt, shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_3);
                shaderc_compile_options_set_target_spirv(opt, shaderc_spirv_version_1_6);
                shaderc_compile_options_set_optimization_level(opt, shaderc_optimization_level_performance);
                shaderc_compile_options_set_include_callbacks(opt, aufloesen, freigeben, NULL);
                long r = shaderc_compile_into_spv(compiler, text, art, d.toString(), "main", opt);
                try {
                    if (shaderc_result_get_compilation_status(r) != shaderc_compilation_status_success) {
                        System.err.println(shaderc_result_get_error_message(r));
                        throw new IllegalStateException("SPIR-V: " + d + " lässt sich nicht übersetzen");
                    }
                    ByteBuffer spv = shaderc_result_get_bytes(r);
                    byte[] b = new byte[spv.remaining()];
                    spv.get(b);
                    Path aus = ziel.resolve(quelle.relativize(d).toString() + ".spv");
                    Files.createDirectories(aus.getParent());
                    Files.write(aus, b);
                    n++;
                } finally {
                    shaderc_result_release(r);
                    shaderc_compile_options_release(opt);
                }
            }
        } finally {
            shaderc_compiler_release(compiler);
            aufloesen.free();
            freigeben.free();
        }
        System.out.printf("SPIR-V: %d Shader übersetzt, %d des Bestands (GLSL 430) übergangen, %.0f ms%n", n, ueber, (System.nanoTime() - t0) / 1e6);
    }
}
