import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.components

// Every window on this monitor; click one to jump to it. A dot marks the focused one.
Item {
    id: root

    readonly property string monName: parent?.monName ?? ""
    readonly property var wins: Hypr.windowsOnMonitor(monName)

    implicitWidth: row.implicitWidth + 8
    implicitHeight: 30

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.wins

            Item {
                id: w

                required property var modelData
                readonly property bool focused: Hypr.activeWindow === modelData

                implicitWidth: 30
                implicitHeight: 30

                IconImage {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    implicitSize: 18
                    source: Hypr.appIcon(w.modelData)
                    scale: w.focused ? 1.08 : 1

                    Behavior on scale { Springy {} }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    height: 3
                    width: w.focused ? 12 : 4
                    radius: 1.5
                    color: w.focused ? Theme.primary : Qt.alpha(Theme.fgDim, 0.5)

                    Behavior on width { Springy {} }
                }

                Hover {
                    radius: 10
                    onClicked: Hypr.focusWindow(w.modelData)
                }
            }
        }
    }
}
