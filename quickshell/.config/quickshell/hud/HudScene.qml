import QtQuick

// The state of the scene on one output: the hero clock, the telemetry and
// signal blocks. It draws nothing itself: each block has a window of its own
// (shell.qml, SceneWindow), sized like the screen here. Positions come from
// Layout (1 u = screen height / 1200, the wallpaper's design grid), which
// also places the glass panes under the three blocks (GlassScene).
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
    // Something of the scene is on screen: it is active, or still fading out.
    // The windows are mapped only then (shell.qml).
    readonly property bool showing: active || fadeOpacity > 0
    // The blocks' opacity. Faded by `fade` below, not bound: the lock-on has
    // to be able to cut the fade short.
    property real fadeOpacity: 0
    Component.onCompleted: fadeOpacity = active ? 1 : 0
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
            fadeOpacity = 1;
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
    NumberAnimation { id: fade; target: scene; property: "fadeOpacity"; duration: 400 }

    readonly property real stagger: 70  // ms between one pane's line and the next
    property real clock: 0
    readonly property bool lockingOn: lockOn.running
    NumberAnimation {
        id: lockOn
        target: scene
        property: "clock"
        from: 0
        to: 420 + 2 * scene.stagger
        duration: to
    }
}
