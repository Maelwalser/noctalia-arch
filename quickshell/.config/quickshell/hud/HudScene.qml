import QtQuick
import Quickshell

// Everything drawn on one output. Positions use the wallpaper's design grid
// (1 u = screen height / 1200) so the overlay lines up with the frame that
// hud-build paints into the wallpaper.
Item {
    id: scene

    property var monitor: null
    readonly property real u: height / 1200
    readonly property bool ultrawide: width / height > 2
    // Nothing to animate behind tiled windows: pause while the workspace is occupied.
    readonly property bool active: {
        const ws = monitor ? monitor.activeWorkspace : null;
        return !ws || ws.toplevels.values.length === 0;
    }
    readonly property real frameTop: 80 * u
    readonly property real frameSide: 28 * u
    // Login name, upper-cased, for the "<USER>//HUD" tags.
    readonly property string user: (Quickshell.env("USER") || "user").toUpperCase()

    // Glitch only when switching to an empty workspace (not on a timer, and not
    // when the last window closes). The workspace id and `active` update in
    // either order on a switch, so the check runs once both have settled.
    readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    property bool switched: false
    function glitchIfSwitched() {
        if (switched && active)
            glitch.trigger();
        switched = false;
    }
    onWorkspaceIdChanged: {
        switched = true;
        Qt.callLater(glitchIfSwitched);
    }

    Item {
        id: content
        anchors.fill: parent
        transform: Translate { x: glitch.jitter }
        opacity: scene.active ? 1 : 0
        // Fully faded content leaves the scene graph, so a covered desktop
        // costs no render passes at all.
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 400 } }

        RingStack {
            u: scene.u
            active: scene.active
            x: scene.width * (scene.ultrawide ? 0.40 : 0.42) - width / 2
            y: scene.height * 0.45 - height / 2
        }

        Telemetry {
            u: scene.u
            x: scene.frameSide + 30 * scene.u
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 140 * scene.u
        }

        // Right column, centred 230 units in from the right edge.
        Signal {
            u: scene.u
            active: scene.active
            x: scene.width - 230 * scene.u - span / 2
            y: scene.height * 0.42
        }
    }

    Glitch {
        id: glitch
        anchors.fill: parent
        u: scene.u
    }
}
