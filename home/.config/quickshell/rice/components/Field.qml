import QtQuick
import qs.services

// A rounded one-line text box
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    property alias input: input

    signal accepted()
    signal escaped()

    implicitHeight: 34
    radius: height / 2
    color: Qt.alpha(Theme.fg, 0.07)
    border.width: 1
    border.color: input.activeFocus ? Theme.primary : Qt.alpha(Theme.line, 0.6)

    Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fg
        selectionColor: Qt.alpha(Theme.primary, 0.4)
        font.family: Theme.font
        font.pixelSize: 13
        clip: true
        onAccepted: root.accepted()
        Keys.onEscapePressed: root.escaped()

        Txt {
            visible: !input.text
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholder
            color: Theme.fgDim
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onPressed: mouse => {
            input.forceActiveFocus();
            mouse.accepted = false;
        }
    }
}
