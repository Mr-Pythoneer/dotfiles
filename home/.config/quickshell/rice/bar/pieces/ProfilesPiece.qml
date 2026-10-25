import QtQuick
import Quickshell.Services.UPower
import qs.services
import qs.components

// Saver / balanced / performance. power-mode switches these when you plug in or unplug; a pick here sticks until then.
Row {
    id: root

    spacing: 6

    Repeater {
        model: [
            { p: PowerProfile.PowerSaver, name: "Saver", icon: "eco", c: Theme.secondary },
            { p: PowerProfile.Balanced, name: "Balanced", icon: "balance", c: Theme.primary },
            { p: PowerProfile.Performance, name: "Performance", icon: "speed", c: Theme.tertiary }
        ]

        Rectangle {
            required property var modelData
            readonly property bool sel: PowerProfiles.profile === modelData.p

            width: (root.width - 12) / 3
            height: 58
            radius: Theme.radiusSmall
            color: sel ? Qt.alpha(modelData.c, 0.18) : Theme.card
            border.width: 1
            border.color: sel ? Qt.alpha(modelData.c, 0.6) : Qt.alpha(Theme.line, 0.35)
            visible: modelData.p !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile

            Behavior on color { ColorAnimation { duration: Theme.durFast } }

            Column {
                anchors.centerIn: parent
                spacing: 3

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    icon: modelData.icon
                    size: 20
                    fill: sel ? 1 : 0
                    color: sel ? modelData.c : Theme.fgDim
                }

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.name
                    font.pixelSize: 11
                    color: sel ? modelData.c : Theme.fgDim
                }
            }

            Hover {
                radius: Theme.radiusSmall
                onClicked: PowerProfiles.profile = modelData.p
            }
        }
    }
}
