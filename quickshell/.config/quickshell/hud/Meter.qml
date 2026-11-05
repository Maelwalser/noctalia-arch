import QtQuick

// Segmented bar meter: `segments` blocks, filled up to `value` (0..1).
Row {
    id: root

    property real value: 0
    property int segments: 20
    property real u: 1
    property real critical: 0.85

    spacing: 3 * u

    Behavior on value {
        NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
    }

    Repeater {
        model: root.segments
        Rectangle {
            required property int index
            readonly property bool lit: index < Math.round(root.value * root.segments)
            width: 9 * root.u
            height: 7 * root.u
            color: !lit ? Theme.outline : (root.value >= root.critical ? Theme.error : Theme.primary)
            opacity: lit ? 1 : 0.3
            // Skewed blocks echo the hazard-stripe language.
            transform: Matrix4x4 {
                matrix: Qt.matrix4x4(1, -0.35, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
            }
        }
    }
}
