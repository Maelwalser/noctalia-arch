// Animations are stepped by the clock, not by a count of frames at the
// primary screen's refresh rate: the lock's doors are animated per window on
// its render thread (UnlockFold.qml), and counted in 60 Hz steps they ran at
// twice the speed on a 120 Hz monitor.
//@ pragma Env QSG_USE_SIMPLE_ANIMATION_DRIVER=1
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// ACID//HUD desktop overlay: two click-through layers for each pane of an
// output, above Noctalia's wallpaper and below every window. hud-glass
// carries the liquid-glass pane (hyprglass renders it, see
// hyprland/plugins.lua), hud-overlay the content on top of it. Start with `hud-overlay start`. Another window,
// hud-unlock, plays the unlock reveal (UnlockFold.qml) on Noctalia's session
// hooks: `qs -c hud ipc call lock locked|unlocked` (themes/acid.toml), and
// its reverse on `lock close` (hud-lock), locking the session once the doors
// are shut on every output. The desktop scene alone is switched off and on
// with `qs -c hud ipc call overlay off|on|toggle` (hud-overlay toggle, the
// bar's spinner): the process, and with it the lock's doors and readouts,
// stays. Not persisted: every start shows the desktop scene. (Not `show`:
// `qs ipc` takes that for its own subcommand and lists the targets instead.)
// Launcher.qml is the app launcher, on its own two layers, and Overview.qml
// the overview of the workspaces and their windows, on one.
ShellRoot {
    id: shell

    property bool overlayOn: true
    IpcHandler {
        target: "overlay"
        function on(): void { shell.overlayOn = true; }
        function off(): void { shell.overlayOn = false; }
        function toggle(): void { shell.overlayOn = !shell.overlayOn; }
        function status(): string { return shell.overlayOn ? "on" : "off"; }
    }

    // The state as a file, for the bar's spinner (spinner.luau): it turns
    // only while the scene is on, and a bar widget can read a file on every
    // tick but not ask over IPC. Replaced atomically, never read half-written.
    onOverlayOnChanged: overlayState.sync()
    Component.onCompleted: overlayState.sync()
    Process {
        id: overlayState
        property string written: ""
        property string writing: ""
        command: ["sh", "-c",
            "d=\"${XDG_RUNTIME_DIR:-/tmp}/mael-hud\" && mkdir -p \"$d\" && printf %s \"$1\" > \"$d/.overlay\" && mv \"$d/.overlay\" \"$d/overlay\"",
            "sh", writing]
        // One write at a time; a toggle made meanwhile is written after it.
        function sync() {
            const want = shell.overlayOn ? "on" : "off";
            if (running || want === written)
                return;
            writing = want;
            running = true;
        }
        onExited: (code, status) => {
            if (code !== 0) {
                console.warn("hud: cannot publish the overlay state, exit", code);
                return;
            }
            written = writing;
            sync();
        }
    }

    function eachFold(fn, output) {
        screens.instances.forEach(o => { if (!output || o.fold.screen.name === output) fn(o.fold); });
    }

    IpcHandler {
        target: "lock"
        function locked(): void { shell.unlockedSeen = 0; shell.eachFold(f => f.arm()); }
        function unlocked(): void { shell.eachFold(f => f.release()); }
        // Lock: shut the doors over the desktop, then lock (hud-lock). With an
        // output named, only that one plays and nothing is locked (for review).
        function close(output: string): void { shell.eachFold(f => f.close(), output); }
        // Tuning without locking: play it over the static lock art, or freeze
        // it at a point of the fold (0..1) for a screenshot; `clear` ends that.
        // `output` is a connector name (e.g. the claude-shot monitor), "" = all.
        function preview(output: string): void { shell.eachFold(f => f.preview(), output); }
        function hold(output: string, progress: real): void { shell.eachFold(f => f.hold(progress), output); }
        function clear(output: string): void { shell.eachFold(f => f.clear(), output); }
        // The real path on one output without a session lock (the capture
        // then carries the desktop): arm, wait, release.
        function arm(output: string): void { shell.eachFold(f => f.arm(), output); }
        function release(output: string): void { shell.eachFold(f => f.release(), output); }
        // The wrong-password blink of the field, without a wrong password.
        function deny(): void { LockClock.denied(); }
        function dump(output: string, path: string): void { shell.eachFold(f => f.dump(path + "-" + f.screen.name + ".png"), output); }
    }

    // The doors are shut on every output: lock now, and the lock surface
    // covers the identical scene.
    readonly property bool allShut: screens.instances.length > 0 && screens.instances.every(o => o.fold.closed)
    onAllShutChanged: if (allShut) lockSession.running = true
    Process {
        id: lockSession
        command: ["noctalia", "msg", "session", "lock"]
        onExited: (code, status) => { if (code !== 0) console.warn("hud: noctalia msg session lock exited with", code); }
    }

    // Safety net for the armed window (it is opaque): if the session shows as
    // unlocked twice in a row while we still think it is locked, the unlocked
    // hook was lost, so release it ourselves. (`qs -c hud ipc call lock clear`
    // is the manual way out.)
    readonly property bool anyArmed: screens.instances.some(o => o.fold.armed)
    onAnyArmedChanged: unlockedSeen = 0
    property int unlockedSeen: 0
    Timer {
        interval: 1500
        repeat: true
        running: shell.anyArmed
        onTriggered: lockedHint.running = true
    }
    Process {
        id: lockedHint
        command: ["sh", "-c",
            // The graphical session: ours, else the user's seat0 session.
            "loginctl show-session \"${XDG_SESSION_ID:-$(loginctl list-sessions --no-legend | awk -v u=\"$USER\" '$3 == u && $4 == \"seat0\" { print $1; exit }')}\" -p LockedHint --value"]
        stdout: StdioCollector {
            onStreamFinished: {
                const hint = text.trim();
                if (hint === "no") {
                    if (++shell.unlockedSeen >= 2) {
                        console.warn("hud: session unlocked without the hook, releasing the fold");
                        shell.eachFold(f => f.release());
                        shell.unlockedSeen = 0;
                    }
                } else {
                    if (hint !== "yes")
                        console.warn("hud: cannot read the session's LockedHint:", JSON.stringify(hint));
                    shell.unlockedSeen = 0;
                }
            }
        }
    }

    // A wrong password: Noctalia has no hook for it, but its PAM check logs
    // the failure to the journal the moment it happens, so follow that
    // while locked and have the field blink red (LockWidgets.qml).
    Process {
        running: shell.anyArmed
        command: ["journalctl", "--follow", "--lines=0", "--output=cat", "--identifier=noctalia"]
        stdout: SplitParser {
            onRead: line => { if (line.includes("authentication failure")) LockClock.denied(); }
        }
    }

    // Stats are sampled only while at least one output shows the desktop or
    // the lock (its graphs, LockWidgets.qml). Derived from the live instances
    // rather than counted, so it cannot drift.
    Binding {
        target: SysStats
        property: "active"
        value: screens.instances.some(o => o.sceneActive || o.fold.active)
    }

    // The app launcher (Alt+Space): `qs -c hud ipc call launcher toggle`.
    Launcher {}

    // The stack overview (ALT + Tab): `qs -c hud ipc call overview toggle`.
    Overview {}

    // Glass tooltips for the bar's HUD widgets: `qs -c hud ipc call tip put/drop`.
    Tip {}

    Variants {
        id: screens
        model: Quickshell.screens

        Scope {
            id: output
            required property var modelData
            readonly property bool sceneActive: scene.active
            readonly property Item fold: unlock

            // The scene's state. It draws nothing: every pane has two windows
            // of its own below, as large as the pane (SceneWindow), instead
            // of two for all three that covered the screen.
            HudScene {
                id: scene
                width: output.modelData.width
                height: output.modelData.height
                monitor: Hyprland.monitorFor(output.modelData)
                shown: shell.overlayOn
            }

            // The glass panes. Declared first so they map under hud-overlay;
            // the `order` layer rule in hyprland/looknfeel.lua keeps them
            // there after every remap. They are shown and hidden outright: a
            // fade would have hyprglass rebuild the glass outline on every
            // frame of it.
            SceneWindow {
                screen: output.modelData
                ns: "hud-glass"
                card: scene.heroCard
                visible: output.sceneActive
                GlassScene { anchors.fill: parent; box: scene.heroCard }
            }
            SceneWindow {
                screen: output.modelData
                ns: "hud-glass"
                card: scene.telemetryCard
                visible: output.sceneActive
                GlassScene { anchors.fill: parent; box: scene.telemetryCard }
            }
            SceneWindow {
                screen: output.modelData
                ns: "hud-glass"
                card: scene.signalCard
                visible: output.sceneActive
                GlassScene { anchors.fill: parent; box: scene.signalCard }
            }

            // The content on the panes: each block sits inside its glass
            // pane, inset by the pane's padding. Unmapped while the desktop
            // is covered: Qt redraws every mapped window of the process on
            // each frame while any animation runs, so with the scene
            // animating on one output, the covered output's windows were
            // committed again on every frame, and the glass of the windows
            // over them sampled and blurred anew.
            SceneWindow {
                screen: output.modelData
                ns: "hud-overlay"
                card: scene.heroCard
                visible: scene.showing

                Glitch {
                    opacity: scene.fadeOpacity
                    box: scene.heroCard
                    u: scene.u
                    clock: scene.clock
                    running: scene.lockingOn
                    seed: 1

                    HeroClock {
                        u: scene.u
                        active: scene.active
                        x: scene.pad
                        y: scene.pad
                        width: parent.width - 2 * scene.pad
                        height: parent.height - 2 * scene.pad
                    }
                }
            }
            SceneWindow {
                screen: output.modelData
                ns: "hud-overlay"
                card: scene.telemetryCard
                visible: scene.showing

                Glitch {
                    opacity: scene.fadeOpacity
                    box: scene.telemetryCard
                    u: scene.u
                    clock: scene.clock
                    running: scene.lockingOn
                    delay: scene.stagger
                    seed: 2

                    Telemetry {
                        u: scene.u
                        x: scene.pad
                        y: scene.pad
                        width: parent.width - 2 * scene.pad
                    }
                }
            }
            SceneWindow {
                screen: output.modelData
                ns: "hud-overlay"
                card: scene.signalCard
                visible: scene.showing

                Glitch {
                    opacity: scene.fadeOpacity
                    box: scene.signalCard
                    u: scene.u
                    clock: scene.clock
                    running: scene.lockingOn
                    delay: 2 * scene.stagger
                    seed: 3

                    Signal {
                        u: scene.u
                        active: scene.active
                        x: scene.pad
                        y: scene.pad
                    }
                }
            }

            // The unlock reveal, above everything: mapped while the session is
            // locked (under the lock surface, so unseen) and for the fold.
            PanelWindow {
                screen: output.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                visible: unlock.showing

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "hud-unlock"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                UnlockFold {
                    id: unlock
                    anchors.fill: parent
                    screen: output.modelData
                }
            }

            // The lock's live readouts (LockWidgets.qml), above the lock
            // surface (`above_lock` layer rule, hyprland/looknfeel.lua).
            // Mapped, but blank, while the doors close, so it is surely in
            // place (a layer surface needs its configure round trip, and its
            // images are loaded) when they are shut: from then on it shows
            // them over the fold's identical copy, then over the lock
            // surface; it goes with the unlock, when the fold's capture
            // carries them instead.
            PanelWindow {
                screen: output.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                visible: unlock.readoutsUp

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "hud-lockwidgets"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                LockWidgets {
                    anchors.fill: parent
                    screen: output.modelData
                    sceneName: unlock.sceneName ?? ""
                    // The window's own condition, not parent.visible: that is
                    // the content item, true whether or not the window is
                    // mapped, and it kept the reticle's FrameAnimation going
                    // for good. A running FrameAnimation has every window of
                    // this process redraw and commit on each frame.
                    active: unlock.readoutsUp
                    backed: true
                    covered: unlock.covering
                    opacity: unlock.closing ? 0 : 1
                }
            }
        }
    }
}
