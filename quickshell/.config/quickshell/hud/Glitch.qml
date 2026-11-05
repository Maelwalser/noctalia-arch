import QtQuick

// Short burst of displaced slices + RGB-offset bars. Call trigger(); `jitter`
// is read by the scene to shake its content for the same few frames.
Item {
    id: root

    property real u: 1
    property real jitter: 0
    property int step: 0

    function trigger() {
        step = 0;
        burst.restart();
    }

    function shuffle() {
        jitter = (Math.random() - 0.5) * 16 * u;
        for (let i = 0; i < slices.count; i++) {
            const s = slices.itemAt(i);
            s.y = Math.random() * height;
            s.height = (2 + Math.random() * 22) * u;
            s.x = (Math.random() - 0.3) * width * 0.4;
            s.width = width * (0.2 + Math.random() * 0.7);
            s.color = Math.random() < 0.55 ? Theme.primary : (Math.random() < 0.5 ? Theme.fg : Theme.error);
            s.visible = Math.random() < 0.8;
        }
    }

    Repeater {
        id: slices
        model: 9
        Rectangle {
            visible: false
            opacity: 0.22
        }
    }

    Timer {
        id: burst
        interval: 55
        repeat: true
        onTriggered: {
            if (root.step++ < 4) {
                root.shuffle();
            } else {
                stop();
                root.jitter = 0;
                for (let i = 0; i < slices.count; i++)
                    slices.itemAt(i).visible = false;
            }
        }
    }
}
