import QtQuick
import QtQuick.Window

// A pre-tinted overlay layer from ~/.local/share/hud/overlay.
Image {
    property string name

    source: Theme.asset(name)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
    // Decode at on-screen size: the sources are 512-1024 px.
    sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
}
