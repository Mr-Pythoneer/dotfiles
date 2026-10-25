import QtQuick
import qs.services

// A Material Symbols Rounded icon; `fill` 0..1 switches between outlined and filled
Text {
    property string icon
    property real fill: 0
    property int size: 18

    text: icon
    color: Theme.fg
    font.family: Theme.iconFont
    font.pixelSize: size
    font.variableAxes: ({ "FILL": fill, "wght": 400, "GRAD": 0, "opsz": 24 })
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
