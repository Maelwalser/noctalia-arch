pragma Singleton

import QtQuick
import Quickshell

// One clock for every copy of the lock readouts (LockWidgets.qml): the
// fold's snapshot and the hud-lockwidgets window draw the same time and the
// same reticle frame, so when one takes over from the other nothing moves.
Singleton {
    id: root

    property bool active: false

    readonly property SystemClock clock: SystemClock {
        enabled: root.active
        precision: SystemClock.Seconds
    }
    // The reticle is a stepper, one frame every 400 ms (hud-build
    // bake_reticle); this counts its frames for all copies at once.
    property int reticleTick: 0
    Timer {
        interval: 400
        repeat: true
        running: root.active
        onTriggered: root.reticleTick += 1
    }
}
