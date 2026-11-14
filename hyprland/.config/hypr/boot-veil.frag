#version 300 es
// Black from the first frame of a session until the lock scene is painted
// (autostart.lua, hypr-boot-lock): the lock can only be asked of Noctalia
// once it runs, and by then its wallpaper and bar are already on screen.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
}
