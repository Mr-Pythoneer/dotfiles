#!/bin/sh
# render1.sh <url> <expected output file> [timeout]: open url in headless Chrome until the page has saved its output
url="$1"; out="$2"; rm -f "$out"
d=$(mktemp -d -p "$(dirname "$0")" chrome.XXXX)
google-chrome-stable --headless=new --no-sandbox --use-angle=swiftshader --enable-unsafe-swiftshader --hide-scrollbars --window-size=1920,1200 --user-data-dir="$d" "$url" >/dev/null 2>&1 &
pid=$!
i=0; while [ $i -lt ${3:-240} ]; do [ -s "$out" ] && break; sleep 1; i=$((i+1)); done
kill $pid 2>/dev/null; sleep 1; rm -rf "$d"
[ -s "$out" ] && echo "rendered $out after ${i}s" || echo "TIMEOUT $out"
