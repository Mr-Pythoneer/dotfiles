import QtQuick
import qs.services
import qs.components

// Keyboard layout (EN, FR...), with a Caps Lock arrow when it's on
Item {
    id: root

    readonly property string code: {
        const k = Hypr.keymap;
        if (!k)
            return "EN";
        return k.replace(/[^A-Za-z].*$/, "").slice(0, 2).toUpperCase() || "EN";
    }

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 30

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 4

        Icon {
            icon: "keyboard"
            size: 16
            color: Theme.fgDim
        }

        Txt {
            text: InputMethod.chinese ? "中" : root.code
            font.pixelSize: InputMethod.chinese ? 14 : 12
            font.weight: Font.DemiBold
            color: InputMethod.chinese ? Theme.purple : Theme.fg
        }

        Icon {
            visible: Hypr.capsLock
            icon: "keyboard_capslock"
            size: 15
            color: Theme.tertiary
        }
    }
}
