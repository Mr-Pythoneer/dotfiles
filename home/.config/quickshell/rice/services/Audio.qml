pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Caelestia.Services

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    // rebuilt when PipeWire's node list changes, not as bindings: tracking the nodes (below) would otherwise
    // re-trigger the filters in a loop and crash the shell
    property list<PwNode> sinks: []
    property list<PwNode> sources: []
    property list<PwNode> streams: []

    function refreshNodes(): void {
        const si = [], so = [], st = [];
        for (const n of Pipewire.nodes.values) {
            if (!n.isStream) {
                if (n.isSink)
                    si.push(n);
                else if (n.audio)
                    so.push(n);
            } else if (n.audio) {
                st.push(n);
            }
        }
        root.sinks = si;
        root.sources = so;
        root.streams = st;
        if (si.length && !root.armed)
            arm.start();   // count from the first device list, not from shell start (PipeWire can be slow at login)
        root.watchNew([...si, ...so]);
        root.refreshPicker();
        ports.refresh();
    }

    Connections {
        target: Pipewire.nodes

        function onValuesChanged(): void {
            root.refreshNodes();
        }
    }

    Component.onCompleted: refreshNodes()

    // ---- where sound goes: the device picker and automatic switching ----

    // what the picker lists: best first, without jacks/HDMI ports that have nothing plugged in
    property list<PwNode> outputs: []
    property list<PwNode> inputs: []
    // node name -> false while its port says "not available"; Quickshell doesn't expose ports, pactl does
    property var avail: ({})
    property bool autoSwitch: true
    property bool pickerOpen: false   // the control centre's device list stays the way you left it
    property string pickerTab: "out"

    function refreshPicker(): void {
        const order = n => ["bluetooth", "usb", "headphones", "speaker", "hdmi", "mic", "jack-mic", "bt-mic"].indexOf(kind(n));
        const pick = l => l.filter(n => root.available(n)).sort((a, b) => order(a) - order(b));
        root.outputs = pick(root.sinks);
        root.inputs = pick(root.sources);
        rescue.restart();
    }

    function available(n: PwNode): bool {
        return root.avail[n?.name] !== false;
    }

    // from the node name, which is there before the node's properties are
    function kind(n: PwNode): string {
        const name = n?.name ?? "";
        if (name.startsWith("bluez_input."))
            return "bt-mic";     // the earbuds' mic: using it drops them into call mode
        if (name.startsWith("bluez_"))
            return "bluetooth";
        if (/^alsa_(output|input)\.usb-/.test(name))
            return "usb";
        if (/hdmi|displayport|iec958/i.test(name))
            return "hdmi";
        if (/headphone/i.test(name))
            return "headphones";
        if (/headset/i.test(name))
            return n.isSink ? "headphones" : "jack-mic";
        return n?.isSink ? "speaker" : "mic";
    }

    function btAddr(n: PwNode): string {
        const m = (n?.name ?? "").match(/([0-9a-f]{2}[_:]){5}[0-9a-f]{2}/i);
        return m ? m[0].replace(/_/g, ":").toUpperCase() : "";
    }

    function btDevice(n: PwNode): var {
        const a = btAddr(n);
        return a ? (Bluetooth.devices.values.find(d => d.address.toUpperCase() === a) ?? null) : null;
    }

    function label(n: PwNode): string {
        if (!n)
            return "Nothing";
        switch (kind(n)) {
        case "bluetooth":
        case "bt-mic":
            return btDevice(n)?.name || nameOf(n);
        case "usb":
            return generic(n) ? (n.isSink ? "USB audio" : "USB mic") : usbName(n);
        case "headphones":
            return "Headphones";
        case "speaker":
            return "Speakers";
        case "mic":
            return "Laptop mic";
        case "jack-mic":
            return "Headset mic";
        case "hdmi": {
            const port = (n.name.match(/HDMI(\d)/) ?? [])[1];
            return root.outputs.filter(o => kind(o) === "hdmi").length > 1 && port ? "Monitor " + port : "Monitor";
        }
        }
        return nameOf(n);
    }

    function detail(n: PwNode): string {
        switch (kind(n)) {
        case "bluetooth": {
            const d = btDevice(n);
            return "Bluetooth" + (d?.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "");
        }
        case "bt-mic":
            return "Bluetooth · call mode, lower sound quality";
        case "usb":
            return generic(n) ? "USB · " + usbName(n) : "USB";
        case "headphones":
        case "jack-mic":
            return "Headphone jack";
        case "hdmi":
            return "HDMI / DisplayPort";
        }
        return "Built in";
    }

    function usbName(n: PwNode): string {
        return nameOf(n).replace(/ (Analog|Digital|Pro|Multichannel)\b.*$/, "");
    }

    // cheap USB dongles report their chip ("PCM2902 Audio Codec", "USB PnP Sound Device"), not what they are
    function generic(n: PwNode): bool {
        return /codec|pnp|sound device|usb audio|audio adapter/i.test(usbName(n));
    }

    function deviceIcon(n: PwNode): string {
        return ({ bluetooth: "headphones", "bt-mic": "headset_mic", usb: n?.isSink ? "speaker" : "mic_external_on", headphones: "headphones", speaker: "laptop_chromebook", hdmi: "desktop_windows", mic: "mic", "jack-mic": "headset_mic" })[kind(n)] ?? "speaker";
    }

    function refreshPorts(): void {
        ports.refresh();
    }

    function togglePicker(tab: string): void {
        root.pickerOpen = !(root.pickerOpen && root.pickerTab === tab);
        root.pickerTab = tab;
        saveSettings();
    }

    function setAutoSwitch(on: bool): void {
        root.autoSwitch = on;
        saveSettings();
    }

    // Auto-switching. New Bluetooth/USB outputs and USB mics take over when they connect, plugging into the
    // headphone jack moves sound there, and when the device in use goes away (or its port goes dead) the
    // best one left takes over. Bluetooth mics are never picked by themselves: they'd drop the earbuds
    // into call mode. A device that was gone for under 8 s doesn't count as new (Bluetooth profile
    // changes recreate the node), nor does anything present in the first seconds after the shell starts.
    property var seen: ({})   // device key -> 0 while present, else the time it left
    property bool armed: false

    function devKey(n: PwNode): string {
        const a = btAddr(n);
        return (a ? "bt:" + a : n.name) + (n.isSink ? ">" : "<");
    }

    function watchNew(nodes: var): void {
        const now = Date.now();
        const here = {};
        for (const n of nodes) {
            const k = devKey(n);
            here[k] = true;
            const left = root.seen[k];
            if (root.armed && root.autoSwitch && (left === undefined || (left > 0 && now - left > 8000)))
                takeOver(n);
            root.seen[k] = 0;
        }
        for (const k in root.seen)
            if (!here[k] && root.seen[k] === 0)
                root.seen[k] = now;
    }

    function takeOver(n: PwNode): void {
        const k = kind(n);
        if (n.isSink ? (k === "bluetooth" || k === "usb") : k === "usb") {
            pending.nodes = [...pending.nodes.filter(x => x && x.isSink !== n.isSink), n];
            pending.restart();
        }
    }

    function autoSet(n: PwNode): void {
        if (!n || n === (n.isSink ? root.sink : root.source))
            return;
        n.isSink ? setSink(n) : setSource(n);
        Ctl.caelestia("toaster", "info", [n.isSink ? "Sound output" : "Microphone", "Now using " + label(n), deviceIcon(n)]);
    }

    Timer {
        id: arm

        interval: 4000
        onTriggered: root.armed = true
    }

    // let WirePlumber finish setting the new node up before making it the default
    Timer {
        id: pending

        property var nodes: []   // one output and/or one input (a USB headset brings both)

        interval: 700
        onTriggered: {
            for (const n of nodes)
                root.autoSet(n);
            nodes = [];
        }
    }

    // the device in use is gone or unplugged: move to the best one that's left
    Timer {
        id: rescue

        interval: 1200
        onTriggered: {
            if (!root.armed || !root.autoSwitch)
                return;
            if (root.outputs.length && (!root.sink || !root.available(root.sink)))
                root.autoSet(root.outputs[0]);
            const ins = root.inputs.filter(n => root.kind(n) !== "bt-mic");
            if (ins.length && (!root.source || !root.available(root.source)))
                root.autoSet(ins[0]);
        }
    }

    function applyPorts(m: var): void {
        const old = root.avail;
        root.avail = m;
        // something just went into the headphone jack
        if (root.armed && root.autoSwitch)
            for (const n of root.sinks)
                if (kind(n) === "headphones" && old[n.name] === false && m[n.name] !== false)
                    autoSet(n);
        refreshPicker();
    }

    // port availability (headphone jack, HDMI): read with pactl now and whenever a card or device changes
    Process {
        id: ports

        function refresh(): void {
            portsSoon.restart();
        }

        command: ["sh", "-c", "pactl -f json list sinks; echo; echo @@; pactl -f json list sources"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const part of text.split("\n@@\n")) {
                    try {
                        for (const d of JSON.parse(part)) {
                            const p = (d.ports ?? []).find(x => x.name === d.active_port);
                            if (p)
                                m[d.name] = p.availability !== "not available";
                        }
                    } catch (e) {}
                }
                root.applyPorts(m);
            }
        }
    }

    Timer {
        id: portsSoon

        interval: 300
        onTriggered: ports.running = true
    }

    Process {
        id: events

        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                if (/'change' on card|'(new|remove)' on (sink|source) #/.test(line))
                    ports.refresh();
            }
        }
        onExited: eventsRetry.start()
    }

    Timer {
        id: eventsRetry

        interval: 3000
        onTriggered: events.running = true
    }

    function saveSettings(): void {
        settings.setText(JSON.stringify({ autoSwitch: root.autoSwitch, pickerOpen: root.pickerOpen, pickerTab: root.pickerTab }, null, 1));
    }

    FileView {
        id: settings

        path: Quickshell.env("HOME") + "/.local/share/rice/audio.json"
        atomicWrites: true
        printErrors: false   // no file yet = auto-switch on, picker closed
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.autoSwitch = d.autoSwitch ?? true;
                root.pickerOpen = d.pickerOpen ?? false;
                root.pickerTab = d.pickerTab ?? "out";
            } catch (e) {}
        }
    }
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? false

    function setVolume(v: real): void {
        if (!sink?.audio)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleMute(): void {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function setMic(v: real): void {
        if (!source?.audio)
            return;
        source.audio.muted = false;
        source.audio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleMic(): void {
        if (source?.audio)
            source.audio.muted = !source.audio.muted;
    }

    function setSink(n: PwNode): void {
        Pipewire.preferredDefaultAudioSink = n;
    }

    function setSource(n: PwNode): void {
        Pipewire.preferredDefaultAudioSource = n;
    }

    function nameOf(n: PwNode): string {
        return n?.description || n?.nickname || n?.name || "Unknown";
    }

    // devices on one sound card share a long prefix ("Core Ultra 200V Series Processors HD Audio ..."), so drop it
    function shortName(n: PwNode, list: var): string {
        if (n?.nickname)
            return n.nickname;
        const full = nameOf(n);
        const names = (list ?? []).map(x => nameOf(x));
        if (names.length < 2)
            return full;
        const words = names.map(x => x.split(" "));
        let common = 0;
        while (words.every(w => w.length > common + 1 && w[common] === words[0][common]))
            common++;
        return common >= 2 ? full.split(" ").slice(common).join(" ") : full;
    }

    function volumeIcon(v: real, m: bool): string {
        return m || v <= 0 ? "volume_off" : v < 0.34 ? "volume_mute" : v < 0.67 ? "volume_down" : "volume_up";
    }

    PwObjectTracker {
        objects: [root.sink, root.source, ...root.sinks, ...root.sources, ...root.streams].filter(n => n)
    }

    // the bar's visualiser: cava runs only while something is actually playing, and not on battery or in
    // efficiency mode (it redraws the bar every frame, even behind a fullscreen video)
    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)
    readonly property var bars: cava.values

    CavaProvider {
        id: cava

        bars: 10
    }

    LazyLoader {
        active: root.playing && !Power.still

        ServiceRef {
            service: cava
        }
    }
}
