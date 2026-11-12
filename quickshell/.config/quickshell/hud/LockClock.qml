pragma Singleton

import QtQuick
import Quickshell

// One clock for every copy of the lock readouts (LockWidgets.qml): the
// fold's snapshot and the hud-lockwidgets window draw the same time and the
// same reticle angle, so when one takes over from the other nothing moves.
Singleton {
    id: root

    property bool active: false

    // A password was refused (shell.qml hears of it): every output's field
    // answers at once.
    signal denied()

    readonly property SystemClock clock: SystemClock {
        enabled: root.active
        precision: SystemClock.Seconds
    }
    // The reticle's angle is the wall clock's, one turn every 18 s: each
    // copy reads it per frame, so they all show the same angle with nothing
    // running here while no lock is up.
    function reticleAngle(): real { return (Date.now() % 18000) * 0.02; }
}
