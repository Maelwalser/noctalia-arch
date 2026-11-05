import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// ACID//HUD desktop overlay: one click-through layer per output, above
// Noctalia's wallpaper and below every window. Start with `hud-overlay start`.
ShellRoot {
    id: shell

    // Stats are sampled only while at least one output shows the desktop.
    // Derived from the live instances rather than counted, so it cannot drift.
    Binding {
        target: SysStats
        property: "active"
        value: screens.instances.some(w => w.sceneActive)
    }

    Variants {
        id: screens
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property bool sceneActive: scene.active

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            // Empty region: no input is ever taken, clicks reach the desktop.
            mask: Region {}

            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "hud-overlay"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            HudScene {
                id: scene
                anchors.fill: parent
                monitor: Hyprland.monitorFor(win.modelData)
            }
        }
    }
}
