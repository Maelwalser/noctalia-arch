import QtQuick
import Quickshell
import Quickshell.Wayland

// The unlock reveal of one output. While the session is locked this item is
// armed: it keeps a live copy of the screen (the lock surface, which the
// compositor still renders for screen capture), so the hud-unlock window under
// the lock already shows the lock scene the frame the lock surface is gone.
// Noctalia's session_unlocked hook then releases it and the fold plays: the
// lock scene parts as two frosted glass doors sliding aside (shaders/fold.frag).
// Without the lock, `preview` plays it over the static lock art.
Item {
    id: fold
    required property ShellScreen screen

    property bool armed: false
    property bool pending: false   // released, waiting for the capture to settle
    property bool playing: false
    property bool held: false
    // The live capture carries the panes only after a real lock; preview and
    // hold use the static art, since outside the lock the capture is the desktop.
    property bool fromCapture: false
    readonly property bool active: armed || pending || playing || held
    // When the window should be mapped. Armed, it waits for the capture's
    // first frame, so it never shows black under the lock; if no frame ever
    // comes, the fold is skipped and the desktop simply appears.
    readonly property bool showing: active && (!fromCapture || capture.hasContent)
    property real progress: 0

    readonly property int durationMs: 1000

    // The static scene of this output (hud-build lock/static-<output>.png is
    // keyed by Noctalia's output selector: the connector or a word of the
    // monitor description), found by trying each name.
    // (The screen is null for a moment while its output is being unplugged.)
    readonly property var sceneNames: !screen ? [] : [screen.name]
        .concat((screen.model + " " + screen.manufacturer).split(/\s+/).filter(t => t.length > 0))
    property int sceneIndex: 0

    function arm() {
        anim.stop();
        settle.stop();
        playing = false;
        pending = false;
        held = false;
        progress = 0;
        fromCapture = true;
        armed = true;
        console.info("hud: lock armed on", screen.name);
    }
    function release() {
        if (!armed)
            return;
        // Pending is raised before armed drops: the window and the capture
        // view live on `active`, and a gap between the two would unmap the
        // one and destroy the other.
        pending = true;
        armed = false;
        console.info("hud: unlock fold on", screen.name, capture.hasContent ? "from the capture" : "WITHOUT a capture");
        // Frames already asked of the capture still land after it stops; they
        // show this window's own (unfolded) copy, so let them drain before
        // the doors move, or one would fold the fold.
        settle.restart();
    }
    function preview() {
        if (armed || pending || playing)
            return;
        held = false;
        fromCapture = false;
        progress = 0;
        play();
    }
    function hold(p) {
        anim.stop();
        settle.stop();
        playing = false;
        pending = false;
        armed = false;
        fromCapture = false;
        progress = p;
        held = true;
    }
    function clear() {
        anim.stop();
        settle.stop();
        playing = false;
        pending = false;
        held = false;
        armed = false;
        fromCapture = false;
        progress = 0;
    }
    property int frames: 0
    property real startedAt: 0
    onProgressChanged: if (playing) frames += 1
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    function play() {
        frames = 0;
        startedAt = Date.now();
        playing = true;
        anim.restart();
    }
    // What the panes would carry right now, as a PNG (checks the capture).
    // Only answers while the window is mapped: locked, previewing or held.
    function dump(path) {
        snapshot.grabToImage(result => {
            console.info("hud: snapshot", result.saveToFile(path) ? "saved to" : "NOT saved to", path);
        });
    }

    Timer {
        id: settle
        interval: 90
        onTriggered: {
            fold.pending = false;
            fold.play();
        }
    }

    NumberAnimation {
        id: anim
        target: fold
        property: "progress"
        from: 0
        to: 1
        duration: fold.durationMs
        easing.type: Easing.Linear  // the shader shapes the motion
        // Fully open is fully transparent, so the window can go without a
        // reset here (a reset would be an opaque frame if one more got drawn).
        onFinished: {
            fold.playing = false;
            console.info("hud: fold on", fold.screen.name, "drew", fold.frames, "frames in", Date.now() - fold.startedAt, "ms");
        }
    }

    // What the doors carry: the live capture while locked, else the static art.
    Item {
        id: snapshot
        anchors.fill: parent

        Image {
            anchors.fill: parent
            source: "file://" + Theme.home + "/.local/share/hud/lock/static-" + fold.sceneNames[fold.sceneIndex] + ".png"
            fillMode: Image.Stretch
            asynchronous: true
            onStatusChanged: {
                if (status === Image.Error && fold.sceneIndex + 1 < fold.sceneNames.length)
                    fold.sceneIndex += 1;
            }
        }
        // A view with no source, there from the start: it only gets the
        // capture buffers set up (done on the first window shown), so the
        // real view below can start at once. Without it, a view created
        // on demand in a fresh process waits for a window to show, while the
        // window waits for the view's first frame.
        ScreencopyView {
            captureSource: null
            visible: false
        }
        // The real view exists only from the lock to the end of the fold: a
        // view still holding an output when that output is unplugged took
        // Quickshell 0.3.2 down.
        Loader {
            id: capture
            anchors.fill: parent
            active: fold.fromCapture && fold.active
            readonly property bool hasContent: item ? item.hasContent : false
            sourceComponent: ScreencopyView {
                captureSource: fold.screen
                paintCursor: false
                visible: hasContent
            }
        }
        // 30 frames a second is plenty for a clock and a password field, and
        // costs the compositor a third of what a live capture does.
        Timer {
            interval: 33
            repeat: true
            running: fold.armed
            triggeredOnStart: true
            onTriggered: if (capture.item) capture.item.captureFrame()
        }
    }

    ShaderEffectSource {
        id: source
        sourceItem: snapshot
        hideSource: true
        live: true
        // Mipmaps keep the fine lines of the scene from crawling as it moves.
        mipmap: true
        smooth: true
    }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: "file://" + Theme.assetDir + "fold.frag.qsb"

        property var src: source
        property real progress: fold.progress
        property real aspect: width / Math.max(height, 1)
        property real pxPerUnit: width * (fold.screen ? fold.screen.devicePixelRatio : 1)
        // Frost: a milky haze in the palette's own light tone (between the
        // dim and the full foreground) filling most of the door's presence;
        // what it leaves darkens, so the door reads as glass rather than mist.
        property color veil: fold.mix(Theme.fgDim, Theme.fg, 0.35)
        property real veilShare: 0.9
        property color accent: Theme.primary
        property color warm: Theme.accent
    }
}
