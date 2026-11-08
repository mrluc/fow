"""Fixture: python3 docs/adr/adr-002/loopback-assets.py (loopback only)."""
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        assets = {
            "/green.svg": ("image/svg+xml", b"<svg xmlns='http://www.w3.org/2000/svg' width='32' height='32'><rect width='32' height='32' fill='rgb(0,180,0)'/></svg>"),
            "/script.js": ("application/javascript", b"window.loopbackScript=true;"),
            "/style.css": ("text/css", b"body{--loopback-css:loaded}"),
        }
        if path not in assets:
            self.send_error(404)
            return
        mime, data = assets[path]
        self.send_response(200)
        self.send_header("Content-Type", mime)
        origin = self.headers.get("Origin", "https://fow-images.invalid")
        if origin in ("https://fow-images.invalid", "http://127.0.0.1:47180"):
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

HTTPServer(("127.0.0.1", 47186), Handler).serve_forever()
