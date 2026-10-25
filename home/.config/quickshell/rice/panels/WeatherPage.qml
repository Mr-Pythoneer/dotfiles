import QtQuick
import qs.services
import qs.components

// Weather: now, the next 12 hours, and the week
Item {
    id: root

    Card {
        id: now

        width: 290
        height: parent.height

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 30
            spacing: 6

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                icon: Weather.icon(Weather.code, Weather.isDay)
                size: 110
                fill: 1
                color: Weather.tint(Weather.code, Weather.isDay)
            }

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Weather.ready ? Math.round(Weather.temp) + "°" : "…"
                font.pixelSize: 60
                font.weight: Font.Bold
            }

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Weather.ready ? Weather.describe(Weather.code) : "Getting the weather"
                font.pixelSize: 16
                color: Theme.fg
            }

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Weather.city
                color: Theme.primary
                font.weight: Font.DemiBold
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 20
            spacing: 10
            visible: Weather.ready

            Repeater {
                model: [
                    { icon: "thermostat", name: "Feels like", v: Math.round(Weather.feels) + "°" },
                    { icon: "humidity_percentage", name: "Humidity", v: Weather.humidity + "%" },
                    { icon: "air", name: "Wind", v: Math.round(Weather.wind) + " km/h" }
                ]

                Item {
                    required property var modelData

                    width: parent.width
                    height: 20

                    Row {
                        spacing: 8

                        Icon {
                            icon: modelData.icon
                            size: 16
                            color: Theme.fgDim
                        }

                        Txt {
                            text: modelData.name
                            color: Theme.fgDim
                        }
                    }

                    Txt {
                        anchors.right: parent.right
                        text: modelData.v
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    Column {
        anchors.left: now.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        spacing: 12

        Card {
            width: parent.width
            height: 150

            Txt {
                x: 14
                y: 12
                text: "NEXT 12 HOURS"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
                color: Theme.fgDim
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2

                Repeater {
                    model: Weather.hourly

                    Column {
                        required property var modelData
                        required property int index

                        width: 44
                        spacing: 6

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: index === 0 ? "now" : Qt.formatTime(modelData.time, "h ap").replace(" ", "")
                            font.pixelSize: 10
                            color: index === 0 ? Theme.primary : Theme.fgDim
                        }

                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            icon: Weather.icon(modelData.code, modelData.time.getHours() >= 6 && modelData.time.getHours() < 20)
                            size: 22
                            fill: 1
                            color: Weather.tint(modelData.code, modelData.time.getHours() >= 6 && modelData.time.getHours() < 20)
                        }

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(modelData.temp) + "°"
                            font.weight: Font.DemiBold
                        }

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.rain > 0 ? modelData.rain + "%" : ""
                            font.pixelSize: 9
                            color: Theme.cyan
                        }
                    }
                }
            }
        }

        Card {
            width: parent.width
            height: root.height - 162

            readonly property real lo: Math.min(...Weather.daily.map(d => d.min), 0)
            readonly property real hi: Math.max(...Weather.daily.map(d => d.max), 1)

            Column {
                id: week

                anchors.fill: parent
                anchors.margins: 14
                spacing: 4

                Txt {
                    text: "THIS WEEK"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    color: Theme.fgDim
                    bottomPadding: 4
                }

                Repeater {
                    model: Weather.daily

                    Item {
                        id: day

                        required property var modelData
                        required property int index
                        readonly property real lo: parent.parent.lo
                        readonly property real hi: parent.parent.hi

                        width: week.width
                        height: 40

                        Txt {
                            id: dn

                            width: 90
                            anchors.verticalCenter: parent.verticalCenter
                            text: index === 0 ? "Today" : Qt.formatDate(modelData.date, "dddd")
                            font.weight: index === 0 ? Font.Bold : Font.Normal
                        }

                        Icon {
                            id: di

                            anchors.left: dn.right
                            anchors.verticalCenter: parent.verticalCenter
                            icon: Weather.icon(modelData.code, true)
                            size: 20
                            fill: 1
                            color: Weather.tint(modelData.code, true)
                        }

                        Txt {
                            id: rain

                            anchors.left: di.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            text: modelData.rain > 10 ? modelData.rain + "%" : ""
                            font.pixelSize: 11
                            color: Theme.cyan
                        }

                        Txt {
                            id: minT

                            anchors.left: rain.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(modelData.min) + "°"
                            color: Theme.fgDim
                        }

                        Item {
                            id: track

                            anchors.left: minT.right
                            anchors.leftMargin: 10
                            anchors.right: maxT.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            height: 6

                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: Qt.alpha(Theme.fg, 0.08)
                            }

                            Rectangle {
                                x: parent.width * (day.modelData.min - day.lo) / Math.max(1, day.hi - day.lo)
                                width: Math.max(6, parent.width * (day.modelData.max - day.modelData.min) / Math.max(1, day.hi - day.lo))
                                height: parent.height
                                radius: 3
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: Theme.cyan }
                                    GradientStop { position: 1; color: Theme.tertiary }
                                }
                            }
                        }

                        Txt {
                            id: maxT

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(modelData.max) + "°"
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
