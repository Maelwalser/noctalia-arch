import QtQuick

// The liquid-glass panes of one output, and nothing else: this window's
// namespace is whitelisted in hyprland/plugins.lua with hyprglass's contour
// mode, which turns every visible pixel into glass with a rim along the shape
// it belongs to. The faint fill only marks the shapes (in the surface colour:
// a white one would lift the panes above the toasts); the blur, lens edge and
// rim are the plugin's. The content is drawn by HudScene on the hud-overlay
// window above, so it stays crisp.
// Two windows show this (shell.qml), because the glass is set per namespace:
// hud-glass has the hero pane, frosted over the wallpaper's lights, and
// hud-clearglass (`corners`) the two bottom panes, clear glass over its dark
// corners.
Item {
    id: glass

    property bool corners: false
    readonly property color fill: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.08)
    component Pane: Rectangle {
        id: pane
        property rect box
        // A pane over the wallpaper's dark corners: the compositor's glass
        // has nothing to bend there, so the pane draws its own edge light
        // (shaders/pane.frag, compiled by `hud-build --shaders`).
        property bool lit: false
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        radius: Layout.radiusPx
        color: glass.fill
        antialiasing: true

        ShaderEffect {
            anchors.fill: parent
            visible: pane.lit
            fragmentShader: "file://" + Theme.assetDir + "pane.frag.qsb"
            readonly property real dpr: Screen.devicePixelRatio
            property vector2d sizePx: Qt.vector2d(width * dpr, height * dpr)
            property real radiusPx: pane.radius * dpr
            property real unit: dpr
            property color light: "#dce6f0"
            property real rim: 0.55
            property real shade: 0.10
        }
    }

    Pane { visible: !glass.corners; box: Layout.heroCard(glass.width, glass.height) }
    Pane { visible: glass.corners; box: Layout.telemetryCard(glass.width, glass.height); lit: true }
    Pane { visible: glass.corners; box: Layout.signalCard(glass.width, glass.height); lit: true }
}
