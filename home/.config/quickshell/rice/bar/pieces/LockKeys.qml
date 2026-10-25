import QtQuick
import qs.services
import qs.components

// The input method (fcitx5 switches Chinese/English on Caps Lock), then Caps Lock and Num Lock, lit when on
Column {
    spacing: 8

    Row {
        width: parent.width
        spacing: 8
        leftPadding: 4

        Icon {
            icon: "translate"
            size: 16
            color: InputMethod.chinese ? Theme.purple : Theme.fgDim
        }

        Txt {
            text: InputMethod.state === 0 ? "No text box focused" : InputMethod.chinese ? "Typing Chinese (拼音)" : "Typing English"
            font.pixelSize: 12
            color: InputMethod.chinese ? Theme.purple : Theme.fg
        }
    }

    Row {
        width: parent.width
        spacing: 8

        Repeater {
            model: [{ name: "Caps Lock", on: Hypr.capsLock, icon: "keyboard_capslock" }, { name: "Num Lock", on: Hypr.numLock, icon: "dialpad" }]

            Rectangle {
                required property var modelData

                width: (parent.width - 8) / 2
                height: 40
                radius: Theme.radiusSmall
                color: modelData.on ? Qt.alpha(Theme.tertiary, 0.16) : Theme.card
                border.width: 1
                border.color: modelData.on ? Qt.alpha(Theme.tertiary, 0.55) : Qt.alpha(Theme.line, 0.35)

                Behavior on color { ColorAnimation { duration: Theme.durFast } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Icon {
                        icon: modelData.icon
                        size: 16
                        color: modelData.on ? Theme.tertiary : Theme.fgDim
                    }

                    Txt {
                        text: modelData.name + (modelData.on ? " on" : " off")
                        font.pixelSize: 12
                        color: modelData.on ? Theme.tertiary : Theme.fgDim
                    }
                }
            }
        }
    }
}
