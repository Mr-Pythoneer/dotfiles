import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// A small section title inside a popout, with room for a control on the right
RowLayout {
    property string text
    property string icon
    default property alias trailing: slot.data

    spacing: 6

    Icon {
        visible: parent.icon !== ""
        icon: parent.icon
        size: 15
        color: Theme.fgDim
    }

    Txt {
        Layout.fillWidth: true
        text: parent.text
        font.pixelSize: Theme.smallText
        font.weight: Font.DemiBold
        color: Theme.fgDim
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
    }

    Row {
        id: slot

        spacing: 6
    }
}
