pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Palette + asset lookup for the overlay. Colours come from the Noctalia template
// output (~/.config/hud/colors.json); images are pre-tinted by `hud-build` and
// cache-busted through the overlay/version stamp it writes after re-tinting.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string assetDir: home + "/.local/share/hud/overlay/"

    property color primary: "#ef5fc6"
    property color secondary: "#ff8fdc"
    property color surface: "#0b0712"
    property color fg: "#efe7f4"
    property color fgDim: "#b7a8c9"
    property color outline: "#6a5a84"
    // The amber highlight (palette tertiary): a few accents only, the rest is primary.
    property color accent: "#ffa35e"
    property color error: "#ff4d5e"
    // The palette's terminal green (noctalia palettes/acid-hud.json): the lock's "granted".
    property color good: "#4fd1b5"
    property string version: "0"

    readonly property string displayFont: "Chakra Petch"
    readonly property string monoFont: "Departure Mono"

    function asset(name) {
        return "file://" + assetDir + name + ".png?v=" + version;
    }

    function applyColors(raw) {
        try {
            const c = JSON.parse(raw);
            primary = c.primary ?? primary;
            secondary = c.secondary ?? secondary;
            surface = c.surface ?? surface;
            fg = c.on_surface ?? fg;
            fgDim = c.on_surface_variant ?? fgDim;
            outline = c.outline ?? outline;
            accent = c.tertiary ?? accent;
            error = c.error ?? error;
        } catch (e) {
            console.warn("hud: ignoring malformed colors.json:", e);
        }
    }

    FileView {
        id: colorsFile
        path: root.home + "/.config/hud/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyColors(text())
        onLoadFailed: retry.start()
    }

    // hud-build rewrites this stamp after every re-tint. It also re-reads the
    // colours, in case an atomic replace of colors.json dropped that watch.
    FileView {
        id: versionFile
        path: root.assetDir + "version"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.version = text().trim();
            colorsFile.reload();
        }
        onLoadFailed: retry.start()
    }

    // Before the first hud-build run neither file exists, and a missing file
    // cannot be watched: poll until both have loaded.
    Timer {
        id: retry
        interval: 5000
        onTriggered: {
            colorsFile.reload();
            versionFile.reload();
        }
    }
}
