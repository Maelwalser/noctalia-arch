pragma Singleton

import QtQuick
import Quickshell

// Shared geometry of the overlay, on the wallpaper's design grid (1 u = screen
// height / 1200). Two windows draw each pane of the desktop (SceneWindow):
// hud-glass holds the liquid-glass pane (GlassScene) and hud-overlay the
// content on top (shell.qml, HudScene). Both take their rectangles from here,
// so a pane and what sits on it cannot drift apart.
Singleton {
    readonly property real pad: 24       // u: a pane's inset around its content
    readonly property int radiusPx: 18   // logical px: the toasts' corner radius
    // The bottom panes' inset from the screen edges: clears the HUD
    // wallpaper's frame line, altimeter ticks and spine label, and keeps
    // them off the edges of a photo wallpaper.
    readonly property real inset: 71     // u
    // The hero's top line, in the upper third above the HUD horizon (655 u).
    readonly property real topLine: 395  // u
    // The two bottom panes share one size, so they read as a pair.
    readonly property real paneW: 400    // u
    readonly property real paneH: 300    // u

    function u(h) { return h / 1200; }

    // The window that carries one pane (or the content on it): the pane's
    // box and a margin, in logical px. A window as large as the screen was
    // put together again by the compositor on every frame the scene drew,
    // all of it, though only the panes are ever drawn on (on the 5120x2160
    // ultrawide that alone kept the GPU more than half busy). On a 16 px
    // grid: the window then starts on a whole device pixel at every scale,
    // and on the glass plugin's coarser outline grid, so nothing in it
    // shifts or softens. The margin keeps the window wider than the size
    // the plugin scales a pane's rim by (160 px).
    function frame(r) {
        const g = 16, m = 16;
        const x0 = Math.floor((r.x - m) / g) * g, y0 = Math.floor((r.y - m) / g) * g;
        const x1 = Math.ceil((r.x + r.width + m) / g) * g, y1 = Math.ceil((r.y + r.height + m) / g) * g;
        return Qt.rect(x0, y0, x1 - x0, y1 - y0);
    }

    // The hero clock pane, centred over the horizon bloom (hud-build's ax).
    function heroCard(w, h) {
        const k = u(h);
        return Qt.rect(w / 2 - 270 * k, topLine * k, 540 * k, 236 * k);
    }
    // The bottom corners, mirrored: telemetry left, signal right, the same
    // box at the same inset from the sides and the bottom. On a photo
    // wallpaper the corners are its quietest ground; on the HUD wallpaper
    // they sit on the floor grid.
    function telemetryCard(w, h) {
        const k = u(h);
        return Qt.rect(inset * k, h - (inset + paneH) * k, paneW * k, paneH * k);
    }
    function signalCard(w, h) {
        const k = u(h);
        return Qt.rect(w - (inset + paneW) * k, h - (inset + paneH) * k, paneW * k, paneH * k);
    }
}
