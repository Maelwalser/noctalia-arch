import QtQuick
import Quickshell
import Quickshell.Wayland

// The unlock reveal of one output. While the session is locked this item is
// armed: it keeps a live copy of the screen (the lock surface, which the
// compositor still renders for screen capture), so the hud-unlock window under
// the lock already shows the lock scene the frame the lock surface is gone.
// Noctalia's session_unlocked hook then releases it and the fold plays: the
// seam splits the lock scene from the centre out and it parts as two glass
// doors sliding aside (shaders/fold.frag). The lock art already carries the
// sheet's light bands (hud-build), so the first frame is the lock itself.
// Locking (hud-lock) plays the same thing backwards: `close` slides the doors
// shut over the desktop, carrying the lock art and its live readouts
// (LockWidgets.qml), the seam shrinks away and the window holds that scene
// until Noctalia's lock surface covers it. Without the lock, `preview` plays
// the reveal over the static lock art.
Item {
    id: fold
    required property ShellScreen screen

    // One phase at a time, changed in a single assignment: the window and the
    // capture view both live on `active`, and a transition that passed
    // through "idle" for even a tick (two flags flipped one after the other)
    // unmapped the window and destroyed the capture, whose replacement then
    // grabbed the unlocked desktop and the doors carried that instead of the
    // lock scene.
    //   armed    locked: capturing the screen under the lock surface
    //   pending  released, waiting for the capture to settle
    //   playing  the doors are moving (opening)
    //   closing  the doors are moving (shutting, for the lock)
    //   closed   shut: showing the lock scene until the lock surface takes over
    //   held     frozen at `progress` for a screenshot
    property string phase: "idle"
    readonly property bool armed: phase === "armed"
    readonly property bool pending: phase === "pending"
    readonly property bool playing: phase === "playing"
    readonly property bool closing: phase === "closing"
    readonly property bool closed: phase === "closed"
    readonly property bool held: phase === "held"
    readonly property bool active: phase !== "idle"
    // The lock readouts window (shell.qml, hud-lockwidgets) is up on this:
    // one binding on `phase`, because an or of the phase flags passes
    // through false between two phases that both need it (each flag
    // re-evaluates on its own), and a window whose `visible` dips false
    // unmaps and remaps: it was gone for a frame or two at the shut doors
    // and again as the lock armed (seen on a frame recording of the lock).
    readonly property bool readoutsUp: phase === "closing" || phase === "closed" || phase === "armed"
    // While it is up, that window also covers the whole scene, not only the
    // readout boxes, from the shut doors until the lock surface has surely
    // painted its own: Noctalia's surface comes up black but for the
    // password field, its images still loading, for a few frames around
    // the locked hook (seen on a frame recording). The cover is the same
    // backdrop and static art, so its fade reveals nothing but the lock's
    // own widgets: the telemetry graphs and the password field.
    readonly property bool covering: phase === "closed" || (phase === "armed" && !lockSettled)
    property bool lockSettled: false
    Timer { id: settleLock; interval: 500; onTriggered: fold.lockSettled = true }
    // The live capture carries the panes only after a real lock; preview and
    // hold use the static art, since outside the lock the capture is the desktop.
    property bool fromCapture: false
    // When the window should be mapped. Armed, it waits for the capture's
    // first frame, so it never shows black under the lock; if no frame ever
    // comes, the fold is skipped and the desktop simply appears. Sealed (the
    // doors were shut over the desktop), it stays up through the arming, so
    // the lock scene never blinks while the lock surface is on its way.
    readonly property bool showing: active && (sealed || !fromCapture || capture.hasContent)
    property bool sealed: false
    property real progress: 0

    readonly property int durationMs: 1150  // ~125 ms for the seam to stretch out, then the doors

    // Shut: the doors met and the seam closed. The shell locks the session then.
    signal shut()

    // The static scene of this output (hud-build lock/static-<output>.png is
    // keyed by Noctalia's output selector: the connector or a word of the
    // monitor description), found by trying each name.
    // (The screen is null for a moment while its output is being unplugged.)
    readonly property var sceneNames: !screen ? [] : [screen.name]
        .concat((screen.model + " " + screen.manufacturer).split(/\s+/).filter(t => t.length > 0))
    property int sceneIndex: 0
    // The name that resolved (the first one until a miss moves it on); the
    // lock readouts load their art by it too.
    readonly property string sceneName: sceneNames[sceneIndex] ?? ""
    // hud-build renders a new monitor's art after the monitor (and this fold)
    // has appeared, and bumps the asset version then: look again.
    Connections {
        target: Theme
        function onVersionChanged() { fold.sceneIndex = 0; }
    }

    function arm() {
        anim.stop();
        shutAnim.stop();
        settle.stop();
        progress = 0;
        fromCapture = true;
        lockSettled = false;
        settleLock.restart();
        phase = "armed";
        console.info("hud: lock armed on", screen.name);
    }
    function release() {
        if (!armed)
            return;
        phase = "pending";
        sealed = false;
        console.info("hud: unlock fold on", screen.name, capture.hasContent ? "from the capture" : "WITHOUT a capture");
        // Frames already asked of the capture still land after it stops; they
        // show this window's own (unfolded) copy, so let them drain before
        // the doors move, or one would fold the fold.
        settle.restart();
    }
    function preview() {
        if (armed || pending || playing || closing || closed)
            return;
        fromCapture = false;
        progress = 0;
        play();
    }
    // The lock: the doors slide in over the desktop carrying the lock art
    // and the seam closes; `shut` fires at the end and the window stays up,
    // opaque, until the lock surface covers it (`arm`, the locked hook) or,
    // if no lock comes, until the stuck timer takes it down.
    function close() {
        if (armed || pending || closing || closed)
            return;
        anim.stop();
        settle.stop();
        fromCapture = false;
        sealed = false;
        lockSettled = false;
        settleLock.stop();
        progress = 1;
        frames = 0;
        startedAt = Date.now();
        phase = "closing";
        shutAnim.restart();
    }
    // Freezes the fold at `p`. Called while armed, pending or playing it
    // keeps the capture the doors carry (frozen: the timer only runs while
    // armed), so a frame of the real path can be inspected; otherwise it
    // shows the static art.
    function hold(p) {
        anim.stop();
        shutAnim.stop();
        settle.stop();
        if (!active)
            fromCapture = false;
        progress = p;
        phase = "held";
    }
    function clear() {
        anim.stop();
        shutAnim.stop();
        settle.stop();
        phase = "idle";
        sealed = false;
        fromCapture = false;
        lockSettled = false;
        settleLock.stop();
        progress = 0;
    }
    property int frames: 0
    property real startedAt: 0
    onProgressChanged: if (playing || closing) frames += 1
    function play() {
        frames = 0;
        startedAt = Date.now();
        phase = "playing";
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
        onTriggered: fold.play()
    }
    // Shut doors with no lock behind them would leave the screen covered by
    // the lock art, so give the lock a few seconds and then let go.
    Timer {
        interval: 4000
        running: fold.closed
        onTriggered: {
            console.warn("hud: doors shut on", fold.screen.name, "but no lock came, clearing");
            fold.clear();
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
            fold.phase = "idle";
            console.info("hud: fold on", fold.screen.name, "drew", fold.frames, "frames in", Date.now() - fold.startedAt, "ms");
        }
    }
    NumberAnimation {
        id: shutAnim
        target: fold
        property: "progress"
        from: 1
        to: 0
        duration: fold.durationMs
        easing.type: Easing.Linear
        onFinished: {
            fold.sealed = true;
            fold.phase = "closed";
            console.info("hud: doors shut on", fold.screen.name, "drew", fold.frames, "frames in", Date.now() - fold.startedAt, "ms");
            fold.shut();
        }
    }

    // What the doors carry: the live capture while locked, else the lock
    // scene as Noctalia will draw it: its backdrop (lockscreen.wallpaper in
    // themes/acid.toml, filled like it fills it) under the static art, with
    // the live readouts.
    Item {
        id: snapshot
        anchors.fill: parent

        Image {
            anchors.fill: parent
            source: "file://" + Theme.home + "/.local/share/hud/lock/backdrop.png"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Image {
            anchors.fill: parent
            source: "file://" + Theme.home + "/.local/share/hud/lock/static-" + fold.sceneName + ".png?v=" + Theme.version
            fillMode: Image.Stretch
            asynchronous: true
            onStatusChanged: {
                if (status === Image.Error && fold.sceneIndex + 1 < fold.sceneNames.length)
                    fold.sceneIndex += 1;
            }
        }
        // The live readouts while the doors close (or in a preview): the
        // same component the hud-lockwidgets window shows above the lock
        // (shell.qml) from the shut doors on, over this copy, pixel for
        // pixel (its boxes are opaque copies of the scene, so it replaces
        // rather than blends). Under a real lock the capture brings them.
        LockWidgets {
            anchors.fill: parent
            screen: fold.screen
            sceneName: fold.sceneName
            visible: !fold.fromCapture
            active: visible && fold.active
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
        // Kept live: frozen at the start of the slide it could carry a
        // texture that had never been rendered (the doors came out black).
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
        // The lock scene keeps its own brightness on the glass: it gives this
        // share of itself to the blurred desktop behind, which is let through
        // at this fraction of its light (the lock backdrop is about four
        // times darker than the desktop, measured on the alley wallpaper).
        property real glassShare: 0.25
        property real glassDim: 0.15
        property color accent: Theme.primary
    }
}
