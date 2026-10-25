pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth

// Wi-Fi and wired state from NetworkManager, VPNs through nmcli, airplane mode through rfkill
Singleton {
    id: root

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null
    readonly property bool wiredUp: wired?.connected ?? false
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property var networks: (wifi?.networks?.values ?? []).slice().sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
    readonly property var active: networks.find(n => n.connected) ?? null
    readonly property real signal: active?.signalStrength ?? 0
    property bool airplane: false
    property var vpns: []            // [{name, type, active}]
    readonly property bool vpnUp: vpns.some(v => v.active)

    function wifiIcon(s: real): string {
        return s > 0.75 ? "network_wifi" : s > 0.5 ? "network_wifi_3_bar" : s > 0.25 ? "network_wifi_2_bar" : "network_wifi_1_bar";
    }

    readonly property string icon: airplane ? "flight" : wiredUp ? "lan" : !wifiOn ? "wifi_off" : active ? wifiIcon(signal) : "signal_wifi_statusbar_not_connected"
    readonly property string label: airplane ? "Airplane mode" : wiredUp ? "Ethernet" : !wifiOn ? "Wi-Fi off" : active ? active.name : "Not connected"

    function setWifi(on: bool): void {
        Networking.wifiEnabled = on;
    }

    function scan(on: bool): void {
        if (root.wifi)
            root.wifi.scannerEnabled = on;
    }

    function toggleAirplane(): void {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/airplane-mode"]);
        rfkillCheck.restart();
    }

    function setVpn(name: string, up: bool): void {
        Quickshell.execDetached(["nmcli", "connection", up ? "up" : "down", name]);
        vpnCheck.restart();
    }

    function refresh(): void {
        rfkill.running = true;
        vpnProc.running = true;
    }

    // airplane = every radio soft-blocked (what the airplane-mode script does)
    Process {
        id: rfkill

        command: ["rfkill", "-n", "-o", "SOFT"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l);
                root.airplane = lines.length > 0 && lines.every(l => l.trim() === "blocked");
            }
        }
    }

    Process {
        id: vpnProc

        command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.vpns = text.trim().split("\n").map(l => l.split(":")).filter(f => f.length >= 3 && /vpn|wireguard/.test(f[1])).map(f => ({ name: f[0], type: f[1], active: f[2] === "yes" }));
            }
        }
    }

    Timer {
        id: rfkillCheck

        interval: 900
        onTriggered: rfkill.running = true
    }

    Timer {
        id: vpnCheck

        interval: 2500
        onTriggered: vpnProc.running = true
    }

    // radios and connections change rarely; re-check when Wi-Fi or Bluetooth state changes, and every 30 s
    Connections {
        target: Networking

        function onWifiEnabledChanged(): void {
            rfkillCheck.restart();
        }
    }

    Connections {
        target: Bluetooth.defaultAdapter

        function onEnabledChanged(): void {
            rfkillCheck.restart();
        }
    }

    onActiveChanged: vpnCheck.restart()

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
