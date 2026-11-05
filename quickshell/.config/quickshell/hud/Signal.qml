import QtQuick

// Right-column instrument: an oscilloscope whose trace swells with live network
// traffic, over a wire hand raising a spinning orb. Mirrors Telemetry's header
// and type so the two columns read as one system.
Column {
    id: root

    property real u: 1
    property bool active: true
    readonly property real span: 270 * u
    // 0..1 activity from the receive rate; 512 KB/s and above is a full swing.
    readonly property real carrier: Math.min(1, Math.sqrt(SysStats.rxKbs / 512))

    spacing: 12 * u

    function fmtRate(k) {
        return k >= 1024 ? (k / 1024).toFixed(1) + "M" : Math.round(k) + "K";
    }

    // ── header ──────────────────────────────────────────────────────────
    Item {
        width: root.span
        height: 22 * root.u
        Row {
            spacing: 10 * root.u
            anchors.verticalCenter: parent.verticalCenter
            Rectangle { width: 6 * root.u; height: 14 * root.u; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "SIGNAL // CARRIER 7F"
                color: Theme.primary
                font.family: Theme.monoFont
                font.pixelSize: 13 * root.u
                font.letterSpacing: 2 * root.u
            }
        }
        HudImage {
            name: "claw"
            width: 16 * root.u
            height: 18 * root.u
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: true
                paused: !root.active
                NumberAnimation { from: 1; to: 0.35; duration: 1600; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.35; to: 1; duration: 1600; easing.type: Easing.InOutSine }
            }
        }
    }

    // ── oscilloscope ────────────────────────────────────────────────────
    Item {
        id: scope
        width: root.span
        height: 74 * root.u

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Theme.outline
            border.width: Math.max(1, root.u)
            opacity: 0.55
        }
        // Acid corner ticks, as on the wallpaper frame.
        Repeater {
            model: [[0, 0, 1, 1], [1, 0, -1, 1], [0, 1, 1, -1], [1, 1, -1, -1]]
            Item {
                required property var modelData
                x: modelData[0] * scope.width
                y: modelData[1] * scope.height
                Rectangle { x: modelData[2] > 0 ? 0 : -width; y: modelData[3] > 0 ? 0 : -height; width: 12 * root.u; height: 2 * root.u; color: Theme.primary }
                Rectangle { x: modelData[2] > 0 ? 0 : -width; y: modelData[3] > 0 ? 0 : -height; width: 2 * root.u; height: 12 * root.u; color: Theme.primary }
            }
        }

        Item {
            id: screen
            anchors.fill: parent
            anchors.margins: 4 * root.u
            clip: true

            // Graticule: centre line and quarter ticks.
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: Math.max(1, root.u); color: Theme.outline; opacity: 0.4 }
            Repeater {
                model: 7
                Rectangle {
                    required property int index
                    x: (index + 1) * screen.width / 8
                    width: Math.max(1, root.u)
                    height: screen.height
                    color: Theme.outline
                    opacity: 0.18
                }
            }

            // Each trace is a seamless tile drawn twice end to end and
            // scrolled by exactly one tile width, so the loop never shows a
            // gap. The two traces run in opposite directions.
            component Trace: Row {
                id: trace
                property string name
                property int duration
                property bool reverse: false
                property real traceHeight
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: 2
                    HudImage {
                        name: trace.name
                        width: screen.width
                        height: trace.traceHeight
                        // Fill the tile exactly: aspect-fit would letterbox it
                        // and open a gap at every join.
                        fillMode: Image.Stretch
                    }
                }
                NumberAnimation on x {
                    from: trace.reverse ? -screen.width : 0
                    to: trace.reverse ? 0 : -screen.width
                    duration: trace.duration
                    loops: Animation.Infinite
                    running: true
                    paused: !root.active
                }
            }
            Trace {
                name: "wave-drift"
                duration: 16000
                reverse: true
                traceHeight: 24 * root.u
                opacity: 0.6
            }
            Trace {
                name: "wave"
                duration: 7000
                traceHeight: 30 * root.u
                // Traffic swells the trace; a quiet link still shows a carrier.
                transform: Scale {
                    origin.y: 15 * root.u
                    yScale: 0.6 + 0.7 * root.carrier
                    Behavior on yScale { NumberAnimation { duration: 900; easing.type: Easing.InOutSine } }
                }
            }

            // Sweep cursor.
            Rectangle {
                width: 2 * root.u
                height: screen.height
                color: Theme.primary
                opacity: 0.8
                NumberAnimation on x {
                    from: 0
                    to: screen.width
                    duration: 2600
                    loops: Animation.Infinite
                    running: true
                    paused: !root.active
                }
            }
        }
    }

    // ── readout ─────────────────────────────────────────────────────────
    Row {
        spacing: 16 * root.u
        component Field: Row {
            property string label
            property string value
            property real u: 1
            spacing: 6 * u
            Text { text: parent.label; color: Theme.fgDim; font.family: Theme.monoFont; font.pixelSize: 12 * parent.u }
            Text { text: parent.value; color: Theme.fg; font.family: Theme.monoFont; font.pixelSize: 12 * parent.u }
        }
        Field { u: root.u; label: "RX"; value: root.fmtRate(SysStats.rxKbs) + "B/s" }
        Field { u: root.u; label: "TX"; value: root.fmtRate(SysStats.txKbs) + "B/s" }
        Field { u: root.u; label: "GAIN"; value: Math.round(root.carrier * 100) + "%" }
    }

    // ── hand and orb ────────────────────────────────────────────────────
    Item {
        id: relic
        width: root.span
        height: 540 * root.u

        // One slow float shared by hand and orb, so the orb stays cradled.
        property real drift: 0
        SequentialAnimation on drift {
            loops: Animation.Infinite
            running: true
            paused: !root.active
            NumberAnimation { from: 0; to: 1; duration: 4200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0; duration: 4200; easing.type: Easing.InOutSine }
        }

        Item {
            id: orb
            width: 168 * root.u
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6 * root.u - relic.drift * 10 * root.u

            HudImage {
                name: "orb-halo"
                anchors.centerIn: parent
                width: parent.width * 1.18
                height: width
                opacity: 0.28
                Spin on rotation { active: root.active; duration: 90000; reverse: true }
            }
            HudImage {
                name: "orb"
                anchors.centerIn: parent
                width: parent.width * 0.86
                height: width
                scale: 0.97 + 0.05 * relic.drift
                Spin on rotation { active: root.active; duration: 22000 }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 6 * root.u
                height: width
                rotation: 45
                color: Theme.primary
            }
        }

        // Twinkling sparks around the orb.
        Repeater {
            model: [
                { x: 0.20, y: 0.04, s: 22, d: 0 },
                { x: 0.80, y: 0.26, s: 14, d: 900 },
                { x: 0.26, y: 0.36, s: 10, d: 1700 }
            ]
            HudImage {
                required property var modelData
                name: "spark"
                width: modelData.s * root.u
                height: width
                x: relic.width * modelData.x - width / 2
                y: relic.height * modelData.y - height / 2
                opacity: 0.2
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: true
                    paused: !root.active
                    PauseAnimation { duration: modelData.d }
                    NumberAnimation { from: 0.15; to: 1; duration: 700; easing.type: Easing.OutQuad }
                    NumberAnimation { from: 1; to: 0.15; duration: 1500; easing.type: Easing.InQuad }
                    PauseAnimation { duration: 2600 - modelData.d }
                }
            }
        }

        HudImage {
            name: "hand"
            // hand-cup's aspect: 126 x 311.
            height: 380 * root.u
            width: height * 126 / 311
            // The index fingertip sits at 40 % of the image width: put it
            // under the orb's centre so the orb rests on the raised fingers.
            x: orb.x + orb.width / 2 - width * 0.40
            y: orb.y + orb.height - 34 * root.u
            opacity: 0.8
        }
    }
}
