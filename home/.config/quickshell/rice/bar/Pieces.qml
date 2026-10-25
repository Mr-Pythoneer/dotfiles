pragma Singleton

import QtQuick
import Quickshell
import qs.services
import qs.components
import qs.bar.pieces

// Builder part ids -> what they look like inside a popout
Singleton {
    readonly property var map: ({
            "now-playing": nowPlaying,
            "media-controls": mediaControls,
            "volume-slider": volume,
            "volume": volume,
            "audio-output": output,
            "pop-audio-devices": output,
            "lock-keys": lockKeys,
            "updates": updates,
            "news": news,
            "date": date,
            "uptime": uptime,
            "timer": timer,
            "pop-calendar": calendar,
            "calendar-btn": calendar,
            "pop-bt-list": bt,
            "bluetooth": bt,
            "airplane": airplane,
            "vpn": vpn,
            "pop-wifi-list": wifi,
            "network": wifi,
            "pop-sysstats": sysstats,
            "sysstats": sysstats,
            "pop-battery-time": batteryTime,
            "battery": batteryTime,
            "pop-profiles": profiles,
            "power-profile": profiles,
            "pop-smart-charge": smartCharge,
            "battery-charge": smartCharge,
            "separator": separator,
            "gap": gap
        })

    function get(id: string): var {
        return map[id] ?? fallback;
    }

    property Component nowPlaying: Component { NowPlaying {} }
    property Component mediaControls: Component { MediaControls {} }
    property Component volume: Component { VolumeSlider {} }
    property Component output: Component { SoundDevices {} }
    property Component sysstats: Component { SysStatsPiece {} }
    property Component lockKeys: Component { LockKeys {} }
    property Component updates: Component { UpdatesPiece {} }
    property Component news: Component { NewsPiece {} }
    property Component date: Component { DatePiece {} }
    property Component uptime: Component { UptimePiece {} }
    property Component timer: Component { TimerPiece {} }
    property Component calendar: Component { CalendarPiece {} }
    property Component bt: Component { BtDevices {} }
    property Component airplane: Component { AirplanePiece {} }
    property Component vpn: Component { VpnPiece {} }
    property Component wifi: Component { WifiList {} }
    property Component batteryTime: Component { BatteryTime {} }
    property Component profiles: Component { ProfilesPiece {} }
    property Component smartCharge: Component { SmartChargePiece {} }
    property Component separator: Component {
        Item {
            implicitHeight: 9

            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 16
                height: 1
                color: Theme.line
            }
        }
    }
    property Component gap: Component {
        Item {
            implicitHeight: parent?.entry?.width ?? 16
        }
    }
    // a part with no popout version yet: its bar form, in a card with its name
    property Component fallback: Component {
        Card {
            id: fb

            readonly property var entry: parent?.entry

            implicitHeight: 46

            Loader {
                id: inner

                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: Parts.get(fb.entry?.id ?? "")
                property var entry: fb.entry
                property string monName: Hypr.focusedMonitor
            }

            Txt {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: fb.entry?.name ?? ""
                font.pixelSize: 11
                color: Theme.fgDim
            }
        }
    }
}
