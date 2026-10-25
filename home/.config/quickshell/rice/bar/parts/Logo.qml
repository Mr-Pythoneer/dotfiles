import QtQuick
import Quickshell.Io
import qs.services
import qs.components

// The distro's logo (Arch here, Fedora in the VM): opens Caelestia's app launcher
Item {
    id: root

    property bool fedora: false

    implicitWidth: 34
    implicitHeight: 30

    Txt {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: -1
        text: root.fedora ? "" : ""   // nerd font: nf-linux-fedora / nf-linux-archlinux
        font.pixelSize: 18
        color: Theme.tertiary
    }

    FileView {
        path: "/etc/os-release"
        onLoaded: root.fedora = /^ID="?fedora"?$/m.test(text())
    }

    Hover {
        onClicked: Ctl.drawer("launcher")
    }
}
