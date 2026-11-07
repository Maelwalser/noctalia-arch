import QtQuick

// Bottom-right instrument block, on its glass pane: tick strip, header, an
// oscilloscope whose trace swells with live network traffic, the RX / TX
// readout and a spectrum of the link. Mirrors Telemetry's strip, header and
// type, so the two bottom panes read as a pair.
Column {
    id: root

    property real u: 1
    property bool active: true
    readonly property real span: 352 * u
    // 0..1 activity from the receive rate; 512 KB/s and above is a full swing.
    readonly property real carrier: Math.min(1, Math.sqrt(SysStats.rxKbs / 512))

    spacing: 12 * u

    function fmtRate(k) {
        return k >= 1024 ? (k / 1024).toFixed(1) + "M" : Math.round(k) + "K";
    }

    HudImage {
        name: "tick-strip"
        width: 300 * root.u
        height: 34 * root.u
        opacity: 0.8
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

        // No box: the glass pane's rim frames the scope. Acid corner ticks,
        // as on the wallpaper frame.
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

    // ── spectrum ────────────────────────────────────────────────────────
    // Thin bars that breathe with the link: a smoothed random walk under a
    // bell envelope, scaled by the carrier; the top quarter clips to amber
    // (the pane's one highlight, so a quiet link shows none). Painted five
    // times a second while the desktop shows, so it stays cheap.
    Canvas {
        id: spectrum
        width: root.span
        height: 48 * root.u
        readonly property int bars: 32
        property var levels: Array(32).fill(0.15)
        readonly property real clip: 0.75
        Timer {
            interval: 200
            repeat: true
            running: root.active
            onTriggered: {
                const n = spectrum.bars, lv = spectrum.levels;
                const gain = 0.3 + 0.7 * root.carrier;
                for (let i = 0; i < n; i++) {
                    const env = 0.3 + 0.7 * Math.exp(-Math.pow((i - n * 0.45) / (n * 0.3), 2));
                    const target = gain * env * (0.6 + 0.4 * Math.random());
                    lv[i] += (target - lv[i]) * 0.4;
                }
                spectrum.requestPaint();
            }
        }
        onPaint: {
            const c = getContext("2d");
            c.clearRect(0, 0, width, height);
            const n = bars, gap = 3 * root.u, bw = (width - gap * (n - 1)) / n;
            for (let i = 0; i < n; i++) {
                const x = i * (bw + gap);
                c.fillStyle = Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25);
                c.fillRect(x, 0, bw, height);
                const h = Math.max(2 * root.u, levels[i] * height), base = Math.min(h, clip * height);
                c.fillStyle = Theme.primary;
                c.fillRect(x, height - base, bw, base);
                if (h > base) {
                    c.fillStyle = Theme.accent;
                    c.fillRect(x, height - h, bw, h - base);
                }
            }
        }
    }
}
