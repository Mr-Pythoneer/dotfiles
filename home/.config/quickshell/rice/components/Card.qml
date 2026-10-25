import QtQuick
import qs.services

// A raised block inside a popout or panel
Rectangle {
    color: Theme.card
    radius: Theme.radiusSmall
    border.width: 1
    border.color: Qt.alpha(Theme.line, 0.35)
}
