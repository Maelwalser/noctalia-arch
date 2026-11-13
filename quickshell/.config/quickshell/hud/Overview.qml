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
// click beside the windows goes back in. A click on the window in the middle
// does nothing: a second click on a window just picked must not close the
// view.
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
//
// The zoom and the travel from window to window are stepped against the
// wall clock (`tick`), not by Qt's animations: their clock is advanced once
// per frame by every window the HUD has on show, so with three of them a
// 170 ms glide was over in three frames, a jump, and how fast it ran
// depended on what else was up.
Scope {
    id: overview

    // closed -> arming (mapped, held at z = 0 until the first frames of the
    // thumbnails are in) -> open -> leaving (zooming back in) -> keeping
    // (back on the desktop, drawing nothing: a still of every window is put
    // by for the next time) -> closed.
    property string phase: "closed"
    readonly property bool shown: phase !== "closed"
    readonly property bool live: phase === "open"
    readonly property bool going: phase === "leaving" || phase === "keeping"
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
    // The selection's box, from its row's frame. It glides in step with the
    // world, which moves the other way: the ring stays in the middle while
    // the windows pass under it.
    readonly property real boxX: (curWin?.sx ?? 0) * viewW
    readonly property real boxY: selRow * rowPitch + (curWin?.y ?? 0) * thumbH
    readonly property real boxW: (curWin?.w ?? 1) * viewW
    readonly property real boxH: (curWin?.h ?? 1) * thumbH
    property real panX: 0
    property real panY: 0
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0
    // A row's screen frame, in the world.
    function frameY(r) {
        return panY + r * rowPitch;
    }

    // The glide: one critically damped spring takes the world and the ring
    // to where they belong. It starts from rest and keeps its speed when the
    // aim changes under way, so a held ALT + L is one continuous pan, not a
    // row of restarts, and it never overshoots. Going over to another window
    // travels (settled in about 200 ms); a window that only changes its size
    // or place (it is being resized, a neighbour opened) is kept up with.
    readonly property var aims: [aimX, aimY, boxX, boxY, boxW, boxH]
    onAimsChanged: {
        if (settled)
            gliding = true;
        else
            rest();
    }
    property var speeds: [0, 0, 0, 0, 0, 0]
    property bool gliding: false
    property bool travel: false
    readonly property real travelRate: 40 // 1/s: the spring's natural frequency
    readonly property real keepUpRate: 110
    // The window the selection left, and how far the light has gone over
    // from it to the new one (0..1).
    property string faded: ""
    property real fade: 1
    function rest() {
        panX = aimX;
        panY = aimY;
        selX = boxX;
        selY = boxY;
        selW = boxW;
        selH = boxH;
        speeds = [0, 0, 0, 0, 0, 0];
        gliding = false;
        travel = false;
        fade = 1;
    }
    function glide(dt) {
        const to = aims;
        const at = [panX, panY, selX, selY, selW, selH];
        const w = travel ? travelRate : keepUpRate;
        const e = Math.exp(-w * dt);
        let done = true;
        for (let i = 0; i < 6; ++i) {
            const d = at[i] - to[i];
            const c = speeds[i] + w * d;
            const nd = (d + c * dt) * e;
            const nv = (speeds[i] - w * c * dt) * e;
            // The last half pixel is not crawled over.
            if (Math.abs(nd) < 0.4 && Math.abs(nv) < 24) {
                at[i] = to[i];
                speeds[i] = 0;
            } else {
                at[i] = to[i] + nd;
                speeds[i] = nv;
                done = false;
            }
        }
        panX = at[0];
        panY = at[1];
        selX = at[2];
        selY = at[3];
        selW = at[4];
        selH = at[5];
        if (done) {
            gliding = false;
            travel = false;
        }
    }

    // The zoom: z from where it is to `end`, eased out over `ms`.
    property bool zooming: false
    property real zFrom: 0
    property real zTo: 0
    property real zLen: 0.2
    property real zAt: 0
    function zoomTo(end, ms) {
        zFrom = z;
        zTo = end;
        zLen = ms / 1000;
        zAt = 0;
        zooming = true;
    }
    function tick(dt) {
        if (zooming) {
            zAt += dt;
            const p = Math.min(1, zAt / zLen);
            z = zFrom + (zTo - zFrom) * (1 - Math.pow(1 - p, 3));
            if (p >= 1) {
                zooming = false;
                if (phase === "leaving")
                    keepPictures();
            }
        }
        if (gliding)
            glide(dt);
        if (fade < 1)
            fade = Math.min(1, fade + dt / 0.16);
    }
    FrameAnimation {
        running: overview.shown && (overview.zooming || overview.gliding || overview.fade < 1)
        // A frame that took long is made up for, but not a stall.
        onTriggered: overview.tick(Math.min(0.1, frameTime))
    }

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
        if (going && anchor < 0)
            shut();
    }

    // The view is where the focus is: the window that has it in the middle,
    // its workspace the one the zoom ends in.
    function follow() {
        const mon = monitor;
        if (!mon || going)
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
        if ((curWin?.top?.address ?? "") === before)
            return;
        travel = true;
        // Also when the new window lies just where the old one did: the
        // glide is what ends the travel.
        gliding = settled;
        if (settled) {
            faded = before;
            fade = 0;
        }
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
    // screen, which on a strip is every column out of sight. A thumbnail
    // holds on to the last frame it was given; for the next time the
    // overview opens a still of each is kept (address -> ItemGrabResult), and
    // a window never seen yet gets its icon and title. The stills are taken
    // on the way out, back on the desktop with nothing of the overview left
    // to see: reading a picture back stalls the HUD for a few frames, which
    // while the overview was up showed as a hitch every time.
    property var kept: ({})
    property int keptRev: 0
    property int keeping: 0
    function keep(addr, grab) {
        kept[addr] = grab;
        ++keptRev;
        if (phase === "keeping" && --keeping <= 0)
            shut();
    }
    function keepPictures() {
        phase = "keeping";
        keeping = 0;
        for (let i = 0; i < tiles.count; ++i)
            if (tiles.itemAt(i)?.keepPicture())
                ++keeping;
        if (keeping === 0)
            shut();
        else
            keepWait.restart();
    }
    // Neither the stills nor the move back in may hold the sheet up: the
    // move is stepped by frames, and an output that stops giving them (it
    // was turned off) would leave it lying over the desktop.
    Timer {
        id: keepWait
        interval: 300
        onTriggered: {
            if (overview.phase === "keeping")
                overview.shut();
        }
    }
    Timer {
        interval: 800
        running: overview.phase === "leaving"
        onTriggered: overview.shut()
    }

    function hypr(lua) {
        Quickshell.execDetached(["hyprctl", "eval", lua]);
    }
    // A click on a window: the focus goes to it and the view follows. On the
    // one that has it already nothing happens, so a double click does not
    // zoom back in.
    function clicked(g) {
        if (!live || !g?.top?.address)
            return;
        if (g !== curWin || !g.top.activated)
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
                overview.zoomTo(1, 200);
            }
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
        zoomTo(0, 160);
    }
    function shut() {
        zooming = false;
        gliding = false;
        keepWait.stop();
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
            // Asked for again while the last stills are being put by.
            if (overview.phase === "keeping")
                overview.shut();
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
            overview.zooming = false;
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
        // Nor the pointer while the stills are taken: the desktop is back.
        mask: overview.phase === "keeping" ? nothing : null
        Region { id: nothing }
        // The compositor took the surface away (its output was unplugged).
        onClosed: overview.shut()

        Item {
            id: box
            anchors.fill: parent
            opacity: overview.phase === "keeping" ? 0 : 1

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
                    // A capture breaks off whenever its window changes
                    // size (every frame of a maximize, as long as Hyprland
                    // animates it) and one asked for too early (a window
                    // that has only just opened) never comes; neither starts
                    // again by itself. While there is no picture it is asked
                    // for anew: at once and often for a window that has just
                    // lost its own, so it is back as soon as the window has
                    // come to rest, less and less often for one that has
                    // none to give (out of sight). Not faster than every
                    // third frame: an answer under way would be thrown out.
                    property int tries: 0
                    property int fast: 0
                    property bool asking: true
                    readonly property var toplevel: {
                        tries;
                        return modelData?.wayland ?? null;
                    }
                    Timer {
                        interval: tile.fast > 0 ? 48 : Math.min(2400, 80 * Math.pow(2, tile.tries))
                        repeat: true
                        running: overview.shown && !!tile.g && !shot.hasContent
                        onTriggered: {
                            if (tile.fast > 0)
                                --tile.fast;
                            else
                                ++tile.tries;
                            tile.asking = false;
                            tile.asking = true;
                        }
                    }
                    // The last frame the capture gave: its size in pixels
                    // of the screen, and that there has been one.
                    property size frame: Qt.size(0, 0)
                    property bool seen: false
                    function framed() {
                        if (shot.hasContent && shot.sourceSize.width > 0 && shot.sourceSize.height > 0) {
                            frame = shot.sourceSize;
                            seen = true;
                        }
                    }
                    // A still of it for the next time, at its size at rest.
                    function keepPicture() {
                        const addr = modelData?.address;
                        if (!addr || !seen || still.width < 1 || still.height < 1)
                            return false;
                        const k = win.devicePixelRatio / overview.camScale;
                        return still.grabToImage(grab => overview.keep(addr, grab),
                            Qt.size(Math.ceil(still.width * k), Math.ceil(still.height * k)));
                    }
                    // The light on the window in the middle: it goes over
                    // from the one the selection left as the view travels.
                    readonly property real lit: current ? overview.fade
                        : (modelData?.address ?? "-") === overview.faded ? 1 - overview.fade : 0
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
                        border.color: Qt.rgba(0, 0, 0, (0.14 + 0.08 * tile.lit) * overview.z)
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
                            onSourceSizeChanged: tile.framed()
                            onHasContentChanged: {
                                // A picture again: the next loss is asked
                                // after as promptly as the first.
                                if (hasContent) {
                                    tile.tries = 0;
                                    tile.fast = 0;
                                } else if (tile.seen && overview.shown) {
                                    tile.fast = 12;
                                }
                                tile.framed();
                            }
                        }
                        // What is drawn of the capture: its frames as they
                        // come, and the last of them for as long as there is
                        // none (the window is being resized, or has gone out
                        // of sight). That one is not stretched over a window
                        // that has changed its size since: it stays the size
                        // it was taken at, from the window's top left corner,
                        // and the window grows or shrinks around it.
                        ShaderEffectSource {
                            id: still
                            sourceItem: shot
                            hideSource: true
                            live: shot.hasContent
                            visible: tile.seen
                            textureSize: tile.frame
                            anchors { left: parent.left; top: parent.top }
                            readonly property real perPixel: overview.zoomOut * overview.camScale / (overview.monitor?.scale ?? 1)
                            width: shot.hasContent ? parent.width : tile.frame.width * perPixel
                            height: shot.hasContent ? parent.height : tile.frame.height * perPixel
                        }
                        // Not captured since the overview opened (it is out
                        // of sight): the still kept of it the last time.
                        Image {
                            id: last
                            anchors.fill: parent
                            readonly property var grab: {
                                overview.keptRev;
                                return overview.kept[tile.modelData?.address ?? ""] ?? null;
                            }
                            visible: !tile.seen && !!grab
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
                            visible: !tile.seen && !last.visible
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
                            opacity: (hover.containsMouse ? 0.1 : 0.34) * (1 - tile.lit) * overview.chrome
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
