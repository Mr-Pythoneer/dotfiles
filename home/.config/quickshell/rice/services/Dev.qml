pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// For the dashboard's Dev page: your git repos in ~/.local/src, GitHub notifications, and the busiest processes.
// Everything is fetched only while that page is open (refresh() is called then).
Singleton {
    id: root

    property var repos: []          // [{name, branch, changed, ahead, behind}]
    property var github: []         // [{repo, title, type}]
    property bool githubOk: true
    property var procs: []          // [{name, cpu, mem}]

    function refresh(): void {
        repoProc.running = true;
        ghProc.running = true;
    }

    function refreshProcs(): void {
        psProc.running = true;
    }

    Process {
        id: repoProc

        command: ["sh", "-c", "for d in \"$HOME\"/.local/src/*/; do [ -d \"$d/.git\" ] || continue; printf '@@%s\\n' \"$(basename \"$d\")\"; git -C \"$d\" status --porcelain=v2 --branch 2>/dev/null; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let cur = null;
                for (const line of text.split("\n")) {
                    if (line.startsWith("@@")) {
                        cur = { name: line.slice(2), branch: "", changed: 0, ahead: 0, behind: 0 };
                        out.push(cur);
                    } else if (!cur || !line) {
                        continue;
                    } else if (line.startsWith("# branch.head ")) {
                        cur.branch = line.slice(14);
                    } else if (line.startsWith("# branch.ab ")) {
                        const m = line.match(/\+(\d+) -(\d+)/);
                        if (m) {
                            cur.ahead = parseInt(m[1]);
                            cur.behind = parseInt(m[2]);
                        }
                    } else if (!line.startsWith("#")) {
                        cur.changed++;
                    }
                }
                root.repos = out;
            }
        }
    }

    Process {
        id: ghProc

        command: ["gh", "api", "notifications", "--jq", ".[] | [.repository.full_name, .subject.type, .subject.title] | @tsv"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.github = text.trim().split("\n").filter(l => l).slice(0, 8).map(l => {
                    const f = l.split("\t");
                    return { repo: f[0], type: f[1], title: f[2] };
                });
            }
        }
        onExited: code => root.githubOk = code === 0
    }

    Process {
        id: psProc

        command: ["ps", "-eo", "comm,%cpu,%mem", "--sort=-%cpu", "--no-headers"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.procs = text.trim().split("\n").slice(0, 6).map(l => {
                    const f = l.trim().split(/\s+/);
                    const mem = parseFloat(f.pop()), cpu = parseFloat(f.pop());
                    return { name: f.join(" "), cpu: cpu, mem: mem };
                });
            }
        }
    }
}
