#version 440

// Unlock reveal (UnlockFold.qml): the lock screen is a sheet of glass split
// down the middle into two doors. The lock scene already is the sheet: its
// light bands are baked into the lock art (hud-build, fold_glass), so at
// progress 0 this draws the scene untouched and the handoff from the lock
// surface to this window is invisible. Then, as one gesture:
//   the seam   a spark at the centre of the screen stretches into a line of
//              light, tapered towards its ends, that runs out to the top and
//              bottom edges and flares as it gets there; the border's
//              hairlines and ruler ticks follow it a beat behind;
//   the doors  already moving by then (the two overlap, so nothing stops
//              and starts): the sheet parts along the line, each door's cut
//              edge showing the thickness of the glass (a hot line on the
//              corner, a clear band that bends and splits the light behind
//              it, the back corner, a shade where the body begins), and
//              sweeps outwards wiping the scene away, the scene a little
//              translucent so the blurred desktop glows through it
//              (hyprglass blurs whatever this layer leaves translucent,
//              hyprland/plugins.lua), until the desktop stands alone.
// The lock plays the same run backwards: the doors land softly, the line
// flares where they meet, draws back into the centre and goes out.
// Coordinates: x across the screen from the centre and y up, in screen
// widths; distances from an edge in logical pixels (`unit` device pixels
// each). The output is premultiplied: the alpha is the door's presence,
// which is also the glass strength the compositor reads off this layer.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0 = shut (the lock scene as is), 1 = open (gone)
    float aspect;     // width / height
    float pxPerUnit;  // device pixels across the screen width
    float unit;       // device pixels per logical pixel
    vec4 accent;      // palette primary: the border's colour (alpha 1: Qt premultiplies colour uniforms)
    float glassShare; // how much of the lock scene gives way to the desktop behind the glass
    float glassDim;   // how much of the desktop's light the glass lets through for it (the lock
                      // backdrop is a darkened wallpaper, so this keeps the brightness even)
};
layout(binding = 1) uniform sampler2D src;

const float SEAM = 0.25;        // share of the run in which the line stretches out
const float FOLLOW = 0.040;     // the hairlines and ticks start this much later
const float OPEN = 0.095;       // the doors start here, while the line is still on its way
const float TAPER = 0.40;       // share of the line's reach over which its ends thin out: a share,
                                //   not a length, so the ends scale with the line and never step
                                //   (it covers hundreds of px a frame at first)
const float TRAVEL = 0.52;      // each door slides this far (screen widths): its half and the border
const float GLIDE = 0.82;       // the share of the doors' glide to a stop that is played: they are
                                //   off the screen before they would come to rest, so the run has
                                //   no dead end (and the lock, played backwards, no dead start:
                                //   the doors are on screen, at speed, the frame it begins)
const float EDGE = 9.0;         // the glass's thickness as seen at the cut, px
const float CLEAR = 0.42;       // how much of the scene the cut's band gives up to the desktop
const float INNER_LINE = 15.0;  // the border's hairline, px in from the edge
const float TICK_STEP = 32.0;   // ruler ticks along it, px apart

float easeOut(float v) {
    float i = 1.0 - v;
    return 1.0 - i * i;
}

// Doors on a rail: they ease out of rest (no jolt), are at speed by a third
// of the way and glide out the rest.
float rail(float t) {
    float u = 1.0 - pow(1.0 - t, 1.5);
    return u * u * (3.0 - 2.0 * u);
}
float slide(float t) {
    return rail(t * GLIDE) / rail(GLIDE);
}

// 1 at 0, falling smoothly to 0 at +-1.
float bell(float v) {
    float b = 1.0 - min(v * v, 1.0);
    return b * b;
}

