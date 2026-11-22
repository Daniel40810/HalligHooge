// flaeche.frag — P0.2: bewegte See aus überlagerten Wellen (Phasengeschwindigkeit nach Tiefwasser), Last in Wellenzahl
// zuschaltbar; oben ein Zeitbalken, an dem Ruckeln sichtbar wird.
#version 450
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 farbe;
layout(push_constant) uniform Bild { vec4 werte; } pk;   // Zeit (s), Breite, Höhe, zusätzliche Wellen (Last)

void main() {
    float t = pk.werte.x;
    vec2 p = uv * vec2(pk.werte.y / max(pk.werte.z, 1.0), 1.0) * 6.0;
    int n = 6 + int(pk.werte.w);
    float h = 0.0;
    for (int i = 0; i < n; i++) {
        float k = 1.0 + float(i) * 0.37;
        vec2 d = vec2(cos(float(i) * 2.399), sin(float(i) * 2.399));
        h += sin(dot(p, d) * k + t * sqrt(9.81 * k)) / k;
    }
    h /= sqrt(float(n));
    vec3 c = mix(vec3(0.02, 0.09, 0.14), vec3(0.12, 0.44, 0.52), clamp(0.5 + 0.5 * h, 0.0, 1.0));
    if (abs(uv.x - fract(t * 0.25)) < 0.003 && uv.y < 0.04) c = vec3(0.95, 0.86, 0.56);
    farbe = vec4(c, 1.0);
}
