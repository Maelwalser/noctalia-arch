pragma Singleton

import QtQuick
import Quickshell

// Shared geometry of the overlay, on the wallpaper's design grid (1 u = screen
// height / 1200). Two windows draw the desktop: hud-glass holds the liquid-glass
// panes (GlassScene) and hud-overlay the content on top (HudScene). Both take
// their rectangles from here, so a pane and what sits on it cannot drift apart.
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
