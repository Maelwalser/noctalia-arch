import QtQuick

// Clipped marquee of status text crawling right-to-left.
Item {
    id: root

    property real u: 1
    property bool active: true
    property string text

    clip: true
    height: label.height

    Row {
        id: strip
        spacing: 0
        // Two copies so the loop is seamless.
        Text { id: label; text: root.text; color: Theme.outline; font.family: Theme.monoFont; font.pixelSize: 12 * root.u; font.letterSpacing: 2 * root.u }
        Text { text: root.text; color: Theme.outline; font.family: Theme.monoFont; font.pixelSize: 12 * root.u; font.letterSpacing: 2 * root.u }

        NumberAnimation on x {
            from: 0
            to: -label.width
            duration: Math.max(1, label.width / (28 * root.u) * 1000)
            loops: Animation.Infinite
            running: label.width > 0
            paused: !root.active
        }
    }
}
