pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One `sh` sample every 2 s while any overlay is visible. /proc files report a
// size of 0, so they are read through a process rather than FileView.
Singleton {
    id: root

    property bool active: false

    property real cpu: 0        // 0..1
    property real mem: 0        // 0..1
    property real memUsedGb: 0
    property real tempC: 0
    property real rxKbs: 0
    property real txKbs: 0
    // Integrated GPU: busy share from RC6 (idle) residency, and its clock.
    property real gpu: -1       // 0..1, -1 until known / no Intel GPU
    property int gpuMhz: 0
    // Discrete GPU power state from PCI runtime PM ("active", "suspended", ""
    // when absent). Read from sysfs only: querying nvidia-smi would wake it.
    property string dgpuState: ""
    property int uptimeSec: 0
    property string host: "--"
    property string kernel: "--"

    // Fires after every poll, even when no value changed (a pegged CPU still samples).
    signal sampled()

    property var _prevCpu: null
    property var _prevNet: null
    property var _prevRc6: null
    property real _prevT: 0

    readonly property string _script: "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; cat /proc/uptime; "
        + "for z in /sys/class/thermal/thermal_zone*; do [ \"$(cat $z/type)\" = x86_pkg_temp ] && { echo TEMP $(cat $z/temp); break; }; done; "
        + "awk 'NR>2 && $1 !~ /^(lo|docker|veth|br-|tailscale|virbr)/ {rx+=$2; tx+=$10} END {print \"NET\", rx, tx}' /proc/net/dev; "
        + "for g in /sys/class/drm/card*/gt/gt0; do [ -r $g/rc6_residency_ms ] && { echo IGPU $(cat $g/rc6_residency_ms $g/rps_act_freq_mhz); break; }; done; "
        + "for d in /sys/bus/pci/devices/*; do [ \"$(cat $d/vendor)\" = 0x10de ] && case $(cat $d/class) in 0x03*) echo DGPU $(cat $d/power/runtime_status); break;; esac; done"

    function parse(out) {
        const now = Date.now() / 1000;
        for (const line of out.split("\n")) {
            const f = line.trim().split(/\s+/);
            if (f[0] === "cpu") {
                const v = f.slice(1).map(Number);
                const idle = v[3] + v[4];
                const total = v.reduce((a, b) => a + b, 0);
                if (_prevCpu)
                    cpu = Math.max(0, Math.min(1, 1 - (idle - _prevCpu.idle) / Math.max(1, total - _prevCpu.total)));
                _prevCpu = { idle: idle, total: total };
            } else if (f[0] === "MemTotal:") {
                _memTotal = Number(f[1]);
            } else if (f[0] === "MemAvailable:") {
                const used = _memTotal - Number(f[1]);
                mem = _memTotal > 0 ? used / _memTotal : 0;
                memUsedGb = used / 1048576;
            } else if (f[0] === "TEMP") {
                tempC = Number(f[1]) / 1000;
            } else if (f[0] === "NET") {
                const rx = Number(f[1]), tx = Number(f[2]);
                if (_prevNet && now > _prevT) {
                    rxKbs = (rx - _prevNet.rx) / 1024 / (now - _prevT);
                    txKbs = (tx - _prevNet.tx) / 1024 / (now - _prevT);
                }
                _prevNet = { rx: rx, tx: tx };
            } else if (f[0] === "IGPU") {
                const rc6 = Number(f[1]);
                gpuMhz = Number(f[2]) || 0;
                if (_prevRc6 !== null && now > _prevT)
                    gpu = Math.max(0, Math.min(1, 1 - (rc6 - _prevRc6) / 1000 / (now - _prevT)));
                _prevRc6 = rc6;
            } else if (f[0] === "DGPU") {
                dgpuState = f[1] ?? "";
            } else if (f.length === 2 && /^[0-9.]+$/.test(f[0]) && /^[0-9.]+$/.test(f[1])) {
                uptimeSec = Math.floor(Number(f[0]));
            }
        }
        _prevT = now;
        sampled();
    }
    property real _memTotal: 0

    Process {
        id: sampler
        command: ["sh", "-c", root._script]
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    Process {
        running: true
        command: ["uname", "-nr"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split(/\s+/);
                root.host = f[0] ?? "--";
                root.kernel = f[1] ?? "--";
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.active
        onTriggered: if (!sampler.running) sampler.running = true
    }
}
