#version 440

// Unlock reveal (UnlockFold.qml): the lock screen is a sheet of glass split
// down the middle into two sliding doors. They part sideways on a rail, the
// scene printed on them dissolving into frost that the desktop shows through
// (hyprglass blurs whatever this layer leaves translucent and lights the
// outline, hyprland/plugins.lua), until each door has left its side of the
// screen. Coordinates: x across the screen from the centre and y up, in screen
// widths; distances from an edge in device pixels. The output is premultiplied:
// the alpha is the door's presence, which is also the glass strength the
// compositor reads off this layer.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0 = shut (the lock scene as is), 1 = open (gone)
    float aspect;     // width / height
    float pxPerUnit;  // device pixels across the screen width
    vec4 veil;        // frost colour (alpha 1: Qt premultiplies colour uniforms)
    vec4 accent;      // palette primary: the border's colour
    vec4 warm;        // palette highlight, warms the core of the light band
    float veilShare;  // how much of the door's presence the frost colour fills
};
layout(binding = 1) uniform sampler2D src;

const float TRAVEL = 0.54;      // each door slides this far (screen widths): its half, plus the border
const float SHEEN_X = 0.23;     // the two light bands on the glass, either side of the centre
const float INNER_LINE = 22.0;  // the border's second hairline, px in from the edge
const float TICK_STEP = 48.0;   // ruler ticks between the two lines, px apart

// Doors on a rail: a gentle start, then a long glide out.
float slide(float t) {
    float s = t * t * (3.0 - 2.0 * t);
    float o = 1.0 - pow(1.0 - t, 3.0);
    return mix(s, o, 0.5);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float x = uv.x - 0.5;
    float y = (0.5 - uv.y) / aspect;

    float p = clamp(progress, 0.0, 1.0);
    float s = slide(p) * TRAVEL;

    // Which door the pixel is under, and how far in from its inner edge. The
    // coverage ramps over the pixel just outside the edge, so the two doors
    // meet without a seam while shut.
    float side = x >= 0.0 ? 1.0 : -1.0;
    float e = (abs(x) - s) * pxPerUnit;
    float c0 = smoothstep(-1.0, 0.0, e);
    float ep = max(e, 0.0);

    // The lock scene printed on the door, carried along with it. The thick
    // edge bends the print a little, as the compositor bends the desktop.
    float lens = exp(-ep / 22.0);
    vec2 tex = vec2(uv.x - side * s + side * 0.012 * lens, uv.y);
    vec3 lock = texture(src, clamp(tex, 0.0, 1.0)).rgb;

    // The border: the lit thickness of the glass at the edge, a dark groove
    // behind it, a soft glow inside, and a second hairline further in with
    // ruler ticks between the two. The lit edge and the hairline also raise
    // the door's presence, so they can be brighter than the frost. Faded in
    // so frame one is the untouched lock scene.
    float fade = smoothstep(0.0, 0.12, p);
    float bevel = min(exp(-ep / 1.3) * 0.9 + smoothstep(5.0, 0.0, ep) * 0.4, 1.0);
    float groove = smoothstep(5.5, 7.0, ep) * smoothstep(10.0, 8.5, ep) * 0.35;
    float glow = exp(-ep / 20.0) * 0.22;
    float d = ep - INNER_LINE;
    float inner = exp(-d * d / 1.6) * 0.5;
    float yp = y * pxPerUnit;
    float row = mod(yp + TICK_STEP * 0.5, TICK_STEP) - TICK_STEP * 0.5;
    float tick = exp(-row * row / 0.8)
               * smoothstep(INNER_LINE - 1.0, INNER_LINE + 1.0, ep)
               * smoothstep(INNER_LINE + 9.0, INNER_LINE + 7.0, ep) * 0.35;
    vec3 rimCol = mix(vec3(1.0), accent.rgb, 0.55);
    vec3 lineCol = mix(vec3(1.0), accent.rgb, 0.8);

    // Glass optics: two soft bands of light fixed to the room, which the doors
    // slide through, leaning a little as a light above and to one side would;
    // and a touch more light near the top of the sheet.
    float xs = x + 0.10 * y;
    float d1 = xs - SHEEN_X, d2 = xs + SHEEN_X;
    float band = exp(-d1 * d1 / 0.0020) + exp(-d2 * d2 / 0.0020);
    float core = exp(-d1 * d1 / 0.00015) + exp(-d2 * d2 / 0.00015);
    vec3 sheen = band * 0.16 * mix(vec3(1.0), veil.rgb, 0.5)
               + core * 0.10 * mix(vec3(1.0), warm.rgb, 0.3);
    float top = 0.04 * smoothstep(-0.5, 0.5, y * aspect * 2.0);

    // Print -> frost. The print fades into the frost over the first stretch;
    // the frost then rides the door out.
    float print = c0 * (1.0 - smoothstep(0.0, 0.45, p));
    float frost = c0 * 0.44;
    float body = max(print, frost);
    float rimA = c0 * fade * clamp(bevel * 1.3 + inner * 1.2, 0.0, 1.0);
    float A = max(body, rimA);
    float v = (body - print) * veilShare;

    vec3 rgb = (lock * print + veil.rgb * v) * (1.0 - groove * fade)
             + (sheen + top) * A * fade
             + rimCol * (bevel + glow) * A * fade
             + lineCol * (inner + tick) * A * fade;

    // The doors throw a soft shadow on the desktop in the gap, with a tight
    // contact line at the edge. Kept under the glass mask threshold
    // (hyprland/plugins.lua), so it stays a shadow on sharp desktop and does
    // not widen the door's outline.
    float gap = max(-e, 0.0);
    float shadow = (0.07 * exp(-gap / 90.0) + 0.04 * exp(-gap / 5.0)) * step(0.0, -e) * (1.0 - c0)
                 * smoothstep(0.0, 0.25, p) * (1.0 - smoothstep(0.85, 1.0, p));

    // Premultiplied: the highlights may not push a channel past the alpha.
    float a = clamp(A + shadow * (1.0 - A), 0.0, 1.0);
    fragColor = vec4(min(rgb, vec3(a)), a) * qt_Opacity;
}
