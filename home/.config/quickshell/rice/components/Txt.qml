import QtQuick
import qs.services

Text {
    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: Theme.textSize
    textFormat: Text.PlainText   // titles and clipboard text can contain <tags>; show them as typed
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    maximumLineCount: 1
}
