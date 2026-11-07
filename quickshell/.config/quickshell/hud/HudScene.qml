import QtQuick

// The content drawn on one output: the hero clock, the telemetry and signal
// blocks. Positions come from Layout (1 u = screen height / 1200, the
// wallpaper's design grid), which also places the glass panes under the
// three blocks (GlassScene).
Item {
    id: scene

    property var monitor: null
    readonly property real u: height / 1200
    // Nothing to animate behind tiled windows: pause while the workspace is occupied.
    readonly property bool active: {
        const ws = monitor ? monitor.activeWorkspace : null;
        return !ws || ws.toplevels.values.length === 0;
    }
    readonly property rect heroCard: Layout.heroCard(width, height)
    readonly property rect telemetryCard: Layout.telemetryCard(width, height)
    readonly property rect signalCard: Layout.signalCard(width, height)
    readonly property real pad: Layout.pad * u

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

        // Each block sits inside its glass pane, inset by the pane's padding.
        HeroClock {
            u: scene.u
            active: scene.active
            x: scene.heroCard.x + scene.pad
            y: scene.heroCard.y + scene.pad
            width: scene.heroCard.width - 2 * scene.pad
            height: scene.heroCard.height - 2 * scene.pad
        }

        Telemetry {
            u: scene.u
            x: scene.telemetryCard.x + scene.pad
            y: scene.telemetryCard.y + scene.pad
            width: scene.telemetryCard.width - 2 * scene.pad
        }

        Signal {
            u: scene.u
            active: scene.active
            x: scene.signalCard.x + scene.pad
            y: scene.signalCard.y + scene.pad
        }
    }

    Glitch {
        id: glitch
        anchors.fill: parent
        u: scene.u
    }
}
