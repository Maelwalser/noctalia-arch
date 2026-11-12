import QtQuick

// The content drawn on one output: the hero clock, the telemetry and signal
// blocks. Positions come from Layout (1 u = screen height / 1200, the
// wallpaper's design grid), which also places the glass panes under the
// three blocks (GlassScene).
Item {
    id: scene

    property var monitor: null
    // Switched off from the bar (shell.qml, `overlay off`): the desktop
    // scene goes, the lock's doors and readouts are not part of it.
    property bool shown: true
    readonly property real u: height / 1200
    // Nothing to animate behind tiled windows: pause while the workspace is occupied.
    readonly property bool active: {
        if (!shown)
            return false;
        const ws = monitor ? monitor.activeWorkspace : null;
        return !ws || ws.toplevels.values.length === 0;
    }
    readonly property rect heroCard: Layout.heroCard(width, height)
    readonly property rect telemetryCard: Layout.telemetryCard(width, height)
    readonly property rect signalCard: Layout.signalCard(width, height)
    readonly property real pad: Layout.pad * u

    // Arriving on an empty workspace, the three feeds lock on again: each
    // pane's content is written in by a line of light (Glitch.qml), the hero
    // first, the bottom pair a beat behind. Only on a switch (not on a timer,
    // and not when the last window closes: then the content just fades in).
    // The workspace id and `active` update in either order on a switch, so
    // the check runs once both have settled.
    readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    property bool switched: false
    function lockOnIfSwitched() {
        if (switched && active) {
            // Coming from a covered desktop the content is fading in: the
            // line writes it in instead.
            fade.stop();
            content.opacity = 1;
            lockOn.restart();
        }
        switched = false;
    }
    onWorkspaceIdChanged: {
        switched = true;
        Qt.callLater(lockOnIfSwitched);
    }

    onActiveChanged: {
        fade.to = active ? 1 : 0;
        fade.restart();
    }
    NumberAnimation { id: fade; target: content; property: "opacity"; duration: 400 }

    readonly property real stagger: 70  // ms between one pane's line and the next
    property real clock: 0
    NumberAnimation {
        id: lockOn
        target: scene
        property: "clock"
        from: 0
        to: 420 + 2 * scene.stagger
        duration: to
    }

    Item {
        id: content
        anchors.fill: parent
        // Faded by `fade` below, not bound: the lock-on has to be able to
        // cut the fade short.
        opacity: 0
        Component.onCompleted: opacity = scene.active ? 1 : 0
        // Fully faded content leaves the scene graph, so a covered desktop
        // costs no render passes at all.
        visible: opacity > 0

        // Each block sits inside its glass pane, inset by the pane's padding.
        Glitch {
            box: scene.heroCard
            u: scene.u
            clock: scene.clock
            running: lockOn.running
            seed: 1

            HeroClock {
                u: scene.u
                active: scene.active
                x: scene.pad
                y: scene.pad
                width: parent.width - 2 * scene.pad
                height: parent.height - 2 * scene.pad
            }
        }

        Glitch {
            box: scene.telemetryCard
            u: scene.u
            clock: scene.clock
            running: lockOn.running
            delay: scene.stagger
            seed: 2

            Telemetry {
                u: scene.u
                x: scene.pad
                y: scene.pad
                width: parent.width - 2 * scene.pad
            }
        }

        Glitch {
            box: scene.signalCard
            u: scene.u
            clock: scene.clock
            running: lockOn.running
            delay: 2 * scene.stagger
            seed: 3

            Signal {
                u: scene.u
                active: scene.active
                x: scene.pad
                y: scene.pad
            }
        }
    }
}
