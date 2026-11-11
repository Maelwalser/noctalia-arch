#version 440

// The light of a glass pane that lies over dark ground (GlassScene.qml).
// hyprglass (hyprland/plugins.lua) blurs and bends what is behind a pane, but
// over a near-black corner of the wallpaper there is nothing to bend. Clear
// glass still shows there, and only by its edge: the body stays as dark as
// what is behind it (any lift or wide sheen reads as milk, which the user
// rejected), and the edge catches the light as a thin, bright line with a
// short tail. Lit from the upper left: the top edge is brightest towards
// the left corner, the light leaves through the bottom edge towards the
// right one, the sides get a fraction. Just inside the line the glass is a
// shade darker, which gives the edge its thickness over a lit backdrop.
// Distances are device pixels; the output is premultiplied.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 sizePx;    // the pane in device pixels
    float radiusPx; // its corner radius
    float unit;     // device pixels per logical pixel: the falloffs scale with it
    vec4 light;     // the light's colour (alpha 1)
    float rim;      // peak alpha of the edge line on the top edge
    float shade;    // peak alpha of the dark band inside it
};

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * sizePx;
    vec2 q = abs(p) - (sizePx * 0.5 - radiusPx);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radiusPx;
    float cover = clamp(0.5 - d, 0.0, 1.0);
    float t = max(-d, 0.0) / unit;           // logical px from the edge, inwards

    // The edge's outward direction: along the corner arcs, else the nearer
    // side. (Every term dies within a few px of the edge, long before the
    // corner's diagonal, where "the nearer side" flips.)
    vec2 n = (q.x > 0.0 && q.y > 0.0) ? normalize(q) : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    n *= sign(p);
    float up = max(-n.y, 0.0);
    float down = max(n.y, 0.0);
    float x = qt_TexCoord0.x;
    // How much of the light each part of the edge catches.
    float catchLight = 0.20
        + 0.80 * pow(up, 1.5) * mix(1.0, 0.55, x)
        + 0.50 * pow(down, 1.5) * mix(0.45, 1.0, x);

    float line = exp(-t / 1.1) + 0.16 * exp(-t / 5.0);
    float a = clamp(rim * catchLight * line, 0.0, 1.0);
    float band = (t - 6.0) / 3.5;
    float s = shade * exp(-band * band);
    // Premultiplied: the light over the (black) shade.
    fragColor = vec4(light.rgb * a, a + s * (1.0 - a)) * cover * qt_Opacity;
}
