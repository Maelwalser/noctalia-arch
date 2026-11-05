// ACID//HUD CRT pass for Ghostty: faint scanlines, a light bloom on bright
// glyphs (the acid accent glows a little) and a soft vignette. Static: no
// iTime, so Ghostty only re-runs it when the terminal content changes.

const float BLOOM_THRESHOLD = 0.55;
const float BLOOM_STRENGTH = 0.85;
const float SCANLINE_DEPTH = 0.07;   // 0 = off
const float SCANLINE_PERIOD = 3.0;   // physical pixels
const float VIGNETTE = 0.32;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 base = texture(iChannel0, uv);
    vec2 px = 1.0 / iResolution.xy;

    // Ring-sampled bloom of whatever is brighter than the threshold.
    vec3 bloom = vec3(0.0);
    const int TAPS = 12;
    for (int i = 0; i < TAPS; i++) {
        float a = 6.2831853 * float(i) / float(TAPS);
        vec2 dir = vec2(cos(a), sin(a)) * px;
        for (int r = 1; r <= 3; r++) {
            vec3 s = texture(iChannel0, uv + dir * float(r) * 2.4).rgb;
            bloom += max(s - BLOOM_THRESHOLD, 0.0);
        }
    }
    bloom /= float(TAPS * 3);

    vec3 col = base.rgb + bloom * BLOOM_STRENGTH;
    col *= 1.0 - SCANLINE_DEPTH * (0.5 + 0.5 * cos(fragCoord.y * 6.2831853 / SCANLINE_PERIOD));
    vec2 d = uv - 0.5;
    col *= 1.0 - dot(d, d) * VIGNETTE;

    fragColor = vec4(col, base.a);
}
