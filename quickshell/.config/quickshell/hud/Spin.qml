import QtQuick

// Endless rotation that pauses in place (no jump) while the desktop is covered.
NumberAnimation {
    property bool active: true
    property bool reverse: false

    property: "rotation"
    from: reverse ? 360 : 0
    to: reverse ? 0 : 360
    loops: Animation.Infinite
    running: true
    paused: !active
}
