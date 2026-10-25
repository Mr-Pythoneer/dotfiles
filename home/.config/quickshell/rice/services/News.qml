pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Headlines from the newest news-brief edition (the summary points at the top of the page)
Singleton {
    id: root

    property string path: ""
    property string title: ""
    property string built: ""
    property var headlines: []

    function decode(s: string): string {
        return s.replace(/<[^>]+>/g, "").replace(/&#x27;|&#39;/g, "'").replace(/&quot;/g, "\"").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#x2F;/g, "/");
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/news-brief/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.path = d.path ?? "";
                root.built = d.built ?? "";
            } catch (e) {}
        }
    }

    FileView {
        path: root.path
        onLoaded: {
            const t = text();
            const h1 = t.match(/<h1>([^<]*)<\/h1>/);
            root.title = h1 ? root.decode(h1[1]) : "News";
            const out = [];
            const re = /<li><b>([\s\S]*?)<\/b>/g;
            let m;
            while ((m = re.exec(t)) !== null && out.length < 8)
                out.push(root.decode(m[1]));
            root.headlines = out;
        }
    }
}
