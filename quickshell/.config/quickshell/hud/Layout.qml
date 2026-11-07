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
    // The side panes' inset from the screen edge: clears the wallpaper's
    // frame line, altimeter ticks and the spine label down the right edge.
    readonly property real inset: 71     // u
    // The hero and signal panes hang from this line, above the horizon (655 u).
    readonly property real topLine: 395  // u

    function u(h) { return h / 1200; }

    // The hero clock pane, centred over the horizon bloom (hud-build's ax).
    function heroCard(w, h) {
        const k = u(h);
        return Qt.rect(w / 2 - 270 * k, topLine * k, 540 * k, 236 * k);
    }
    // Bottom-left telemetry pane, at the side inset, 100 u off the bottom.
    function telemetryCard(w, h) {
        const k = u(h);
        return Qt.rect(inset * k, h - 400 * k, 400 * k, 300 * k);
    }
    // Right-hand signal pane around the oscilloscope, top-aligned with the
    // hero at the same inset as the telemetry; the relic floats below it.
    function signalCard(w, h) {
        const k = u(h);
        return Qt.rect(w - (inset + 318) * k, topLine * k, 318 * k, 183 * k);
    }
}
