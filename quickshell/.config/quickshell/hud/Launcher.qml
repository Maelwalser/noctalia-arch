import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// The app launcher: one glass pill in the upper third of the focused output
// that grows a short results list as you type, the selected row a lens laid
// on the glass like the bar's capsules. `qs -c hud ipc call launcher toggle`
// (Alt+Space, hyprland/bindings.lua).
//
// Two windows, as for the desktop panes: hud-launcher-glass holds only the
// shapes hyprglass turns into glass (hyprland/plugins.lua; the lens is a
// nested shape), hud-launcher the text and icons above it, and the keyboard.
//
// A plain query finds applications. One that starts with "/" is a mode:
// /calc (qalc; Enter copies the result), /emo (Enter copies the emoji),
// /win (Enter focuses the window) and /session. "/" alone lists them.
//
// A result is { title, markup, note, icon | glyph, run, keep }: `run` is what
// Enter does, `keep` leaves the launcher open afterwards.
Scope {
    id: launcher

    property bool shown: false
    // Review on a named output (`peek`): shown without taking the keyboard.
    property bool peeking: false
    property var targetScreen: null
    property string query: ""
    property var results: []
    property int selected: 0
    // The first result on show: the list scrolls under a window of maxRows.
    property int first: 0
    readonly property var rows: results.slice(first, first + maxRows)

    // Logical px, in step with the bar and the toasts (radius 18, capsules 12).
    readonly property int pillW: 560
    readonly property int pillH: 48
    readonly property int rowH: 40
    readonly property int maxRows: 7
    // The lens keeps clear of the body's bent edge (12 px, acid_clear) on
    // three sides, and its corners (12) run parallel to the body's (24).
    readonly property int listPad: 12
    readonly property real listH: rows.length ? rows.length * rowH + listPad : 0
    property real bodyH: pillH + listH
    Behavior on bodyH { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // On whole device pixels, or a fractional scale smears the edge over two.
    function bodyRect(w, h, dpr) {
        const snap = v => Math.round(v * dpr) / dpr;
        return Qt.rect(snap((w - pillW) / 2), snap(h * 0.26), pillW, bodyH);
    }

    onQueryChanged: refresh()
    function refresh() {
        // A throw must not leave the last query's rows under Enter.
        try {
            results = items(query);
        } catch (e) {
            console.warn("hud: launcher:", e);
            results = [];
        }
        selected = 0;
        first = 0;
    }

    // The entries are read in the background: a search made before they are
    // in (the first one after the HUD starts) is run again when they arrive.
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            // Only then: a refresh under a list the user is already
            // moving through would put the selection back on the first row.
            if (launcher.shown && !launcher.results.length)
                launcher.refresh();
        }
    }

    function openOn(screen) {
        targetScreen = screen;
        query = "";
        refresh();
        shown = true;
    }
    function close() {
        shown = false;
        peeking = false;
    }
    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }
    function move(step) {
        if (!results.length)
            return;
        selected = (selected + step + results.length) % results.length;
        if (selected < first)
            first = selected;
        else if (selected >= first + maxRows)
            first = selected - maxRows + 1;
    }
    function activate(item) {
        if (!item)
            return;
        // Closed first: whatever `run` does, the keyboard is given back.
        if (!item.keep)
            close();
        item.run();
    }
    function copy(text) {
        Quickshell.execDetached(["wl-copy", "--", text]);
    }

    // Launch counts, so the apps you use rise to the top of a tie.
    property var usage: ({})
    FileView {
        id: usageFile
        path: Quickshell.env("HOME") + "/.local/state/hud/launcher.json"
        printErrors: false
        onLoaded: {
            try {
                launcher.usage = JSON.parse(text());
            } catch (e) {
                console.warn("hud: ignoring malformed launcher.json:", e);
            }
        }
    }

    function launch(entry) {
        const counts = Object.assign({}, usage);
        counts[entry.id] = (counts[entry.id] ?? 0) + 1;
        usage = counts;
        usageFile.setText(JSON.stringify(counts));
        if (entry.runInTerminal)
            Quickshell.execDetached({
                command: ["ghostty", "-e"].concat(entry.command),
                workingDirectory: entry.workingDirectory
            });
        else
            entry.execute();
    }

    // Where `q` sits in `text`: the start scores highest, then the start of a
    // word, then anywhere, then its letters in order (names only).
    function matchScore(text, q, loose) {
        const at = text.indexOf(q);
        if (at === 0)
            return 100;
        if (at > 0)
            return /[\s\-_.]/.test(text[at - 1]) ? 80 : 60;
        if (!loose)
            return 0;
        let i = 0;
        for (const ch of text) {
            if (ch === q[i] && ++i === q.length)
                return 30;
        }
        return 0;
    }

    function items(text) {
        if (!text.startsWith("/"))
            return apps(text.trim().toLowerCase());
        const sp = text.indexOf(" ");
        if (sp < 0)
            return modes.filter(m => m.key.startsWith(text.slice(1).toLowerCase())).map(m => ({
                title: "/" + m.key, markup: marked("/" + m.key, text), note: m.label, icon: m.icon,
                run: () => { launcher.query = "/" + m.key + " "; }, keep: true
            }));
        const arg = text.slice(sp + 1).trim();
        switch (text.slice(1, sp).toLowerCase()) {
        case "calc": return calcItems(arg);
        case "emo": return emojiItems(arg.toLowerCase());
        case "win": return windowItems(arg.toLowerCase());
        case "session": return sessionItems(arg.toLowerCase());
        }
        return [];
    }

    readonly property var modes: [
        { key: "calc", label: "CALCULATOR", icon: "accessories-calculator" },
        { key: "emo", label: "EMOJI", icon: "preferences-desktop-emoticons" },
        { key: "win", label: "WINDOWS", icon: "preferences-system-windows" },
        { key: "session", label: "SESSION", icon: "system-shutdown" }
    ]

    function apps(q) {
        if (!q)
            return [];
        const found = [];
        for (const entry of DesktopEntries.applications.values) {
            if (entry.noDisplay)
                continue;
            let score = matchScore(entry.name.toLowerCase(), q, true);
            if (!score) {
                const extra = [entry.genericName].concat(entry.keywords).join(" ").toLowerCase();
                score = matchScore(extra, q, false) / 2;
            }
            if (score)
                found.push({ entry: entry, score: score + Math.min(usage[entry.id] ?? 0, 20) * 2 });
        }
        found.sort((a, b) => b.score - a.score || a.entry.name.length - b.entry.name.length
            || a.entry.name.localeCompare(b.entry.name));
        return found.slice(0, 50).map(f => ({
            title: f.entry.name, markup: marked(f.entry.name, q), note: f.entry.genericName.toUpperCase(),
            icon: f.entry.icon, run: () => launcher.launch(f.entry)
        }));
    }

    // /calc: qalc works the expression out; the answer arrives a moment
    // after the keystroke and replaces the row. One run at a time, each
    // left to finish: `started` is what the output on its way belongs to.
    property string calcFor: ""
    property string calcAnswer: ""
    function calcExpr() {
        const m = /^\/calc\s(.*)$/i.exec(query);
        return m ? m[1].trim() : "";
    }
    function calcRun() {
        const expr = calcExpr();
        if (!shown || qalc.running || !expr || expr === calcFor)
            return;
        qalc.started = expr;
        qalc.killed = false;
        qalc.running = true;
    }
    Process {
        id: qalc
        property string started: ""
        property bool killed: false
        command: ["qalc", "-t", "--", started]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!qalc.killed) {
                    launcher.calcFor = qalc.started;
                    launcher.calcAnswer = text.trim().split("\n").pop();
                    if (launcher.shown && launcher.calcExpr())
                        launcher.refresh();
                }
                // What was typed while it ran.
                Qt.callLater(launcher.calcRun);
            }
        }
    }
    Timer {
        id: calcDelay
        interval: 120
        onTriggered: launcher.calcRun()
    }
    // A run that hangs (an exchange-rate fetch with no network) is ended.
    Timer {
        interval: 5000
        running: qalc.running
        onTriggered: {
            qalc.killed = true;
            qalc.running = false;
        }
    }
    function calcItems(expr) {
        if (!expr)
            return [];
        // Until the answer is in, the last one stays (the list would blink
        // shut on every key otherwise), but Enter does not copy it.
        const stale = expr !== calcFor;
        if (stale)
            calcDelay.restart();
        const answer = calcAnswer;
        if (!answer)
            return [];
        return [{ title: answer, markup: esc(answer), note: stale ? "" : "COPY", icon: "accessories-calculator",
                  run: () => { if (!stale) launcher.copy(answer); }, keep: stale }];
    }

    // /emo: Noctalia's emoji table.
    property var emoji: []
    FileView {
        path: "/usr/share/noctalia/assets/emoji.json"
        printErrors: false
        onLoaded: {
            try {
                launcher.emoji = JSON.parse(text());
            } catch (e) {
                console.warn("hud: launcher: unreadable emoji.json:", e);
            }
        }
    }
    function emojiItems(q) {
        const found = [];
        for (const e of emoji) {
            const score = q ? Math.max(matchScore(e.name.toLowerCase(), q, false),
                                       e.keywords.some(k => k.startsWith(q)) ? 50 : 0) : 1;
            if (score)
                found.push({ e: e, score: score });
        }
        found.sort((a, b) => b.score - a.score);
        return found.slice(0, 60).map(f => ({
            title: f.e.name, markup: marked(f.e.name, q), note: f.e.category.toUpperCase(),
            glyph: f.e.emoji, run: () => launcher.copy(f.e.emoji)
        }));
    }

    // /win: the open windows.
    function windowItems(q) {
        const found = [];
        for (const w of ToplevelManager.toplevels.values) {
            if (q && !(w.title + " " + w.appId).toLowerCase().includes(q))
                continue;
            const entry = DesktopEntries.heuristicLookup(w.appId);
            found.push({
                title: w.title, markup: marked(w.title, q), note: (entry?.name ?? w.appId).toUpperCase(),
                icon: entry?.icon ?? w.appId, run: () => w.activate()
            });
        }
        return found;
    }

    // /session. Lock comes first, so a bare Enter does nothing drastic.
    readonly property var sessionActions: [
        { title: "Lock", icon: "system-lock-screen", command: [Theme.home + "/.local/bin/hud-lock"] },
        { title: "Suspend", icon: "system-suspend", command: ["noctalia", "msg", "session", "suspend"] },
        { title: "Log out", icon: "system-log-out", command: ["noctalia", "msg", "session", "logout"] },
        { title: "Reboot", icon: "system-reboot", command: ["noctalia", "msg", "session", "reboot"] },
        { title: "Shut down", icon: "system-shutdown", command: ["noctalia", "msg", "session", "shutdown"] }
    ]
    function sessionItems(q) {
        return sessionActions.filter(a => a.title.toLowerCase().includes(q)).map(a => ({
            title: a.title, markup: marked(a.title, q), note: "", icon: a.icon,
            run: () => Quickshell.execDetached(a.command)
        }));
    }

    function esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
    }
    // `text` with the first run of `q` in the highlight colour.
    function marked(text, q) {
        const low = text.toLowerCase();
        // (A few letters change length in lower case; the index would be off.)
        const at = q && low.length === text.length ? low.indexOf(q.toLowerCase()) : -1;
        if (at < 0)
            return esc(text);
        return esc(text.slice(0, at)) + "<font color=\"" + Theme.accent + "\">"
            + esc(text.slice(at, at + q.length)) + "</font>" + esc(text.slice(at + q.length));
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (launcher.shown)
                launcher.close();
            else
                launcher.openOn(launcher.focusedScreen());
        }
        function close(): void { launcher.close(); }
        // For review: show it on an output by connector name with a query
        // typed in, without taking the keyboard. `close` ends it.
        function peek(output: string, query: string): void {
            const screen = Quickshell.screens.find(s => s.name === output);
            if (!screen) {
                console.warn("hud: launcher peek: no output named", output);
                return;
            }
            launcher.peeking = true;
            launcher.openOn(screen);
            launcher.query = query;
        }
    }

    // The glass: the body and, on it, the lens under the selected row. Only
    // flat fills: hyprglass traces this layer's alpha, and anything else on
    // it (the edge light, say) is traced as a second rim.
    PanelWindow {
        id: glassWin
        screen: launcher.targetScreen ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        visible: launcher.shown

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hud-launcher-glass"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: body
            readonly property rect box: launcher.bodyRect(glassWin.width, glassWin.height, glassWin.devicePixelRatio)
            x: box.x
            y: box.y
            width: box.width
            height: box.height
            radius: launcher.pillH / 2
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.1)
            antialiasing: true

            Rectangle {
                x: launcher.listPad
                y: launcher.pillH + (launcher.selected - launcher.first) * launcher.rowH
                width: parent.width - 2 * launcher.listPad
                height: launcher.rowH
                radius: body.radius - launcher.listPad
                color: Qt.rgba(1, 1, 1, 0.12)
                antialiasing: true
                visible: launcher.results.length > 0
                Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
        }
    }

    PanelWindow {
        id: win
        screen: launcher.targetScreen ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: launcher.shown

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hud-launcher"
        WlrLayershell.keyboardFocus: launcher.peeking ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
        // The compositor took the surface away (its output was unplugged):
        // without this the first Alt+Space afterwards would only "close" it.
        onClosed: launcher.close()

        // Escape closes it whatever has the focus: this window holds the
        // keyboard exclusively, so there must always be a way out.
        Shortcut {
            sequences: ["Escape"]
            onActivated: launcher.close()
        }

        // A click anywhere else puts it away.
        MouseArea {
            anchors.fill: parent
            onClicked: launcher.close()
        }

        Item {
            id: box
            readonly property rect at: launcher.bodyRect(win.width, win.height, win.devicePixelRatio)
            property real hoverX: -1
            property real hoverY: -1
            x: at.x
            y: at.y
            width: at.width
            height: at.height
            clip: true

            MouseArea { anchors.fill: parent }

            // The edge: one even hairline of a device pixel all round, so
            // the sides are as crisp as the lit top, and the panes' light.
            Rectangle {
                anchors.fill: parent
                radius: launcher.pillH / 2
                color: "transparent"
                border.width: 1 / win.devicePixelRatio
                border.color: Qt.rgba(0.86, 0.9, 0.94, 0.16)
                antialiasing: true
            }
            PaneLight { anchors.fill: parent; radius: launcher.pillH / 2 }

            Item {
                id: pill
                width: parent.width
                height: launcher.pillH

                Image {
                    id: emblem
                    // Centred over the icons' column; the query then starts
                    // where the names do.
                    x: launcher.listPad + 10 + (22 - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    fillMode: Image.PreserveAspectFit
                    sourceSize.height: 64
                    source: "file://" + Theme.home + "/.local/share/hud/bar/emblem.png?v=" + Theme.version
                }

                TextInput {
                    id: input
                    anchors { left: parent.left; leftMargin: launcher.listPad + 44; right: count.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    clip: true
                    focus: true
                    color: Theme.fg
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.surface
                    renderType: Text.CurveRendering
                    font.family: Theme.displayFont
                    font.pixelSize: 17
                    font.weight: Font.Medium
                    cursorDelegate: Rectangle {
                        width: 2
                        color: Theme.primary
                        visible: input.cursorVisible
                    }
                    onTextEdited: launcher.query = text
                    Connections {
                        target: launcher
                        function onShownChanged() {
                            if (launcher.shown) {
                                input.text = "";
                                input.forceActiveFocus();
                            }
                        }
                        // `peek` types the query from outside.
                        function onQueryChanged() {
                            if (input.text !== launcher.query)
                                input.text = launcher.query;
                        }
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Escape) {
                            launcher.close();
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            launcher.activate(launcher.results[launcher.selected]);
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab
                                   || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
                            launcher.move(1);
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab
                                   || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
                            launcher.move(-1);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }

                    Text {
                        visible: !input.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: "RUN /"
                        color: Theme.outline
                        renderType: Text.CurveRendering
                        font.family: Theme.monoFont
                        font.pixelSize: 11
                        font.letterSpacing: 1
                    }
                }

                Text {
                    id: count
                    anchors { right: parent.right; rightMargin: launcher.listPad + 12; verticalCenter: parent.verticalCenter }
                    visible: input.text.length > 0
                    text: launcher.results.length ? String(launcher.results.length).padStart(2, "0") : "--"
                    color: launcher.results.length ? Theme.fgDim : Theme.error
                        renderType: Text.CurveRendering
                        font.family: Theme.monoFont
                    font.pixelSize: 11
                }
            }

            Repeater {
                model: launcher.rows

                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: launcher.first + index === launcher.selected
                    x: launcher.listPad
                    y: launcher.pillH + index * launcher.rowH
                    width: box.width - 2 * launcher.listPad
                    height: launcher.rowH

                    IconImage {
                        id: icon
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 22
                        visible: !row.modelData.glyph
                        source: Quickshell.iconPath(row.modelData.icon ?? "", "application-x-executable")
                    }
                    Text {
                        anchors.centerIn: icon
                        visible: !!row.modelData.glyph
                        text: row.modelData.glyph ?? ""
                        // Colour glyphs: the curve renderer has none.
                        renderType: Text.NativeRendering
                        font.family: "Noto Color Emoji"
                        font.pixelSize: 18
                    }
                    Text {
                        id: name
                        anchors { left: icon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        width: Math.min(implicitWidth, row.width - 200)
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: row.modelData.markup
                        color: row.current ? Theme.fg : Theme.fgDim
                        renderType: Text.CurveRendering
                        font.family: Theme.displayFont
                        font.pixelSize: 15
                        font.weight: row.current ? Font.DemiBold : Font.Medium
                    }
                    Text {
                        anchors { left: name.right; leftMargin: 16; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: row.modelData.note
                        color: row.current ? Theme.fgDim : Theme.outline
                        renderType: Text.CurveRendering
                        font.family: Theme.monoFont
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        // Only a pointer that moved: a row scrolled under
                        // a resting one must not take the selection.
                        onPositionChanged: mouse => {
                            const at = mapToItem(box, mouse.x, mouse.y);
                            if (at.x === box.hoverX && at.y === box.hoverY)
                                return;
                            box.hoverX = at.x;
                            box.hoverY = at.y;
                            launcher.selected = launcher.first + row.index;
                        }
                        onClicked: launcher.activate(row.modelData)
                    }
                }
            }
        }
    }
}
