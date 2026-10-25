import QtQuick
import QtQuick.Shapes
import qs.services

// A round gauge: value 0..1 as an arc, with a label in the middle
Item {
    id: root

    property real value: 0
    property color accent: Theme.primary
    property string text: Math.round(value * 100) + "%"
    property string caption
    property real thickness: 7

    implicitWidth: 76
    implicitHeight: 76

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.alpha(Theme.fg, 0.1)
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - root.thickness
                radiusY: radiusX
                startAngle: 135
                sweepAngle: 270
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.accent
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - root.thickness
                radiusY: radiusX
                startAngle: 135
                sweepAngle: 270 * Math.max(0.001, Math.min(1, root.value))

                Behavior on sweepAngle { Springy {} }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0

        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.text
            font.pixelSize: 15
            font.weight: Font.Bold
            color: root.accent
        }

        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.caption !== ""
            text: root.caption
            font.pixelSize: 10
            color: Theme.fgDim
        }
    }
}
