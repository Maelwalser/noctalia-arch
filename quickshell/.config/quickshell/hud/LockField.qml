import QtQuick

// The lock's password field, as Noctalia's login box draws it empty, placed
// on an item the size of the output: the box is hud-build's LOCK_LOGIN (in
// u = 1/800 of the height, x from the centre); the field is 16 px in from
// the box's sides and 38 px tall whatever the output's size, a pill with a
// 2 px ring in the palette's secondary over a 35 % surface fill, with the
// placeholder (measured on captures of the lock at scale 1 and 1.5).
// The real field only exists on Noctalia's lock surface. This one stands in
// for it on the closing doors and in the cover above the fresh lock
// (LockWidgets.qml), and, as the ring alone in another colour, is the
// lock's answer to a password: red over the real field when it was wrong,
// green on the opening doors when it was right (UnlockFold.qml).
Item {
    id: field
    property real dpr: 1
    property color ring: Theme.secondary
    // The fill and the placeholder too, not only the ring.
    property bool body: true

    readonly property real u: height / 800
    function snap(v) { return Math.round(v * dpr) / dpr; }

    Item {
        x: field.snap(field.width / 2 - 240 * field.u)
        y: field.snap(640 * field.u)
        width: field.snap(480 * field.u)
        height: field.snap(72 * field.u)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - field.snap(38.67)) / 2 + 0.24
            width: field.snap(parent.width - 32)
            height: 38
            radius: height / 2
            color: field.body ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.35) : "transparent"
            border.width: field.snap(2)
            border.color: field.ring
            antialiasing: true
            Text {
                // Noctalia sets the placeholder at 13.6 px and rasterises it
                // at just that size. Qt's native text takes whole pixels only
                // (13: smaller and heavier, which showed when the real field
                // took over), so this is laid out five times the size and
                // scaled down by the curve renderer, which stays sharp. The
                // offsets put it on the real one (measured at scale 1.5);
                // not aligned to whole pixels, or they would be rounded off.
                anchors.centerIn: parent
                anchors.alignWhenCentered: false
                anchors.horizontalCenterOffset: -0.12
                anchors.verticalCenterOffset: 0.3
                visible: field.body
                text: "Password"
                color: Theme.fgDim
                opacity: 0.68
                renderType: Text.CurveRendering
                font.family: Theme.monoFont
                font.pixelSize: 68
                scale: 0.2
            }
        }
    }
}
