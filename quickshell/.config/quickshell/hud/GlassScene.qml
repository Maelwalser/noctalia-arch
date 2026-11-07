import QtQuick

// The liquid-glass panes of one output, and nothing else: this window's
// namespace (hud-glass) is whitelisted in hyprland/plugins.lua with hyprglass's
// contour mode, which turns every visible pixel into glass with a rim along
// the shape it belongs to. The faint fill only marks the shapes (in the
// surface colour: a white one would lift the panes above the toasts); the
// blur, lens edge and rim are the plugin's. The content is drawn by HudScene
// on the hud-overlay window above, so it stays crisp.
Item {
    id: glass

    readonly property color fill: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.08)
    component Pane: Rectangle {
        property rect box
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        radius: Layout.radiusPx
        color: glass.fill
        antialiasing: true
    }

    Pane { box: Layout.heroCard(glass.width, glass.height) }
    Pane { box: Layout.telemetryCard(glass.width, glass.height) }
    Pane { box: Layout.signalCard(glass.width, glass.height) }
}
