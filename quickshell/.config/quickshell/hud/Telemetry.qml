import QtQuick

// Bottom-left readout block: CPU / MEM / TEMP / GPU meters, uptime. Network
// rates live on the Signal oscilloscope.
Column {
    id: root

    property real u: 1

    spacing: 10 * u

    function fmtUptime(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d > 0 ? d + "D " : "") + String(h).padStart(2, "0") + "H " + String(m).padStart(2, "0") + "M";
    }
    function fmtGpu() {
        // The clock reads 0 while the GPU sits in RC6.
        const clock = SysStats.gpuMhz > 0 ? SysStats.gpuMhz + "MHz" : "IDLE";
        const igpu = SysStats.gpu < 0 ? "--" : Math.round(SysStats.gpu * 100) + "%  " + clock;
        if (SysStats.dgpuState === "")
            return igpu;
        return igpu + "   ·   dGPU " + (SysStats.dgpuState === "active" ? "ACTIVE" : "SLEEP");
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

    component Readout: Row {
        property string label
        property string value
        property real level: -1
        property real critical: 0.85
        spacing: 12 * root.u
        Text {
            width: 52 * root.u
            text: parent.label
            color: Theme.fgDim
            font.family: Theme.monoFont
            font.pixelSize: 12 * root.u
            anchors.verticalCenter: parent.verticalCenter
        }
        Meter {
            visible: parent.level >= 0
            value: Math.max(0, parent.level)
            critical: parent.critical
            u: root.u
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
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
    Readout { label: "UP";   value: fmtUptime(SysStats.uptimeSec) + "   ·   " + SysStats.kernel }
}
