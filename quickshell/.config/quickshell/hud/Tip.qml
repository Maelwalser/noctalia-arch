import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Tooltips for the bar's HUD widgets, as liquid glass. Noctalia's own are
// xdg popups with an opaque surface fill and no option to change it, and
// hyprglass only renders layers, so the widgets (mael/hud, common.luau `tip`)
// send their text here instead:
//   qs -c hud ipc call tip put <id> <output> <text>
//   qs -c hud ipc call tip drop <id>
// (`show` is a reserved word of `qs ipc`.) `id` names the widget: a drop only
// counts while its own text is up, since the calls of two widgets (leave one,
// enter the next) can arrive in any order.
//
// One small layer under the bar, centred on the pointer: a faint fill for
// hyprglass to turn into glass (hyprland/plugins.lua, hud-tooltip) with the
// text on it, as Noctalia's toasts are.
Scope {
    id: tip

    property string owner: ""
    property string text: ""
    property var targetScreen: null
    // Pointer x on the target screen (logical px); the tooltip centres on it.
    property real pointerX: 0
    property bool shown: false

    // Logical px. The top is the bar's lower edge (margin 6 + thickness 32 in
    // noctalia themes/acid.toml) plus the toasts' 8 px gap.
    readonly property int top: 46
    readonly property int edge: 8
    readonly property int padH: 10
    readonly property int padV: 6

    function show(id, output, body) {
        const screen = Quickshell.screens.find(s => s.name === output);
        if (!screen || body === "")
            return;
        owner = id;
        text = body;
        targetScreen = screen;
        leave.stop();
        expire.restart();
        pointer.running = true;
    }
    function hide(id) {
        if (id === owner)
            leave.restart();
    }
    function close() {
        owner = "";
        delay.stop();
        expire.stop();
        shown = false;
    }

    IpcHandler {
        target: "tip"
        function put(id: string, output: string, text: string): void { tip.show(id, output, text); }
        function drop(id: string): void { tip.hide(id); }
    }

    // Where the pointer is: the bar widgets do not know their own position.
    Process {
        id: pointer
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /(-?\d+),\s*(-?\d+)/.exec(text);
                if (!m || tip.owner === "" || !tip.targetScreen)
                    return;
                tip.pointerX = Number(m[1]) - tip.targetScreen.x;
                // Already up (the pointer came from a neighbour): it has just
                // moved along. Otherwise wait, so a pass over the bar shows none.
                if (!tip.shown && !delay.running)
                    delay.start();
            }
        }
    }
    Timer {
        id: delay
        interval: 450
        onTriggered: tip.shown = tip.owner !== ""
    }
    // A drop is held briefly: on the way to a neighbour its put follows, and
    // the tooltip moves over instead of blinking.
    Timer {
        id: leave
        interval: 120
        onTriggered: tip.close()
    }
    // A widget that is reloaded while hovered never sends its drop.
    Timer {
        id: expire
        interval: 10000
        onTriggered: tip.close()
    }

    PanelWindow {
        id: win
        screen: tip.targetScreen ?? Quickshell.screens[0]
        anchors { top: true; left: true }
        // Kept on the screen, and on whole device pixels: a fractional scale
        // would smear the rim over two.
        readonly property real left: {
            const room = (screen?.width ?? 0) - body.width - tip.edge;
            const x = Math.max(tip.edge, Math.min(room, tip.pointerX - body.width / 2));
            return Math.round(x * devicePixelRatio) / devicePixelRatio;
        }
        margins { top: tip.top; left: win.left }
        implicitWidth: body.width
        implicitHeight: body.height
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        visible: tip.shown

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hud-tooltip"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: body
            width: Math.ceil(label.implicitWidth) + 2 * tip.padH
            height: Math.ceil(label.implicitHeight) + 2 * tip.padV
            // The capsules' radius; a one-line tooltip comes out as a pill.
            radius: Math.min(12, height / 2)
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.1)
            antialiasing: true

            Text {
                id: label
                x: tip.padH
                y: tip.padV
                text: tip.text
                color: Theme.fg
                font.family: Theme.monoFont
                font.pixelSize: 11
                lineHeight: 1.25
                // The default renderer fringes in colour over glass at 1.5x.
                renderType: Text.CurveRendering
            }
        }
    }
}
