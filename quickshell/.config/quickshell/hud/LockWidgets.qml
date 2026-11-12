import QtQuick
import Quickshell

// The lock screen's live readouts: the hero time, the seconds beside it,
// the numeric date and ISO week under the ruler, and the stepping reticle
// by the SYS//LOCKED plate, and the six telemetry graphs in the cards at the
// sides (with a copy of the empty password field for the closing doors). The static lock art (hud-build) frames them, so
// they sit where its LOCK_* spec puts them, in the same units: u = 1/800 of
// the output's logical height, x from the centre. The HUD draws them rather
// than Noctalia's lock widgets so the closing doors carry them live (they
// are part of UnlockFold's snapshot) and they then go on above the lock
// surface (shell.qml, hud-lockwidgets) without changing hands; a Noctalia
// widget would only appear once its lock surface is up. Keep the spec here
// and in hud-build in step.
Item {
    id: root
    required property ShellScreen screen
    // The key of this output's lock art (static-<key>.png, reticle-<key>.png):
    // not always the connector, so UnlockFold resolves it (sceneName).
    property string sceneName: ""
    property bool active: true
    // Above the lock (shell.qml) each box is backed by an opaque copy of
    // the scene under it (the same backdrop and static art Noctalia draws,
    // which match pixel for pixel): the window then replaces what is
    // beneath instead of blending over it, so it can map whenever it is
    // ready, over the fold's copy or over the lock surface, and nothing
    // shifts or brightens. The copy inside the fold's snapshot sits on the
    // scene already and needs none.
    property bool backed: false
    // The whole scene under the readouts, while the lock surface may not
    // have painted its own yet (UnlockFold.covering); it fades out to
    // reveal the lock's own widgets.
    property bool covered: false

    readonly property real u: height / 800
    readonly property real dpr: screen ? screen.devicePixelRatio : 1
    // All copies share one clock and one reticle counter (LockClock.qml),
    // and everything is placed on whole device pixels, so the copy in the
    // fold's snapshot and the window above the lock rasterise alike.
    readonly property SystemClock clock: LockClock.clock
    onActiveChanged: if (active) LockClock.active = true

    function snap(v) { return Math.round(v * dpr) / dpr; }

    // Up at once (a fade in let the lock surface's black through: it can
    // be up two frames after the doors shut), out with a short fade.
    Box {
        id: cover
        cx: 0; cy: 400; bw: root.u > 0 ? root.width / root.u : 0; bh: 800
        visible: opacity > 0
        opacity: root.covered ? 1 : 0
        // One layer: the scene and the field copy on it fade as a single
        // opaque picture, so over the identical lock surface the fade
        // changes nothing. Faded item by item, the field's ring and text
        // were blended twice (the copy over the half-faded scene over the
        // real field) and dipped darker mid-fade.
        layer.enabled: root.backed
        Backing { anchors.fill: parent }
        Field {}
        NumberAnimation { id: coverOut; target: cover; property: "opacity"; to: 0; duration: 180 }
    }
    onCoveredChanged: {
        coverOut.stop();
        if (covered)
            cover.opacity = 1;
        else
            coverOut.start();
    }

    // The password field's stand-in (LockField.qml): on the closing doors
    // (the copy below), and above the lock as part of the cover, which then
    // fades over the real field, which looks the same.
    component Field: LockField {
        width: root.width
        height: root.height
        dpr: root.dpr
    }
    Field { visible: !root.backed }

    // Noctalia writes "Authentication failure" in red across the caption
    // above the field after a wrong password and leaves it there; it has no
    // setting for that. The strip it lands in is static art, so above the
    // lock it is simply kept as the scene (the ring's blink below says it).
    // The message sits a fixed distance above the field, not one in u, hence
    // the strip's height: everything from the caption down to the field.
    Box {
        cx: 0; cy: 617; bw: 300; bh: 42
        visible: root.backed
        Backing { anchors.fill: parent }
    }

    // A wrong password (LockClock.denied, from shell.qml): the real field's
    // ring blinks red twice, drawn over it up here.
    Field {
        id: denied
        visible: root.backed && opacity > 0
        opacity: 0
        body: false
        ring: Theme.error
        SequentialAnimation {
            id: deny
            NumberAnimation { target: denied; property: "opacity"; to: 1; duration: 50 }
            PauseAnimation { duration: 130 }
            NumberAnimation { target: denied; property: "opacity"; to: 0; duration: 90 }
            PauseAnimation { duration: 50 }
            NumberAnimation { target: denied; property: "opacity"; to: 1; duration: 50 }
            PauseAnimation { duration: 320 }
            NumberAnimation { target: denied; property: "opacity"; to: 0; duration: 380; easing.type: Easing.OutQuad }
        }
        Connections {
            target: LockClock
            enabled: root.backed
            function onDenied() { deny.restart(); }
        }
    }

    // A box of the spec, placed on device pixels.
    component Box: Item {
        property real cx: 0
        property real cy: 0
        property real bw: 10
        property real bh: 10
        x: root.snap(root.width / 2 + (cx - bw / 2) * root.u)
        y: root.snap((cy - bh / 2) * root.u)
        width: root.snap(bw * root.u)
        height: root.snap(bh * root.u)
    }

    // The scene under a box: the full-size images, clipped, at the same
    // place on the output as the fold's copies of them. Loaded in step so
    // the window's first frame is whole (the files are cached anyway).
    component Backing: Item {
        clip: true
        Image {
            x: -parent.parent.x; y: -parent.parent.y
            width: root.width; height: root.height
            source: "file://" + Theme.home + "/.local/share/hud/lock/backdrop.png"
            fillMode: Image.PreserveAspectCrop
        }
        Image {
            x: -parent.parent.x; y: -parent.parent.y
            width: root.width; height: root.height
            source: root.sceneName ? "file://" + Theme.home + "/.local/share/hud/lock/static-" + root.sceneName + ".png?v=" + Theme.version : ""
            fillMode: Image.Stretch
        }
    }

    // A text centred in its box, sized as Noctalia's clock widget sized it:
    // its label is laid out at 4x the body size (56 px) and scaled to fit
    // the box, keeping its aspect, so the box is the knob.
    component Readout: Box {
        id: readout
        property alias text: label.text
        property alias color: label.color
        property alias font: label.font
        property string probe: label.text  // the widest text the box must fit
        property real pixelSize: Math.max(1, 56 * Math.min(width / Math.max(natural.width, 1), height / Math.max(natural.height, 1)))
        // Noctalia centres the digits themselves in the box; Qt centres the
        // line box (ascent + descent), which puts the hero time's digits a
        // little high: measured 3 px at a 232 px face.
        property real dropEm: 0
        // A box inside another box (the seconds, date and week sit in the
        // time's) leaves the backing to it: its own opaque copy of the scene
        // would cut into the time's wide digits (the 8's bottom right corner).
        property bool ownBacking: true
        Backing { anchors.fill: parent; visible: root.backed && readout.ownBacking }
        Text {
            id: label
            x: 0
            y: root.snap(readout.dropEm * font.pixelSize)
            width: parent.width
            height: parent.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            font.pixelSize: readout.pixelSize
        }
        TextMetrics {
            id: natural
            font.family: label.font.family
            font.weight: label.font.weight
            font.pixelSize: 56
            text: readout.probe
        }
    }

    Readout {
        cx: 0; cy: 226; bw: 560; bh: 280
        text: Qt.formatDateTime(root.clock.date, "HH:mm")
        probe: "00:00"
        color: Theme.fg
        font.family: Theme.displayFont
        font.weight: Font.DemiBold
        // Noctalia's fit of this face came out smaller than Qt's metrics
        // give (measured: 155 px at u = 1, digits 162 px tall at scale 1.5);
        // the seconds sit just right of its last digit, so keep this size.
        pixelSize: 155 * root.u
        dropEm: 0.013
    }
    Readout {
        cx: 224; cy: 266; bw: 64; bh: 34
        text: String(root.clock.seconds).padStart(2, "0")
        probe: "00"
        ownBacking: false
        color: Theme.primary
        font.family: Theme.monoFont
    }
    Readout {
        cx: -52; cy: 358; bw: 120; bh: 16
        text: Qt.formatDateTime(root.clock.date, "dd.MM.yy")
        probe: "00.00.00"
        ownBacking: false
        color: Theme.fgDim
        font.family: Theme.monoFont
    }
    Readout {
        cx: 32; cy: 358; bw: 80; bh: 16
        text: "W" + String(root.isoWeek(root.clock.date)).padStart(2, "0")
        probe: "W00"
        ownBacking: false
        color: Theme.fgDim
        font.family: Theme.monoFont
    }

    // The telemetry cards' graphs (hud-build lock_cards frames them: two
    // banks of three at +-455 u, 170 x 120 u cards from 205 u down, 12 u
    // apart; the graph takes the card below its header rule). They are
    // drawn as Noctalia's sysmon widget drew them when these were its lock
    // widgets (measured on captures of that lock): the last two minutes as
    // a smooth 1.6 px line, newest at the right, over a fill that fades
    // towards the baseline, and under it, centred, the stat's glyph (from
    // Noctalia's own icon font) and the reading. The history is SysStats',
    // which samples on the desktop too: the graphs are whole while the doors
    // are still closing and never start over.
    FontLoader { id: glyphs; source: "file:///usr/share/noctalia/assets/fonts/noctalia-tabler.ttf" }
    component Reading: Row {
        property string glyph
        property alias text: reading.text
        property color color: Theme.primary
        spacing: 5.5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.glyph
            color: parent.color
            renderType: Text.NativeRendering
            font.family: glyphs.name
            font.pointSize: 9.15  // 12.2 px: a pixel size takes whole pixels only
        }
        Text {
            id: reading
            anchors.verticalCenter: parent.verticalCenter
            color: parent.color
            renderType: Text.NativeRendering
            font.family: Theme.monoFont
            font.pointSize: 7.2  // 9.6 px: a pixel size takes whole pixels only
        }
    }
    component Graph: Box {
        id: graph
        property int row: 0
        property int side: -1
        property string stat          // key of SysStats.history
        property string stat2: ""     // a second trace, in the dim colour, with its own reading
        property string glyph
        property string glyph2: ""
        property string value         // the reading
        property string value2: ""
        property real full: 1         // the value at the top of the graph; 0 = the history's peak
        property real floor: 0        // the least a self-scaled graph spans
        cx: side * 455; cy: 277 + row * 132; bw: 150; bh: 80
        clip: true
        Backing { anchors.fill: parent; visible: root.backed }
        Canvas {
            id: trace
            // As wide as the widget made it: 136 px, or the whole box under
            // a reading wider than that.
            readonly property real inset: readings.width > parent.width - 14 ? 0 : 6.67
            x: inset
            width: parent.width - 2 * inset
            height: parent.height - 20
            Connections {
                target: SysStats
                function onSampled() { trace.requestPaint(); }
            }
            Connections {
                target: Theme
                function onPrimaryChanged() { trace.requestPaint(); }
            }
            onInsetChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.clearRect(0, 0, width, height);
                // The baseline sits 24.2 px above the box's bottom edge and
                // a full reading 51.7 px above that.
                const base = height - 4.2, span = 51.7, n = SysStats.historyLength, step = width / (n - 1);
                const keys = graph.stat2 ? [graph.stat, graph.stat2] : [graph.stat];
                let top = graph.full;
                if (top <= 0) {
                    top = graph.floor;
                    for (const k of keys)
                        for (const v of SysStats.history[k])
                            top = Math.max(top, v);
                }
                for (const k of keys) {
                    // Oldest first, a short history standing on the baseline.
                    const h = SysStats.history[k], pts = [];
                    for (let i = 0; i < n; i++) {
                        const v = i < n - h.length ? 0 : h[i - (n - h.length)];
                        pts.push([i * step, base - span * Math.max(0, Math.min(1, v / top))]);
                    }
                    // A smooth curve through the samples (Catmull-Rom).
                    const curve = () => {
                        for (let i = 0; i < n - 1; i++) {
                            const p0 = pts[Math.max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(i + 2, n - 1)];
                            c.bezierCurveTo(p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6,
                                            p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6, p2[0], p2[1]);
                        }
                    };
                    const col = k === graph.stat ? Theme.primary : Theme.fgDim;
                    const fill = c.createLinearGradient(0, base - span, 0, base);
                    fill.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 0.2));
                    fill.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0));
                    c.beginPath();
                    c.moveTo(0, base);
                    c.lineTo(pts[0][0], pts[0][1]);
                    curve();
                    c.lineTo(width, base);
                    c.closePath();
                    c.fillStyle = fill;
                    c.fill();
                    c.beginPath();
                    c.moveTo(pts[0][0], pts[0][1]);
                    curve();
                    c.strokeStyle = col;
                    c.lineWidth = 1.6;
                    c.lineJoin = "round";
                    c.stroke();
                }
            }
        }
        Row {
            id: readings
            spacing: 12
            x: Math.max(0, (parent.width - width) / 2)
            y: parent.height - 6.3 - height / 2
            Reading { glyph: graph.glyph; text: graph.value }
            Reading { visible: graph.stat2 !== ""; glyph: graph.glyph2; text: graph.value2; color: Theme.fgDim }
        }
    }
    function rate(kbs) {
        return kbs >= 1024 ? (kbs / 1024).toFixed(1) + " MB/s" : kbs.toFixed(1) + " kB/s";
    }
    Graph { side: -1; row: 0; stat: "cpu"; glyph: "勺"; value: Math.round(SysStats.cpu * 100) + "%" }
    Graph {
        side: -1; row: 1; stat: "mhz"; glyph: ""
        full: Math.max(SysStats.cpuMaxMhz, 1)
        value: (SysStats.cpuMhz / 1000).toFixed(1) + " GHz"
    }
    Graph { side: -1; row: 2; stat: "mem"; glyph: ""; value: Math.round(SysStats.mem * 100) + "%" }
    Graph { side: 1; row: 0; stat: "temp"; glyph: ""; full: 100; value: Math.round(SysStats.tempC) + "°C" }
    Graph {
        side: 1; row: 1; stat: "rx"; stat2: "tx"; glyph: ""; glyph2: ""
        full: 0; floor: 1
        value: root.rate(SysStats.rxKbs); value2: root.rate(SysStats.txKbs)
    }
    Graph { side: 1; row: 2; stat: "swap"; glyph: ""; value: Math.round(SysStats.swap * 100) + "%" }

    // The reticle's frames are the ring alone on a transparent ground
    // (hud-build bake_reticle: one PNG strip, RETICLE_FRAMES side by side),
    // finished at the box's physical size, so the box lands on whole pixels
    // with an even size, as reticle_box computes them, and is drawn texel
    // for texel. The strip slides behind the box one frame per tick of the
    // shared counter, so every copy shows the same one.
    readonly property int reticleFrames: 45
    Item {
        id: reticle
        readonly property real k: root.u * root.dpr
        readonly property int size: 2 * Math.round(26 * k / 2)
        readonly property int px: Math.round(root.width * root.dpr / 2 - 134 * k - size / 2)
        readonly property int py: Math.round(112 * k - size / 2)
        x: px / root.dpr
        y: py / root.dpr
        width: size / root.dpr
        height: size / root.dpr
        clip: true
        Backing { anchors.fill: parent; visible: root.backed }
        Image {
            x: -(LockClock.reticleTick % root.reticleFrames) * reticle.width
            width: root.reticleFrames * reticle.width
            height: reticle.height
            source: root.sceneName ? "file://" + Theme.home + "/.local/share/hud/lock/reticle-" + root.sceneName + ".png?v=" + Theme.version : ""
            smooth: false
        }
    }

    // ISO 8601 week number (Qt's date formats have none).
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7);
    }
}
