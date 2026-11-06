import QtQuick
import Quickshell

// Everything drawn on one output. Positions use the wallpaper's design grid
// (1 u = screen height / 1200) so the overlay lines up with the frame that
// hud-build paints into the wallpaper.
Item {
    id: scene

    property var monitor: null
    readonly property real u: height / 1200
    readonly property bool ultrawide: width / height > 2
    // Nothing to animate behind tiled windows: pause while the workspace is occupied.
    readonly property bool active: {
        const ws = monitor ? monitor.activeWorkspace : null;
        return !ws || ws.toplevels.values.length === 0;
    }
    readonly property real frameTop: 80 * u
    readonly property real frameSide: 28 * u
    // Login name, upper-cased, for the "<USER>//HUD" tags.
    readonly property string user: (Quickshell.env("USER") || "user").toUpperCase()

    // Glitch only when switching to an empty workspace (not on a timer, and not
    // when the last window closes). The workspace id and `active` update in
    // either order on a switch, so the check runs once both have settled.
    readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    property bool switched: false
    function glitchIfSwitched() {
        if (switched && active)
            glitch.trigger();
        switched = false;
    }
    onWorkspaceIdChanged: {
        switched = true;
        Qt.callLater(glitchIfSwitched);
    }

    SystemClock {
        id: clock
        enabled: scene.active
        precision: SystemClock.Minutes
    }

    function leap(d) {
        const y = d.getFullYear();
        return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
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

    Item {
        id: content
        anchors.fill: parent
        transform: Translate { x: glitch.jitter }
        opacity: scene.active ? 1 : 0
        // Fully faded content leaves the scene graph, so a covered desktop
        // costs no render passes at all.
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 400 } }

        RingStack {
            u: scene.u
            active: scene.active
            x: scene.width * (scene.ultrawide ? 0.40 : 0.42) - width / 2
            y: scene.height * 0.45 - height / 2
        }

        Telemetry {
            u: scene.u
            x: scene.frameSide + 30 * scene.u
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 140 * scene.u
        }

        // Right column, centred 230 units in from the right edge.
        Signal {
            u: scene.u
            active: scene.active
            x: scene.width - 230 * scene.u - span / 2
            y: scene.height * 0.42
        }

        Ticker {
            u: scene.u
            active: scene.active
            x: scene.frameSide + 340 * scene.u
            width: scene.width - x - scene.frameSide - 420 * scene.u
            y: scene.height - scene.frameSide - 44 * scene.u
            // Only facts the rest of the desktop does not show. Fixed-width
            // fields keep the strip length steady, so the crawl never jumps.
            text: "SYS://" + scene.user + "-HUD  ▸  LOAD " + SysStats.load
                + "  ▸  THREADS " + String(SysStats.threads).padStart(4, "0")
                + "  ▸  DISK / " + String(SysStats.diskPct).padStart(2, "0") + "% · " + Math.round(SysStats.diskFreeGb) + "G FREE"
                + "  ▸  WLAN " + (SysStats.wifiDbm < 0 ? SysStats.wifiDbm + " dBm" : "OFFLINE")
                + "  ▸  UTC " + String(clock.date.getUTCHours()).padStart(2, "0") + ":" + String(clock.date.getUTCMinutes()).padStart(2, "0")
                + "  ▸  DAY " + String(scene.dayOfYear(clock.date)).padStart(3, "0") + "/" + (scene.leap(clock.date) ? 366 : 365)
                + "  ▸  WEEK " + String(scene.isoWeek(clock.date)).padStart(2, "0")
                + "  ▸  EST. 2100  ▸  "
        }
    }

    Glitch {
        id: glitch
        anchors.fill: parent
        u: scene.u
    }
}
