import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// ACID//HUD desktop overlay: two click-through layers per output, above
// Noctalia's wallpaper and below every window. hud-glass carries the liquid-
// glass panes (hyprglass renders them, see hyprland/plugins.lua), hud-overlay
// the content on top of them. Start with `hud-overlay start`. A third window,
// hud-unlock, plays the unlock reveal (UnlockFold.qml) on Noctalia's session
// hooks: `qs -c hud ipc call lock locked|unlocked` (themes/acid.toml), and
// its reverse on `lock close` (hud-lock), locking the session once the doors
// are shut on every output. The desktop scene alone is switched off and on
// with `qs -c hud ipc call overlay off|on|toggle` (hud-overlay toggle, the
// bar's spinner): the process, and with it the lock's doors and readouts,
// stays. Not persisted: every start shows the desktop scene. (Not `show`:
// `qs ipc` takes that for its own subcommand and lists the targets instead.)
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

    // Stats are sampled only while at least one output shows the desktop.
    // Derived from the live instances rather than counted, so it cannot drift.
    Binding {
        target: SysStats
        property: "active"
        value: screens.instances.some(o => o.sceneActive)
    }

    Variants {
        id: screens
        model: Quickshell.screens

        Scope {
            id: output
            required property var modelData
            readonly property bool sceneActive: scene.active
            readonly property Item fold: unlock

            // Declared first so it maps under hud-overlay; the `order` layer
            // rule in hyprland/looknfeel.lua keeps it there after every remap.
            // It is shown and hidden outright: a fade would have hyprglass
            // rebuild the glass outline on every frame of it.
            PanelWindow {
                screen: output.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                visible: output.sceneActive

                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.namespace: "hud-glass"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                GlassScene { anchors.fill: parent }
            }
            // The bottom panes, on a namespace of their own for a clearer
            // glass (GlassScene.qml).
            PanelWindow {
                screen: output.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                visible: output.sceneActive

                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.namespace: "hud-clearglass"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                GlassScene { anchors.fill: parent; corners: true }
            }

            PanelWindow {
                id: win
                screen: output.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                // Empty region: no input is ever taken, clicks reach the desktop.
                mask: Region {}

                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.namespace: "hud-overlay"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                HudScene {
                    id: scene
                    anchors.fill: parent
                    monitor: Hyprland.monitorFor(output.modelData)
                    shown: shell.overlayOn
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
                    active: parent.visible
                    backed: true
                    covered: unlock.covering
                    opacity: unlock.closing ? 0 : 1
                }
            }
        }
    }
}
