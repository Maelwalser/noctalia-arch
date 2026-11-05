import QtQuick
import Quickshell

// Concentric HUD instrument: rings turning at different speeds and directions
// around a clock face with an acid seconds sweep. Every ring asset is centred
// on its own circle by hud-build, so anchoring them to one point keeps them
// concentric while they rotate.
Item {
    id: root

    property real u: 1          // design unit (screen height / 1200)
    property bool active: true
    property real diameter: 560 * u
    // Vertical fine-tune of the text block against the dial centre (measured).
    property real textNudge: 0

    width: diameter * 1.34
    height: width

    SystemClock {
        id: clock
        enabled: root.active
        precision: SystemClock.Seconds
    }

    component Ring: HudImage {
        id: ring
        property real scale_: 1
        property int period: 60000
        property bool reverse: false
        anchors.centerIn: parent
        width: root.diameter * scale_
        height: width
        Spin on rotation {
            active: root.active && ring.period > 0
            duration: Math.max(1, ring.period)
            reverse: ring.reverse
        }
    }

    // Square reticle framing the instrument: four identical corner brackets
    // and edge ticks, drawn here so it is exactly symmetric. Breathes slowly.
    Item {
        id: reticle
        anchors.centerIn: parent
        width: root.diameter * 1.30
        height: width
        readonly property real arm: width * 0.12
        readonly property real t: Math.max(1, 2 * root.u)
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: true
            paused: !root.active
            NumberAnimation { from: 0.35; to: 0.7; duration: 4200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.7; to: 0.35; duration: 4200; easing.type: Easing.InOutSine }
        }
        Repeater {
            // Corners: (x, y) as 0/1, arms pointing inwards.
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            Item {
                required property var modelData
                readonly property real sx: modelData[0] ? -1 : 1
                readonly property real sy: modelData[1] ? -1 : 1
                x: modelData[0] * reticle.width
                y: modelData[1] * reticle.height
                Rectangle { x: sx > 0 ? 0 : -width; y: sy > 0 ? 0 : -height; width: reticle.arm; height: reticle.t; color: Theme.outline }
                Rectangle { x: sx > 0 ? 0 : -width; y: sy > 0 ? 0 : -height; width: reticle.t; height: reticle.arm; color: Theme.outline }
                // Acid knuckle at the very corner.
                Rectangle { x: sx > 0 ? 0 : -width; y: sy > 0 ? 0 : -height; width: 4 * reticle.t; height: 4 * reticle.t; color: Theme.primary }
            }
        }
        Repeater {
            // Edge-centre ticks pointing at the dial: top, bottom, left, right.
            model: [[0.5, 0, 0], [0.5, 1, 0], [0, 0.5, 1], [1, 0.5, 1]]
            Rectangle {
                required property var modelData
                width: modelData[2] ? reticle.arm * 0.4 : reticle.t
                height: modelData[2] ? reticle.t : reticle.arm * 0.4
                x: modelData[0] * reticle.width - (modelData[0] === 1 ? width : modelData[0] === 0 ? 0 : width / 2)
                y: modelData[1] * reticle.height - (modelData[1] === 1 ? height : modelData[1] === 0 ? 0 : height / 2)
                color: Theme.outline
            }
        }
    }

    Ring { name: "ring-ticks"; scale_: 1.16; period: 240000; opacity: 0.30 }
    Ring { name: "ring-outer"; scale_: 1.02; period: 150000; reverse: true; opacity: 0.55 }
    Ring { name: "ring-acid";  scale_: 0.80; period: 90000; opacity: 0.95 }
    Ring { name: "ring-face";  scale_: 0.56; period: 0; opacity: 0.9 }

    // Seconds sweep: an acid needle over the face's minute ticks, which run
    // from 0.405 to 0.46 of its canvas (clock_face in hud-build).
    Item {
        id: sweep
        anchors.centerIn: parent
        width: root.diameter * 0.56 * 0.46 * 2
        height: width
        rotation: clock.seconds * 6
        Behavior on rotation {
            enabled: root.active
            RotationAnimation { duration: 350; direction: RotationAnimation.Clockwise; easing.type: Easing.OutCubic }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: 3 * root.u
            height: root.diameter * 0.56 * (0.46 - 0.405)
            color: Theme.primary
        }
    }

    // Time, date and status as one block centred on the dial. letterSpacing
    // also pads after the last glyph, so spaced lines shift right by half of it
    // to stay optically centred; the caret lives outside the centred text.
    Column {
        id: readout
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.textNudge
        spacing: 2 * root.u
        Text {
            id: hhmm
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Theme.fg
            font.family: Theme.displayFont
            font.weight: Font.DemiBold
            font.pixelSize: 62 * root.u
            // Trim the font's internal leading so the block centres on the ink.
            height: Math.round(font.pixelSize * 0.86)
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: font.letterSpacing / 2
            text: Qt.formatDateTime(clock.date, "ddd dd.MM.yy").toUpperCase()
            color: Theme.fgDim
            font.family: Theme.monoFont
            font.pixelSize: 14 * root.u
            font.letterSpacing: 2 * root.u
        }
        Text {
            id: status
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: font.letterSpacing / 2
            text: "CORE//ONLINE"
            color: Theme.primary
            font.family: Theme.monoFont
            font.pixelSize: 11 * root.u
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
}
