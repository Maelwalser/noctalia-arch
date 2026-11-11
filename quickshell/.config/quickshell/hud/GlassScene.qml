import QtQuick

// The liquid-glass panes of one output, and nothing else: this window's
// namespace is whitelisted in hyprland/plugins.lua with hyprglass's contour
// mode, which turns every visible pixel into glass with a rim along the shape
// it belongs to. The faint fill only marks the shapes (in the surface colour:
// a white one would lift the panes above the toasts); the blur, lens edge and
// rim are the plugin's. The content is drawn by HudScene on the hud-overlay
// window above, so it stays crisp. The three panes are one clear glass; the
// bar's rail carries the same edge light (BarLight.qml).
Item {
    id: glass

    readonly property color fill: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.08)
    component Pane: Rectangle {
        id: pane
        property rect box
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        radius: Layout.radiusPx
        color: glass.fill
        antialiasing: true

        PaneLight { anchors.fill: parent; radius: pane.radius }
    }

    Pane { box: Layout.heroCard(glass.width, glass.height) }
    Pane { box: Layout.telemetryCard(glass.width, glass.height) }
    Pane { box: Layout.signalCard(glass.width, glass.height) }
}
