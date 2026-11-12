import QtQuick

// One pane's content (its children, placed in the pane's box), which can be
// written in again by a line of light: shaders/glitch.frag, compiled by
// `hud-build --shaders`. HudScene runs `clock` once when the desktop comes up
// on an empty workspace; each pane starts `delay` ms into it. The content is
// only drawn through the shader for that run: at rest there is no layer.
Item {
    id: root

    property rect box
    property real u: 1
    property real clock: 0     // ms into the scene's run
    property bool running: false
    property real delay: 0     // ms: when this pane's line sets off
    property real run: 420     // ms: how long its content takes to settle
    property real seed: 0

    // On whole device pixels: the layer's texture then lines up with the
    // screen, and the content does not shift or soften as the layer comes
    // and goes.
    readonly property real dpr: Screen.devicePixelRatio
    function snap(v) { return Math.round(v * dpr) / dpr; }
    x: snap(box.x)
    y: snap(box.y)
    width: snap(box.x + box.width) - x
    height: snap(box.y + box.height) - y

    layer.enabled: running
    layer.effect: ShaderEffect {
        fragmentShader: "file://" + Theme.assetDir + "glitch.frag.qsb"
        property real progress: Math.max(0, Math.min(1, (root.clock - root.delay) / root.run))
        property real seed: root.seed
        property vector2d sizePx: Qt.vector2d(width * root.dpr, height * root.dpr)
        property real unit: root.u * root.dpr
        property color accent: Theme.primary
    }
}
