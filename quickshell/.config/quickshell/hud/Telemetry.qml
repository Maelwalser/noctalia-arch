import QtQuick

// Bottom-left readout block, on its glass pane: tick strip, header, a CPU
// history trace and the CPU / MEM / TEMP / GPU meters with uptime. Network
// rates live on the Signal oscilloscope. `width` is the pane's inner width.
Column {
    id: root

    property real u: 1

    spacing: 8 * u

    function fmtUptime(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d > 0 ? d + "D " : "") + String(h).padStart(2, "0") + "H " + String(m).padStart(2, "0") + "M";
    }
    function fmtGpu() {
        // The clock reads 0 while the GPU sits in RC6.
        const clock = SysStats.gpuMhz > 0 ? SysStats.gpuMhz + "MHz" : "IDLE";
        return SysStats.gpu < 0 ? "--" : Math.round(SysStats.gpu * 100) + "% " + clock;
    }

    HudImage {
        name: "tick-strip"
        width: 300 * root.u
        height: 34 * root.u
        opacity: 0.8
    }

    Row {
        spacing: 10 * root.u
        Rectangle { width: 6 * root.u; height: 14 * root.u; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: "TELEMETRY // " + SysStats.host.toUpperCase()
            color: Theme.primary
            font.family: Theme.monoFont
            font.pixelSize: 13 * root.u
            font.letterSpacing: 2 * root.u
        }
    }

    // CPU history: one point per sample (2 s), the last two minutes. Painted
    // only when a sample lands, so it costs nothing between samples.
    Canvas {
        id: trace
        width: parent.width
        height: 32 * root.u
        property var history: []
        Connections {
            target: SysStats
            function onSampled() {
                trace.history.push(SysStats.cpu);
                if (trace.history.length > 60)
                    trace.history.shift();
                trace.requestPaint();
            }
        }
        onPaint: {
            const c = getContext("2d");
            c.clearRect(0, 0, width, height);
            const step = width / 59, pad = Math.max(1, root.u);
            // Graticule: dotted lines at 0, 50 and 100 %, so the strip reads
            // as an instrument before the history has filled.
            c.strokeStyle = Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.6);
            c.lineWidth = Math.max(1, root.u);
            c.setLineDash([2 * root.u, 4 * root.u]);
            for (const f of [0, 0.5, 1]) {
                const y = Math.round(pad + (height - 2 * pad) * f) + 0.5;
                c.beginPath();
                c.moveTo(0, y);
                c.lineTo(width, y);
                c.stroke();
            }
            c.setLineDash([]);
            const h = trace.history, n = h.length;
            if (n < 2)
                return;
            // Newest sample at the right edge: the trace scrolls in from the
            // right, so a short history is not a stub at the left.
            const x0 = width - (n - 1) * step;
            // Area under the trace, faint, then the line.
            c.beginPath();
            c.moveTo(x0, height);
            for (let i = 0; i < n; i++)
                c.lineTo(x0 + i * step, pad + (height - 2 * pad) * (1 - h[i]));
            c.lineTo(width, height);
            c.closePath();
            c.fillStyle = Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12);
            c.fill();
            c.beginPath();
            for (let i = 0; i < n; i++) {
                const x = x0 + i * step, y = pad + (height - 2 * pad) * (1 - h[i]);
                i === 0 ? c.moveTo(x, y) : c.lineTo(x, y);
            }
            c.strokeStyle = Theme.primary;
            c.lineWidth = Math.max(1, 1.5 * root.u);
            c.lineJoin = "round";
            c.stroke();
        }
    }

    component Readout: Item {
        property string label
        property string value
        property real level: -1
        property real critical: 0.85
        width: root.width
        height: 16 * root.u
        Text {
            width: 52 * root.u
            text: parent.label
            color: Theme.fgDim
            font.family: Theme.monoFont
            font.pixelSize: 12 * root.u
            anchors.verticalCenter: parent.verticalCenter
        }
        Meter {
            x: 64 * root.u
            visible: parent.level >= 0
            value: Math.max(0, parent.level)
            critical: parent.critical
            segments: 14
            u: root.u
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            anchors.right: parent.right
            text: parent.value
            color: Theme.fg
            font.family: Theme.monoFont
            font.pixelSize: 13 * root.u
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Readout { label: "CPU";  level: SysStats.cpu; value: Math.round(SysStats.cpu * 100) + "%" }
    Readout { label: "MEM";  level: SysStats.mem; value: SysStats.memUsedGb.toFixed(1) + "G" }
    Readout { label: "TEMP"; level: Math.min(1, SysStats.tempC / 100); critical: 0.9; value: Math.round(SysStats.tempC) + "°C" }
    Readout { label: "GPU";  level: Math.max(0, SysStats.gpu); value: root.fmtGpu() }
    Readout { label: "DGPU"; visible: SysStats.dgpuState !== ""; value: SysStats.dgpuState === "active" ? "ACTIVE" : "SLEEP" }
    Readout { label: "UP";   value: fmtUptime(SysStats.uptimeSec) + "  ·  " + SysStats.kernel }
}
