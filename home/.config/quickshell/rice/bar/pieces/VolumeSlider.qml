import QtQuick
import qs.services
import qs.components

// Volume; click the speaker to mute
Slider {
    value: Audio.muted ? 0 : Audio.volume
    icon: Audio.volumeIcon(Audio.volume, Audio.muted)
    label: Audio.muted ? "muted" : Math.round(Audio.volume * 100) + "%"
    accent: Theme.primary
    onMoved: v => Audio.setVolume(v)
    onIconClicked: Audio.toggleMute()
}