// How far along the screen's height a line has drawn itself: 1 where it is
// whole, falling to 0 over its tapered end.
float drawn(float g, float halfH, float ay) {
    float reach = max(g * (halfH + 2.0) / (1.0 - TAPER), 0.001);
    return 1.0 - smoothstep(reach * (1.0 - TAPER), reach, ay);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(progress, 0.0, 1.0);
    if (p <= 0.0) {
        // Shut: the scene itself, to the bit.
        fragColor = texture(src, uv) * qt_Opacity;
        return;
    }

    float x = uv.x - 0.5;
    float y = (0.5 - uv.y) / aspect;
    float side = x >= 0.0 ? 1.0 : -1.0;
    float halfH = 0.5 / aspect * pxPerUnit / unit;  // logical px
    float yp = y * pxPerUnit / unit;
    float xp = x * pxPerUnit / unit;

    // The line, then its followers.
    float lit = drawn(easeOut(clamp(p / SEAM, 0.0, 1.0)), halfH, abs(yp));
    float litLate = drawn(easeOut(clamp((p - FOLLOW) / SEAM, 0.0, 1.0)), halfH, abs(yp));
    // The spark it starts from, and the flare as it arrives and the doors let go.
    float spark = bell((p - 0.045) / 0.045);
    float flare = bell((p - 0.15) / 0.15);

    // The doors.
    float t = clamp((p - OPEN) / (1.0 - OPEN), 0.0, 1.0);
    float s = slide(t) * TRAVEL;
    float open = smoothstep(0.0, 0.10, t);
    float leaving = 1.0 - smoothstep(0.85, 1.0, t);
    // The translucency comes in over the first stretch of travel.
    float see = glassShare * smoothstep(0.0, 0.15, t);

    // How far in from its door's inner edge the pixel is. The coverage ramps
    // over the device pixel just outside the edge, so the two doors meet
    // without a seam while shut.
    float e = (abs(x) - s) * pxPerUnit;
    float c0 = smoothstep(-1.0, 0.0, e);
    float ep = max(e, 0.0) / unit;
    float gap = max(-e, 0.0) / unit;

    // The lock scene, fixed to the screen: the door's edge wipes over it.
    // The thick edge bends the scene as a lens would, the colours by
    // slightly different amounts, once the doors part (not while the line
    // alone draws over the shut sheet, where the bend would shift the scene).
    float lens = 1.0 - smoothstep(0.0, 30.0, ep);
    float bend = side * 13.0 * unit / pxPerUnit * lens * lens * open;
    vec3 lock = vec3(texture(src, clamp(vec2(uv.x + bend * 0.90, uv.y), 0.0, 1.0)).r,
                     texture(src, clamp(vec2(uv.x + bend, uv.y), 0.0, 1.0)).g,
                     texture(src, clamp(vec2(uv.x + bend * 1.10, uv.y), 0.0, 1.0)).b);

    // The cut edge of the glass. From the corner inwards: the hot line, a
    // clear band as deep as the glass is thick, lit from within and
    // brightest at the corner, the back corner's thinner line, then a shade
    // where the body begins. A soft highlight rides the edge, travelling
    // along it as the door slides (down one door, up the other).
    float core = exp(-ep / 0.85);
    float halo = exp(-ep / 5.0) * 0.20 + exp(-ep / 40.0) * 0.05;
    float band = (1.0 - smoothstep(EDGE - 0.8, EDGE + 0.8, ep)) * open;
    float pipe = band * mix(0.13, 0.03, clamp(ep / EDGE, 0.0, 1.0));
    float backD = ep - EDGE;
    float back = exp(-backD * backD / 0.6) * 0.42 * open;
    float shade = 0.26 * exp(-max(ep - EDGE, 0.0) / 9.0) * smoothstep(EDGE - 0.8, EDGE + 0.8, ep) * open;
    float gy = yp / halfH - side * mix(0.85, -0.85, slide(t));
    float glint = 1.0 + 0.9 * exp(-gy * gy / 0.16) * open;

    // The border's hairline further in, with ruler ticks hanging off it.
    float d = ep - INNER_LINE;
    float inner = exp(-d * d / 0.7) * 0.5;
    float row = mod(yp + TICK_STEP * 0.5, TICK_STEP) - TICK_STEP * 0.5;
    float tick = exp(-row * row / 0.4)
               * smoothstep(INNER_LINE - 0.7, INNER_LINE + 0.7, ep)
               * smoothstep(INNER_LINE + 6.0, INNER_LINE + 4.7, ep) * 0.35;

    vec3 hotCol = mix(vec3(1.0), accent.rgb, 0.22);
    vec3 rimCol = mix(vec3(1.0), accent.rgb, 0.60);
    vec3 lineCol = mix(vec3(1.0), accent.rgb, 0.80);

    // While the line draws, its light runs hotter and wider than the steady
    // edge it settles into; the spark is a small upright glow at the centre
    // with a short streak across it.
    float energy = 1.0 + 0.9 * flare;
    float sx = xp / 22.0, sy = yp / 110.0;
    float glow = exp(-(sx * sx + sy * sy)) * 0.50 + exp(-abs(xp) / 60.0 - yp * yp / 2.2) * 0.45;
    vec3 light = hotCol * core * 0.95 * lit * glint
               + rimCol * (halo * energy + exp(-ep / 70.0) * 0.10 * flare) * lit * mix(1.0, glint, 0.5)
               + rimCol * (pipe + back) * lit
               + lineCol * (inner + tick) * litLate
               + rimCol * glow * spark;

    // The scene keeps its brightness: it gives up a share of itself to the
    // blurred desktop behind, which is let through dimmed to the same level,
    // and stays like that until the edge wipes it. The cut's band is clearer
    // than the body, so the desktop's light pools in it. The lights raise
    // the door's presence where they are brighter than the glass.
    float clear = 1.0 - band * CLEAR * lit;
    float print = c0 * (1.0 - see) * clear * (1.0 - shade);
    float body = c0 * (1.0 - see * glassDim) * clear;
    float A = max(body, c0 * clamp(max(light.r, max(light.g, light.b)), 0.0, 1.0));
    vec3 rgb = lock * print + light * c0;

    // In the gap: the edge's light blooms a few px out over the desktop, and
    // the door throws a soft shadow with a tight contact line. Both stay
    // under the glass mask threshold (hyprland/plugins.lua), so the desktop
    // in the gap stays sharp and the door's outline is the edge itself.
    float out0 = (1.0 - c0) * smoothstep(0.0, 0.2, t) * leaving;
    float bloom = 0.10 * exp(-gap / 5.0) * lit * out0;
    float shadow = (0.07 * exp(-gap / 60.0) + 0.04 * exp(-gap / 3.5)) * (1.0 - exp(-gap / 5.0)) * out0;
    float under = min(bloom + shadow, 0.11);
    rgb += rimCol * bloom;

    // Premultiplied: the highlights may not push a channel past the alpha.
    float a = clamp(A + under * (1.0 - A), 0.0, 1.0);
    fragColor = vec4(min(rgb, vec3(a)), a) * qt_Opacity;
}
