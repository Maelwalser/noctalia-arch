import QtQuick
import Quickshell

// The lock screen's live readouts: the hero time, the seconds beside it,
// the numeric date and ISO week under the ruler, and the stepping reticle
// by the SYS//LOCKED plate. The static lock art (hud-build) frames them, so
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
        Backing { anchors.fill: parent }
        NumberAnimation { id: coverOut; target: cover; property: "opacity"; to: 0; duration: 180 }
    }
    onCoveredChanged: {
        coverOut.stop();
        if (covered)
            cover.opacity = 1;
        else
            coverOut.start();
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
            source: root.screen ? "file://" + Theme.home + "/.local/share/hud/lock/static-" + root.screen.name + ".png" : ""
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

    // The reticle GIF was baked over the scene under it (hud-build
    // bake_reticle), so it must land on the same physical pixels: whole
    // pixels and an even size, as reticle_box computes them.
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
        Backing { anchors.fill: parent; visible: root.backed }
        AnimatedImage {
            anchors.fill: parent
            source: root.screen ? "file://" + Theme.home + "/.local/share/hud/lock/reticle-" + root.screen.name + ".gif" : ""
            // Stepped by the shared counter, not by its own timer, so every
            // copy shows the same frame.
            playing: false
            currentFrame: frameCount > 0 ? LockClock.reticleTick % frameCount : 0
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
