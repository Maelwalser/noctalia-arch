import QtQuick
import Quickshell
import Quickshell.Wayland

// One window of the desktop scene: click-through, on the bottom layer, as
// large as one pane and its margin (Layout.frame). What is put in it is
// placed in screen coordinates, as if the window covered the screen.
PanelWindow {
    id: win

    required property rect card     // the pane's box on the screen, logical px
    required property string ns
    readonly property rect frame: Layout.frame(card)
    default property alias content: stage.data

    anchors { top: true; left: true }
    margins { top: frame.y; left: frame.x }
    implicitWidth: frame.width
    implicitHeight: frame.height
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Empty region: no input is ever taken, clicks reach the desktop.
    mask: Region {}

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: ns
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
        id: stage
        x: -win.frame.x
        y: -win.frame.y
        width: win.screen ? win.screen.width : 0
        height: win.screen ? win.screen.height : 0
    }
}
