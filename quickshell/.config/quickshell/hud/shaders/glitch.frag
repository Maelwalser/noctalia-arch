#version 440

// A feed locking on (Glitch.qml): played over one pane's content when the
// desktop comes up on an empty workspace. A line of light crosses the pane
// from top to bottom, quick at first and easing out, and writes the content
// in behind it: nothing below the line, the rows just above it still torn
// sideways in bands with their colours pulled apart and glowing in the
// accent, the rows further up already at rest. The tear follows the line
// down and dies with it, so the run ends on the untouched content and the
// layer can be dropped without a step. Lengths are in u (the design grid,
// `unit` device pixels each); the output is premultiplied.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress; // 0 = blank, the line above the pane; 1 = the content as it is
    float seed;     // tells the panes apart, so they do not tear alike
    vec2 sizePx;    // the pane in device pixels
    float unit;     // device pixels per u
    vec4 accent;    // the line's colour (alpha 1)
};
layout(binding = 1) uniform sampler2D source;

const float SWEEP = 0.62;   // share of the run in which the line crosses the pane
const float STEPS = 11.0;   // the tear is redrawn this often over the run: stepped, as a decoder would
const float SETTLE = 46.0;  // u behind the line over which the rows come to rest
const float TEAR = 15.0;    // u: the furthest a band is thrown sideways
const float SPLIT = 2.5;    // u: how far red and blue part at the line
const float WARM = 30.0;    // u behind the line that still glow in the accent
const float TAIL = 12.0;    // u: the line's afterglow

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float y = uv.y * sizePx.y / unit;                 // u from the pane's top
    float h = sizePx.y / unit;

    float s = clamp(progress / SWEEP, 0.0, 1.0);
    float line = mix(-6.0, h + 6.0, 1.0 - pow(1.0 - s, 3.0));
    float behind = line - y;                          // u; > 0 once the line has passed
    // The line is there while it crosses; whatever still moves after it has
    // left fades with the rest of the run.
    float lit = smoothstep(0.0, 0.08, progress) * (1.0 - smoothstep(SWEEP * 0.9, SWEEP * 1.15, progress));
    float rest = 1.0 - smoothstep(SWEEP * 0.7, 1.0, progress);
    float unrest = behind > 0.0 ? exp(-behind / SETTLE) * rest : 0.0;

    // Bands of two sizes; most of them stay put on any one step.
    float tick = floor(progress * STEPS) + seed * 17.0;
    float wide = floor(y / 21.0), fine = floor(y / 5.0);
    float shift = 0.0;
    if (hash(vec2(wide, tick)) > 0.50)
        shift += (hash(vec2(wide + 31.0, tick)) - 0.5) * 2.0 * TEAR;
    if (hash(vec2(fine, tick + 5.0)) > 0.86)
        shift += (hash(vec2(fine + 57.0, tick)) - 0.5) * TEAR;
    // Whole device pixels, so torn text stays as crisp as text at rest.
    float dx = floor(shift * unrest * unit + 0.5) / sizePx.x;
    float ca = floor(SPLIT * unrest * unit + 0.5) / sizePx.x;

    vec4 r = texture(source, vec2(uv.x + dx + ca, uv.y));
    vec4 g = texture(source, vec2(uv.x + dx, uv.y));
    vec4 b = texture(source, vec2(uv.x + dx - ca, uv.y));
    vec4 c = vec4(r.r, g.g, b.b, max(g.a, max(r.a, b.a)));

    // Fresh off the line the content glows in its colour, then cools.
    float warm = behind > 0.0 ? exp(-behind / WARM) * lit : 0.0;
    c.rgb = mix(c.rgb, accent.rgb * c.a, 0.75 * warm);
    c *= smoothstep(0.0, 1.5, behind);

    // The line: a hard core, a short afterglow above it, thinning out
    // towards both ends so it never meets the pane's rounded corners.
    float ends = smoothstep(0.0, 0.2, uv.x) * smoothstep(0.0, 0.2, 1.0 - uv.x);
    float core = exp(-abs(behind) / 0.9);
    float tail = behind > 0.0 ? 0.22 * exp(-behind / TAIL) : 0.0;
    float a = clamp((core + tail) * ends * lit, 0.0, 1.0);

    fragColor = (c * (1.0 - a) + vec4(accent.rgb * a, a)) * qt_Opacity;
}
