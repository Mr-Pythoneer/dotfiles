# Serves a directory on 127.0.0.1 and saves POST /save?name=x.png bodies into ./out
import http.server, os, sys, urllib.parse
root, port = sys.argv[1], int(sys.argv[2])
os.chdir(root); os.makedirs("out", exist_ok=True)
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        name = os.path.basename(urllib.parse.parse_qs(u.query).get("name", ["out.png"])[0])
        data = self.rfile.read(int(self.headers["Content-Length"]))
        open(os.path.join("out", name), "wb").write(data)
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
