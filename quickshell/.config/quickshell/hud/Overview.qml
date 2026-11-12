import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// The stack overview: the view pulls back from the desktop and stays there,
// with the window that has the focus in the middle and what lies around it
// in sight: its neighbours along the strip, and the workspaces above and
// below, in the order ALT + J/K steps through them (hyprland/bindings.lua).
// A row is a workspace drawn to scale, as live thumbnails, every window
// where Hyprland has it. `qs -c hud ipc call overview toggle` (ALT + Tab).
//
// It is a way of looking at the desktop, not a picker: it never takes the
// keyboard. The window in the middle is typed into as ever (its thumbnail is
// live), every Hyprland binding works, and the view follows the focus
// wherever they move it. A click on another window gives it the focus; a
// click on the one in the middle, or beside the windows, goes back in.
//
// It is one camera move. The world is the overview as it rests. `z` runs
// from 0 (the desktop) to 1 (the overview) and scales the world about the one point that keeps the screen
// frame of the anchor row, the workspace on show, on the screen's own edges
// at z = 0: there every thumbnail of that workspace lies exactly on its
// window, so the first frame is the desktop itself. Behind the world the
// wallpaper is drawn again, so the windows are gone from where they were and
// only the thumbnails are left of them, and it blurs and darkens as they
// recede. Leaving runs the same move backwards.
//
// A row is { id, origin, cols, tiles }: `cols` are the columns left to right,
// each { x, w, wins }, a window { top, x, y, w, h, sx, row, col, win } in
// fractions of the screen (`sx` is x from `origin`, the row's first column);
// `tiles` is every window of the row. Only workspaces with a
// window on them get a row. The thumbnails are one flat list keyed by the
// window itself (`tops`, a ScriptModel), each looking its place up in `geo`,
// so a new layout moves them instead of making them anew.
Scope {
    id: overview

    // closed -> arming (mapped, held at z = 0 until the first frames of the
    // thumbnails are in) -> open -> leaving (zooming back in) -> closed.
    property string phase: "closed"
    readonly property bool shown: phase !== "closed"
    readonly property bool live: phase === "open"
    property real z: 0
    property var targetScreen: null
    property var rows: []
    property var tops: []
    property var geo: ({})
    property int geoRev: 0
    // What `rows` was built from, to tell a new layout from the same again.
    property string laid: ""
    // The window in the middle: the one with the focus.
    property int selRow: 0
    property int selCol: 0
    property int selWin: 0
    // Off until the overview has been laid out once, so nothing glides into
    // place from where it lay the last time.
    property bool settled: false
    // The workspace the zoom starts from and ends in.
    property int anchorId: -1
    readonly property int anchor: rows.findIndex(row => row.id === anchorId)
    // Over a fullscreen window the sheet must be on the overlay layer; else
    // it lies under the bar, which stays where it is while the windows go.
    property bool overFull: false

    readonly property var monitor: targetScreen ? Hyprland.monitorFor(targetScreen) : null
    readonly property real screenW: targetScreen?.width ?? 1280
    readonly property real screenH: targetScreen?.height ?? 800
    readonly property real barH: overFull ? 0 : (monitor?.lastIpcObject?.reserved?.[1] ?? 0)

    // How far back the view goes: a screen in the overview is this much of
    // the real one. Far enough to see what is around, near enough to read
    // and type in the window in the middle. Logical px below.
    readonly property real zoomOut: 0.56
    readonly property real viewW: screenW * zoomOut
    readonly property real thumbH: screenH * zoomOut
    // From one row's screen to the next.
    readonly property real rowPitch: thumbH + 40

    readonly property var curRow: rows[selRow] ?? null
    readonly property var curWin: curRow?.cols[selCol]?.wins[selWin] ?? null

    // Where the world lies: the window in the middle is in the middle of
    // the room under the bar. All that is drawn takes its place from panX
    // and panY as they glide, never from where they are going, so the world
    // moves as one.
    readonly property real aimX: screenW / 2 - (curWin ? curWin.sx + curWin.w / 2 : 0.5) * viewW
    readonly property real aimY: (screenH + barH) / 2 - selRow * rowPitch - (curWin ? curWin.y + curWin.h / 2 : 0.5) * thumbH
    property real panX: aimX
    property real panY: aimY
    Behavior on panX {
        enabled: overview.settled
        NumberAnimation { duration: overview.glide; easing.type: Easing.OutCubic }
    }
    Behavior on panY {
        enabled: overview.settled
        NumberAnimation { duration: overview.glide; easing.type: Easing.OutCubic }
    }
    // How long a move takes. A window that only changes its size or place
    // (it is being resized, a neighbour opened) is kept up with, a step
    // behind at most; the view going over to another window travels.
    property bool quick: false
    readonly property int glide: quick ? 50 : 170
    // A row's screen frame, in the world.
    function frameY(r) {
        return panY + r * rowPitch;
    }
    // The selection's box, from its row's frame. It glides in step with the
    // world, which moves the other way: the ring stays in the middle while
    // the windows pass under it.
    property real selX: (curWin?.sx ?? 0) * viewW
    property real selY: selRow * rowPitch + (curWin?.y ?? 0) * thumbH
    property real selW: (curWin?.w ?? 1) * viewW
    property real selH: (curWin?.h ?? 1) * thumbH
    Behavior on selX { enabled: overview.settled; NumberAnimation { duration: overview.glide; easing.type: Easing.OutCubic } }
    Behavior on selY { enabled: overview.settled; NumberAnimation { duration: overview.glide; easing.type: Easing.OutCubic } }
    Behavior on selW { enabled: overview.settled; NumberAnimation { duration: overview.glide; easing.type: Easing.OutCubic } }
    Behavior on selH { enabled: overview.settled; NumberAnimation { duration: overview.glide; easing.type: Easing.OutCubic } }

    // The camera. `zoomK` is how much larger the desktop is than its row;
    // the scale runs between the two in equal ratios per step of z, which is
    // what an even pull back looks like. Without an anchor (the workspace on
    // show is empty) there is nothing to pull back from: the overview comes
    // forward a little as it fades in.
    readonly property real zoomK: 1 / zoomOut
    readonly property real camScale: anchor >= 0 ? Math.pow(zoomK, 1 - z) : 1 + 0.08 * (1 - z)
    readonly property real camX: anchor >= 0 ? (panX - rows[anchor].origin * viewW) * zoomK / (zoomK - 1) : screenW / 2
    readonly property real camY: anchor >= 0 ? frameY(anchor) * zoomK / (zoomK - 1) : screenH / 2
    // The world drawn through the camera. The thumbnails are placed with
    // these instead of being scaled with the rest: scaled up they would show
    // the few pixels of their size at rest, not the window.
    function camPx(x) {
        return camX * (1 - camScale) + x * camScale;
    }
    function camPy(y) {
        return camY * (1 - camScale) + y * camScale;
    }
    // What belongs to the overview alone (frames, labels, the ring) comes in
    // over the second half of the move, when there is room for it.
    readonly property real chrome: Math.max(0, Math.min(1, (z - 0.45) / 0.55))
    // The ground is opaque almost at once: until then the windows
    // themselves show through, under thumbnails barely smaller than they.
    readonly property real cover: Math.min(1, z * 12)
    // The corners of the windows on the desktop (decoration.rounding).
    readonly property real windowRadius: 18

    function rebuild() {
        const mon = monitor;
        if (!mon) {
            rows = [];
            tops = [];
            return;
        }
        const spaces = Hyprland.workspaces.values.filter(w => w.monitor === mon && w.id > 0).sort((a, b) => a.id - b.id);
        const out = [];
        for (const ws of spaces) {
            const tiled = [];
            const floats = [];
            for (const top of ws.toplevels.values) {
                const o = top.lastIpcObject;
                // `hidden`: a tab of a group that is not the one on show.
                if (!top.address || !o?.at || !o.size || o.hidden || o.mapped === false)
                    continue;
                const g = {
                    top: top,
                    x: (o.at[0] - mon.x) / screenW, y: (o.at[1] - mon.y) / screenH,
                    w: o.size[0] / screenW, h: o.size[1] / screenH
                };
                (o.floating ? floats : tiled).push(g);
            }
            tiled.sort((a, b) => a.x - b.x || a.y - b.y);
            const cols = [];
            for (const g of tiled) {
                const last = cols[cols.length - 1];
                if (last && Math.abs(last.x - g.x) < 0.004) {
                    last.wins.push(g);
                    last.w = Math.max(last.w, g.w);
                } else {
                    cols.push({ x: g.x, w: g.w, wins: [g] });
                }
            }
            // Floating windows lie over the tiled ones, where they are: a
            // column each, in their order from the left.
            floats.sort((a, b) => a.x - b.x);
            for (const g of floats)
                cols.push({ x: g.x, w: g.w, wins: [g] });
            // Along the row a window is placed from the first column of its
            // workspace, not from the edge of the screen: a strip that
            // scrolls under the screen, as it does whenever the focus moves
            // along it, then leaves every thumbnail where it is, and the
            // rows above and below do not shift to make up for it.
            const origin = tiled.length ? tiled[0].x : 0;
            const tiles = [];
            cols.forEach((c, ci) => c.wins.forEach((g, wi) => {
                g.sx = g.x - origin;
                g.row = out.length;
                g.col = ci;
                g.win = wi;
                tiles.push(g);
            }));
            if (tiles.length)
                out.push({ id: ws.id, origin: origin, cols: cols, tiles: tiles });
        }
        // The same layout again (Hyprland reports every window afresh on
        // each refetch): nothing to lay out.
        const sig = JSON.stringify(out.map(row => [row.id, row.tiles.map(g => [g.top.address, g.x, g.y, g.w, g.h])]));
        if (sig !== laid) {
            laid = sig;
            const places = {};
            const all = [];
            for (const row of out)
                for (const g of row.tiles) {
                    places[g.top.address] = g;
                    all.push(g.top);
                }
            // Pictures of windows that are gone.
            for (const addr of Object.keys(kept))
                if (!places[addr])
                    delete kept[addr];
            rows = out;
            geo = places;
            tops = all;
            ++geoRev;
        }
        follow();
        // The row gone back into is no more: nothing to zoom into.
        if (phase === "leaving" && anchor < 0)
            shut();
    }

    // The view is where the focus is: the window that has it in the middle,
    // its workspace the one the zoom ends in.
    function follow() {
        const mon = monitor;
        if (!mon || phase === "leaving")
            return;
        anchorId = mon.activeWorkspace?.id ?? -1;
        select(pinned || (Hyprland.activeToplevel?.address ?? ""), anchorId);
    }
    // For review (`pick`): a window held in the middle whatever has the focus.
    property string pinned: ""

    // Put the selection on a window by address, else on a workspace's row.
    function select(addr, id) {
        const before = curWin?.top?.address ?? "";
        selectAt(addr, id);
        quick = (curWin?.top?.address ?? "") === before;
    }
    function selectAt(addr, id) {
        const g = addr ? geo[addr] : null;
        if (g) {
            selRow = g.row;
            selCol = g.col;
            selWin = g.win;
            return;
        }
        const r = rows.findIndex(row => row.id === id);
        if (r < 0) {
            // An empty workspace has no row: the nearest one that has.
            let near = 0;
            rows.forEach((row, i) => {
                if (Math.abs(row.id - id) < Math.abs(rows[near].id - id))
                    near = i;
            });
            selRow = near;
            selCol = 0;
            selWin = 0;
            return;
        }
        // The window of that workspace that had the focus last.
        let best = null;
        for (const t of rows[r].tiles)
            if (!best || (t.top?.lastIpcObject?.focusHistoryID ?? 1e9) < (best.top?.lastIpcObject?.focusHistoryID ?? 1e9))
                best = t;
        selRow = r;
        selCol = best?.col ?? 0;
        selWin = best?.win ?? 0;
    }

    // Hyprland hands out no picture of a window that lies wholly off its
    // screen, which on a strip is every column out of sight. The last
    // picture taken of each window is kept (address -> ItemGrabResult) and
    // shown in its place; a window never seen yet gets its icon and title.
    property var kept: ({})
    property int keptRev: 0
    function keep(addr, grab) {
        kept[addr] = grab;
        ++keptRev;
    }

    function hypr(lua) {
        Quickshell.execDetached(["hyprctl", "eval", lua]);
    }
    // A click on a window: the focus goes to it and the view follows; on the
    // one that has it already, back in.
    function clicked(g) {
        if (!live || !g?.top?.address)
            return;
        if (g === curWin && g.top.activated)
            leave();
        else
            hypr("hl.dispatch(hl.dsp.focus({ window = 'address:0x" + g.top.address.replace(/^0x/, "") + "' }))");
    }

    function openOn(screen) {
        if (phase !== "closed")
            return;
        targetScreen = screen;
        overFull = Hyprland.monitorFor(screen)?.activeWorkspace?.hasFullscreen ?? false;
        settled = false;
        z = 0;
        laid = "";
        // The positions Quickshell holds are those of the last event; the
        // fresh ones arrive a moment later and are laid out as they do.
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        wallpaper.fetch(screen.name);
        rebuild();
        armed = 0;
        phase = "arming";
    }
    // The first frames of the thumbnails that stand in for the windows on
    // show, and the wallpaper, take a moment: until they are in the sheet is
    // mapped and stays at z = 0, where all it draws is clear, so the move
    // starts from the desktop as it is and not from blank cards. It does
    // not wait long for stragglers.
    property int armed: 0
    Timer {
        interval: 16
        repeat: true
        running: overview.phase === "arming"
        onTriggered: {
            overview.armed += interval;
            let waits = backdrop.loading;
            for (let i = 0; i < tiles.count && !waits; ++i)
                waits = tiles.itemAt(i)?.waits ?? false;
            // At least two ticks: the fresh positions are in by then.
            if (overview.armed >= 32 && (!waits || overview.armed >= 160)) {
                overview.phase = "open";
                overview.settled = true;
                zoom.go(1, 260);
            }
        }
    }
    NumberAnimation {
        id: zoom
        target: overview
        property: "z"
        easing.type: Easing.OutCubic
        function go(end, ms) {
            stop();
            from = overview.z;
            to = end;
            duration = ms;
            start();
        }
        onFinished: {
            if (overview.phase === "leaving")
                overview.shut();
        }
    }

    // Back into the workspace on show.
    function leave() {
        if (phase === "arming") {
            shut();
            return;
        }
        if (phase !== "open")
            return;
        phase = "leaving";
        zoom.go(0, 200);
    }
    function shut() {
        zoom.stop();
        relayout.stop();
        refetch.stop();
        phase = "closed";
        pinned = "";
        z = 0;
        // The rows hold the windows themselves: let go of them.
        rows = [];
        tops = [];
        geo = ({});
        laid = "";
    }
    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }

    // The wallpaper of each output, asked of Noctalia when the overview
    // opens (the last answer serves until the new one is in).
    Process {
        id: wallpaper
        property string asked: ""
        property var paths: ({})
        property int rev: 0
        function fetch(name) {
            if (running)
                return;
            asked = name;
            running = true;
        }
        command: ["noctalia", "msg", "wallpaper-get", asked]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.startsWith("/") && wallpaper.paths[wallpaper.asked] !== path) {
                    wallpaper.paths[wallpaper.asked] = path;
                    ++wallpaper.rev;
                }
            }
        }
    }

    // Laid out again whenever a window moves, opens, closes or changes
    // workspace while the overview is up, and when the focus moves: on a
    // strip that scrolls the columns.
    function dirty() {
        if (shown)
            relayout.restart();
    }
    Timer {
        id: relayout
        interval: 8
        onTriggered: {
            if (overview.shown)
                overview.rebuild();
        }
    }
    // A window that is resized says nothing of it, and neither does a strip
    // whose columns change width: while the overview is up Hyprland is asked
    // where the windows are, every few frames, so the thumbnails keep up.
    Timer {
        interval: 40
        repeat: true
        running: overview.live
        onTriggered: Hyprland.refreshToplevels()
    }
    Timer {
        id: refetch
        interval: 16
        onTriggered: {
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
        }
    }
    Instantiator {
        model: Hyprland.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { overview.dirty(); }
            function onWorkspaceChanged() { overview.dirty(); }
        }
        onObjectAdded: overview.dirty()
        onObjectRemoved: overview.dirty()
    }
    Connections {
        target: Hyprland
        enabled: overview.live
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindowv2", "changefloatingmode", "fullscreen",
                 "createworkspacev2", "destroyworkspacev2", "activewindowv2", "workspacev2"].includes(event.name))
                refetch.restart();
        }
        function onActiveToplevelChanged() { overview.follow(); }
    }
    Connections {
        target: overview.monitor
        enabled: overview.live
        function onActiveWorkspaceChanged() { overview.follow(); }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void {
            if (overview.shown)
                overview.leave();
            else
                overview.openOn(overview.focusedScreen());
        }
        function close(): void { overview.leave(); }
        // For review: show it on an output by connector name, stop the move
        // at a point of it (0 the desktop, 1 the overview), and put a window
        // in the middle by address without giving it the focus.
        function peek(output: string): void {
            const screen = Quickshell.screens.find(s => s.name === output);
            if (!screen) {
                console.warn("hud: overview peek: no output named", output);
                return;
            }
            overview.openOn(screen);
        }
        function hold(at: real): void {
            zoom.stop();
            overview.z = at;
        }
        function pick(address: string): void {
            overview.pinned = address.replace(/^0x/, "");
            overview.follow();
        }
        function state(): string {
            const g = overview.curWin;
            return overview.phase + " z " + overview.z.toFixed(2) + " armed " + overview.armed + " row " + overview.selRow
                + "/" + overview.rows.length + " ws " + (overview.curRow?.id ?? "-") + " col " + overview.selCol
                + " win " + overview.selWin + " " + (g?.top?.title ?? "(none)");
        }
    }

    PanelWindow {
        id: win
        screen: overview.targetScreen ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: overview.shown

        WlrLayershell.layer: overview.overFull ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.namespace: "hud-overview"
        // Never the keyboard: it stays with the window in the middle.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // The compositor took the surface away (its output was unplugged).
        onClosed: overview.shut()

        Item {
            id: box
            anchors.fill: parent

            // The wallpaper again, over the desktop: the windows are gone
            // from where they were. Sharp and bright at first, as it is on
            // the desktop, then out of focus and dark, the ground the
            // thumbnails stand out from. Without a wallpaper to read, the
            // theme's ground colour.
            Item {
                id: backdrop
                anchors.fill: parent
                opacity: overview.cover
                readonly property string path: {
                    wallpaper.rev;
                    return wallpaper.paths[overview.targetScreen?.name ?? ""] ?? "";
                }
                readonly property bool loading: path !== "" && picture.status === Image.Loading

                Rectangle {
                    anchors.fill: parent
                    color: Theme.surface
                }
                Image {
                    id: picture
                    anchors.fill: parent
                    source: backdrop.path ? "file://" + backdrop.path : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Math.ceil(win.width * win.devicePixelRatio)
                    sourceSize.height: Math.ceil(win.height * win.devicePixelRatio)
                }
                MultiEffect {
                    anchors.fill: parent
                    source: picture
                    visible: picture.status === Image.Ready
                    opacity: overview.z
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                    autoPaddingEnabled: false
                }
                Rectangle {
                    anchors.fill: parent
                    color: Theme.surface
                    opacity: 0.62 * overview.z
                }
            }

            // A click beside the windows goes back in.
            MouseArea {
                anchors.fill: parent
                enabled: overview.live
                onClicked: overview.leave()
            }

            // The windows.
            Repeater {
                id: tiles
                model: ScriptModel { values: overview.tops }

                Item {
                    id: tile
                    required property var modelData
                    readonly property var g: {
                        overview.geoRev;
                        return overview.geo[modelData?.address ?? ""] ?? null;
                    }
                    readonly property int rowAt: g?.row ?? 0
                    readonly property bool current: !!g && rowAt === overview.selRow && g.col === overview.selCol && g.win === overview.selWin
                    // A capture that was asked for too early (a window that
                    // has only just opened) or that broke off (some windows
                    // on a resize) never starts again by itself: while there
                    // is no picture it is asked for anew, less and less often
                    // for a window that has none to give (out of sight).
                    property int tries: 0
                    property bool asking: true
                    readonly property var toplevel: {
                        tries;
                        return modelData?.wayland ?? null;
                    }
                    Timer {
                        interval: Math.min(2400, 80 * Math.pow(2, tile.tries))
                        repeat: true
                        running: overview.shown && !!tile.g && !shot.hasContent
                        onTriggered: {
                            tile.asking = false;
                            again.restart();
                        }
                    }
                    Timer {
                        id: again
                        interval: 40
                        onTriggered: {
                            ++tile.tries;
                            tile.asking = true;
                        }
                    }
                    readonly property string icon: Quickshell.iconPath(DesktopEntries.heuristicLookup(toplevel?.appId ?? "")?.icon
                        ?? toplevel?.appId ?? "", "application-x-executable")
                    // On the screen of the workspace the move starts from:
                    // its first frame is waited for.
                    readonly property bool waits: !!g && rowAt === overview.anchor && g.x < 1 && g.x + g.w > 0
                        && !!toplevel && !shot.hasContent
                    visible: !!g
                    // Its place in its row: this is what glides when the
                    // layout changes; the world and the camera come on top.
                    property real lx: (g?.sx ?? 0) * overview.viewW
                    property real ly: (g?.y ?? 0) * overview.thumbH
                    property real lw: Math.max(8, (g?.w ?? 0) * overview.viewW)
                    property real lh: Math.max(8, (g?.h ?? 0) * overview.thumbH)
                    Behavior on lx { enabled: overview.settled; NumberAnimation { duration: 50; easing.type: Easing.OutCubic } }
                    Behavior on ly { enabled: overview.settled; NumberAnimation { duration: 50; easing.type: Easing.OutCubic } }
                    Behavior on lw { enabled: overview.settled; NumberAnimation { duration: 50; easing.type: Easing.OutCubic } }
                    Behavior on lh { enabled: overview.settled; NumberAnimation { duration: 50; easing.type: Easing.OutCubic } }
                    x: overview.camPx(overview.panX + lx)
                    y: overview.camPy(overview.frameY(rowAt) + ly)
                    width: lw * overview.camScale
                    height: lh * overview.camScale

                    // A soft shadow under each window, the depth between
                    // it and the ground; none on the desktop.
                    Rectangle {
                        anchors { fill: parent; leftMargin: -6; rightMargin: -6; topMargin: -3; bottomMargin: -10 }
                        radius: clipped.radius + 6
                        color: "transparent"
                        border.width: 6
                        border.color: Qt.rgba(0, 0, 0, (tile.current ? 0.22 : 0.14) * overview.z)
                        antialiasing: true
                    }
                    ClippingRectangle {
                        id: clipped
                        anchors.fill: parent
                        // The windows' own corners on the desktop, in
                        // proportion at rest.
                        radius: overview.windowRadius * (1 + (overview.zoomOut - 1) * overview.z)
                        // The windows are glass: on the desktop the wallpaper
                        // shows through them, here the ground of the overview.
                        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72 * overview.cover)

                        ScreencopyView {
                            id: shot
                            anchors.fill: parent
                            captureSource: overview.shown && tile.asking ? tile.toplevel : null
                            live: true
                            // A picture again: the next loss is asked after
                            // as promptly as the first.
                            onHasContentChanged: {
                                if (hasContent)
                                    tile.tries = 0;
                            }
                        }
                        Timer {
                            interval: 500
                            repeat: true
                            running: overview.live && shot.hasContent
                            onRunningChanged: interval = 500
                            onTriggered: {
                                interval = 2500;
                                const addr = tile.modelData?.address;
                                if (addr)
                                    shot.grabToImage(grab => overview.keep(addr, grab));
                            }
                        }
                        // Out of sight: the last picture of it.
                        Image {
                            id: last
                            anchors.fill: parent
                            readonly property var grab: {
                                overview.keptRev;
                                return overview.kept[tile.modelData?.address ?? ""] ?? null;
                            }
                            visible: !shot.hasContent && !!grab
                            source: visible ? grab.url : ""
                            cache: false
                            // Taken at another size, perhaps: cut, not stretched.
                            fillMode: Image.PreserveAspectCrop
                            horizontalAlignment: Image.AlignLeft
                            verticalAlignment: Image.AlignTop
                        }
                        // Never seen: a card with its icon and title.
                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            spacing: 8
                            visible: !shot.hasContent && !last.visible
                            // Not on the desktop: there the window itself is.
                            opacity: overview.cover
                            IconImage {
                                anchors.horizontalCenter: parent.horizontalCenter
                                implicitSize: Math.max(16, Math.min(56, Math.round(tile.height * 0.2)))
                                source: tile.icon
                            }
                            Text {
                                width: parent.width
                                visible: tile.height >= 64 && tile.width >= 56
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: tile.modelData?.title ?? ""
                                color: Theme.fgDim
                                renderType: Text.CurveRendering
                                font.family: Theme.displayFont
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                        }
                        // The others sit back, as unfocused windows do on
                        // the desktop.
                        Rectangle {
                            anchors.fill: parent
                            color: Theme.surface
                            opacity: (tile.current ? 0 : hover.containsMouse ? 0.1 : 0.34) * overview.chrome
                        }
                    }
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        enabled: overview.live
                        hoverEnabled: true
                        onClicked: overview.clicked(tile.g)
                    }
                }
            }

            // What lies over the windows, scaled as the world is.
            Item {
                id: over
                width: parent.width
                height: parent.height
                transformOrigin: Item.TopLeft
                scale: overview.camScale
                x: overview.camX * (1 - overview.camScale)
                y: overview.camY * (1 - overview.camScale)
                opacity: (overview.anchor >= 0 ? 1 : overview.z) * overview.chrome

                // Each row's workspace, at the corner of its screen. The
                // windows themselves show where a row is: no frame around it.
                Repeater {
                    model: overview.rows
                    Text {
                        required property var modelData
                        required property int index
                        x: overview.panX
                        y: overview.frameY(index) - height - 4
                        text: String(modelData.id).padStart(2, "0")
                        color: index === overview.selRow ? Theme.primary : Theme.fgDim
                        renderType: Text.CurveRendering
                        font.family: Theme.monoFont
                        font.pixelSize: 12
                        font.letterSpacing: 1
                    }
                }

                // The window that has the focus: one ring, in the middle,
                // that the windows pass under.
                Item {
                    x: overview.panX + overview.selX
                    y: overview.panY + overview.selY
                    width: overview.selW
                    height: overview.selH
                    visible: !!overview.curWin

                    Rectangle {
                        anchors { fill: parent; margins: -7 }
                        radius: 17
                        color: "transparent"
                        border.width: 4
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        antialiasing: true
                    }
                    Rectangle {
                        anchors { fill: parent; margins: -3 }
                        radius: 13
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.primary
                        antialiasing: true
                    }
                }
            }

            // Nothing to show.
            Text {
                anchors.centerIn: parent
                visible: overview.rows.length === 0
                opacity: overview.chrome
                text: "No windows on this monitor"
                color: Theme.fgDim
                renderType: Text.CurveRendering
                font.family: Theme.displayFont
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
        }
    }
}
