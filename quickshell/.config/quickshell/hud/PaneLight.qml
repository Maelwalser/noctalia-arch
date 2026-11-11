import QtQuick

// The edge light of a clear glass pane (shaders/pane.frag, compiled by
// `hud-build --shaders`). The compositor's glass blurs and bends what is
// behind a pane, but over dark ground there is nothing to bend, so the pane
// shows by this light alone: a crisp line along the edge, lit from the upper
// left. hud-build bakes the same light into the lock's cards (glass_map):
// keep the numbers in step.
ShaderEffect {
    property real radius: Layout.radiusPx
    fragmentShader: "file://" + Theme.assetDir + "pane.frag.qsb"
    readonly property real dpr: Screen.devicePixelRatio
    property vector2d sizePx: Qt.vector2d(width * dpr, height * dpr)
    property real radiusPx: Math.min(radius, width / 2, height / 2) * dpr
    property real unit: dpr
    property color light: "#dce6f0"
    property real rim: 0.55
    property real shade: 0.10
}
