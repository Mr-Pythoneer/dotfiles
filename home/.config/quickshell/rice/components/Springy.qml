import QtQuick
import qs.services

// The shell's standard motion: overshoots a little, then settles
NumberAnimation {
    duration: Theme.durIn
    easing.type: Easing.OutBack
    easing.overshoot: 1.15
}
