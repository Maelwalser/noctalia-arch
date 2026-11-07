import QtQuick
import Quickshell

// The hero: time, date and status on the central glass pane, in the same
// header-tag idiom as the telemetry and signal blocks, with a thin acid
// seconds line along the bottom. `width`/`height` are the pane's inner box.
Item {
    id: root

    property real u: 1
    property bool active: true

    SystemClock {
        id: clock
        enabled: root.active
        precision: SystemClock.Seconds
    }

    Row {
        id: header
        spacing: 10 * root.u
        Rectangle { width: 6 * root.u; height: 14 * root.u; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: "CHRONO // LOCAL"
            color: Theme.primary
            font.family: Theme.monoFont
            font.pixelSize: 13 * root.u
            font.letterSpacing: 2 * root.u
        }
    }
    Text {
        anchors.right: parent.right
        anchors.verticalCenter: header.verticalCenter
        text: "W" + String(root.isoWeek(clock.date)).padStart(2, "0") + "  ·  D" + String(root.dayOfYear(clock.date)).padStart(3, "0")
        color: Theme.fgDim
        font.family: Theme.monoFont
        font.pixelSize: 12 * root.u
        font.letterSpacing: 1 * root.u
    }

    Text {
        id: time
        anchors.top: header.bottom
        anchors.topMargin: 6 * root.u
        x: -5 * root.u  // the face's side bearing, so the digits align with the tag
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: Theme.fg
        font.family: Theme.displayFont
        font.weight: Font.DemiBold
        font.pixelSize: 132 * root.u
        // Trim the face's internal leading so the rows below sit close.
        height: Math.round(font.pixelSize * 0.9)
        verticalAlignment: Text.AlignVCenter
    }
    // Seconds, small and dim on the time's baseline, like a watch face.
    Text {
        anchors.left: time.right
        anchors.leftMargin: 14 * root.u
        anchors.baseline: time.baseline
        text: String(clock.seconds).padStart(2, "0")
        color: Theme.fgDim
        font.family: Theme.displayFont
        font.weight: Font.DemiBold
        font.pixelSize: 48 * root.u
    }

    Row {
        id: dateRow
        anchors.top: time.bottom
        anchors.topMargin: 10 * root.u
        spacing: 18 * root.u
        Text {
            text: Qt.formatDateTime(clock.date, "dddd dd.MM.yy").toUpperCase()
            color: Theme.fgDim
            font.family: Theme.monoFont
            font.pixelSize: 15 * root.u
            font.letterSpacing: 3 * root.u
        }
        Text {
            text: "CORE//ONLINE"
            color: Theme.primary
            font.family: Theme.monoFont
            font.pixelSize: 15 * root.u
            font.letterSpacing: 3 * root.u
            Text {
                anchors.left: parent.right
                text: "_"
                visible: caret.on
                color: Theme.primary
                font: parent.font
            }
            Timer {
                id: caret
                property bool on: true
                interval: 600
                repeat: true
                running: root.active
                onTriggered: on = !on
            }
        }
    }

    // Seconds: a hairline track with an acid fill growing across the minute.
    Item {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 2 * root.u
        Rectangle { anchors.fill: parent; color: Theme.outline; opacity: 0.5 }
        Rectangle {
            height: parent.height
            width: parent.width * clock.seconds / 59
            color: Theme.accent
            Behavior on width {
                enabled: root.active && clock.seconds > 0
                NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
            }
        }
    }

    function dayOfYear(d) {
        return Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(d.getFullYear(), 0, 1)) / 86400000) + 1;
    }
    // ISO 8601 week number (Qt's date formats have none).
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7);
    }
}
