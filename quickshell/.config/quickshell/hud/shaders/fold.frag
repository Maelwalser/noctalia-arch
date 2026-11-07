#version 440

// Unlock reveal (UnlockFold.qml): the lock screen is a sheet of glass split
// down the middle into two doors. The lock scene already is the sheet: its
// light bands are baked into the lock art (hud-build, fold_glass, the same
// formulas), so at progress 0 this draws the scene untouched and the handoff
// from the lock surface to this window is invisible. The seam then appears
// at the centre of the screen and stretches up and down to the edges, the
// doors part along it, their inner edges sweeping outwards and wiping the
// scene away, the scene going a little translucent so the blurred desktop
// glows through it (hyprglass blurs whatever this layer leaves translucent,
// hyprland/plugins.lua), until the desktop stands alone. Coordinates: x
// across the screen from the centre and y up, in screen widths; distances
// from an edge in device pixels. The output is premultiplied: the alpha is
// the door's presence, which is also the glass strength the compositor
// reads off this layer.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0 = shut (the lock scene as is), 1 = open (gone)
    float aspect;     // width / height
    float pxPerUnit;  // device pixels across the screen width
    vec4 accent;      // palette primary: the border's colour (alpha 1: Qt premultiplies colour uniforms)
    float glassShare; // how much of the lock scene gives way to the desktop behind the glass
    float glassDim;   // how much of the desktop's light the glass lets through for it (the lock
                      // backdrop is a darkened wallpaper, so this keeps the brightness even)
};
layout(binding = 1) uniform sampler2D src;

const float SPLIT = 0.11;       // share of the run in which the seam stretches out, before the doors move
const float TIP = 96.0;         // px over which the seam's ends fade: it moves ~100 px a frame, so a
                                //   shorter tip stepped (the ticks blinked out one by one)
const float TRAVEL = 0.54;      // each door slides this far (screen widths): its half, plus the border
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
    // First the seam: lit from the centre outwards until it spans the
    // screen, the doors standing still; then the travel. The seam's reach,
    // in px from the vertical centre, gates every edge light below, so the
    // edges stay dark where the seam has not arrived yet.
    float ps = clamp(p / SPLIT, 0.0, 1.0);
    float t = clamp((p - SPLIT) / (1.0 - SPLIT), 0.0, 1.0);
    float s = slide(t) * TRAVEL;
    float halfH = 0.5 / aspect * pxPerUnit;
    float yp = y * pxPerUnit;
    float reach = ps * (halfH + TIP);
    float fade = 1.0 - smoothstep(reach - TIP, reach, abs(yp));
    // The translucency comes in over the first stretch of travel.
    float see = glassShare * smoothstep(0.0, 0.15, t);

    // Which door the pixel is under, and how far in from its inner edge. The
    // coverage ramps over the pixel just outside the edge, so the two doors
    // meet without a seam while shut.
    float side = x >= 0.0 ? 1.0 : -1.0;
    float e = (abs(x) - s) * pxPerUnit;
    float c0 = smoothstep(-1.0, 0.0, e);
    float ep = max(e, 0.0);

    // The lock scene, fixed to the screen: the door's edge wipes over it.
    // The thick edge bends the scene a little, as a lens would, once the
    // doors part (not while the seam alone draws over the shut sheet, where
    // the bend would shift the scene as the seam passed).
    float lens = exp(-ep / 22.0) * smoothstep(0.0, 0.08, t);
    vec2 tex = vec2(uv.x + side * 0.012 * lens, uv.y);
    vec3 lock = texture(src, clamp(tex, 0.0, 1.0)).rgb;

    // The border: the lit thickness of the glass at the edge, a dark groove
    // behind it, a soft glow inside, and a second hairline further in with
    // ruler ticks between the two. The lit edge and the hairline also raise
    // the door's presence, so they can be brighter than the glass.
    float bevel = min(exp(-ep / 1.3) * 0.9 + smoothstep(5.0, 0.0, ep) * 0.4, 1.0);
    float groove = smoothstep(5.5, 7.0, ep) * smoothstep(10.0, 8.5, ep) * 0.35;
    float glow = exp(-ep / 20.0) * 0.22;
    float d = ep - INNER_LINE;
    float inner = exp(-d * d / 1.6) * 0.5;
    float row = mod(yp + TICK_STEP * 0.5, TICK_STEP) - TICK_STEP * 0.5;
    float tick = exp(-row * row / 0.8)
               * smoothstep(INNER_LINE - 1.0, INNER_LINE + 1.0, ep)
               * smoothstep(INNER_LINE + 9.0, INNER_LINE + 7.0, ep) * 0.35;
    vec3 rimCol = mix(vec3(1.0), accent.rgb, 0.55);
    vec3 lineCol = mix(vec3(1.0), accent.rgb, 0.8);

    // The scene keeps its brightness: it gives up a share of itself to the
    // blurred desktop behind, which is let through dimmed to the same level,
    // and stays like that until the edge wipes it. The rest of the presence
    // is dark glass.
    float print = c0 * (1.0 - see);
    float rimA = c0 * fade * clamp(bevel * 1.3 + inner * 1.2, 0.0, 1.0);
    float A = max(c0 * (1.0 - see * glassDim), rimA);

    vec3 rgb = lock * print * (1.0 - groove * fade)
             + rimCol * (bevel + glow) * A * fade
             + lineCol * (inner + tick) * A * fade;

    // The doors throw a soft shadow on the desktop in the gap, with a tight
    // contact line at the edge. Kept under the glass mask threshold
    // (hyprland/plugins.lua), so it stays a shadow on sharp desktop and does
    // not widen the door's outline.
    float gap = max(-e, 0.0);
    float shadow = (0.07 * exp(-gap / 90.0) + 0.04 * exp(-gap / 5.0)) * step(0.0, -e) * (1.0 - c0)
                 * smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.85, 1.0, t));

    // Premultiplied: the highlights may not push a channel past the alpha.
    float a = clamp(A + shadow * (1.0 - A), 0.0, 1.0);
    fragColor = vec4(min(rgb, vec3(a)), a) * qt_Opacity;
}
