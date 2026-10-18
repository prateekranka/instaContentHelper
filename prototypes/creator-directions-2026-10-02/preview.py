"""Serve only this throwaway prototype on loopback; no app APIs are connected."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from functools import partial
from pathlib import Path
from argparse import ArgumentParser
from socketserver import TCPServer
from urllib.parse import unquote, urlsplit


class LoopbackHTTPServer(ThreadingHTTPServer):
    def server_bind(self):
        # This static preview has a fixed loopback host; no reverse DNS is needed.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


class PreviewHandler(SimpleHTTPRequestHandler):
    # Keep test dependencies, runner reports, and configuration off the preview.
    public_files = {"/", "/index.html", "/styles.css", "/details.css", "/app.js"}

    def public_request(self):
        return unquote(urlsplit(self.path).path) in self.public_files

    def do_GET(self):
        if not self.public_request():
            self.send_error(404)
            return
        super().do_GET()

    def do_HEAD(self):
        if not self.public_request():
            self.send_error(404)
            return
        super().do_HEAD()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


parser = ArgumentParser(description="Serve the ContentHelper prototype on loopback.")
parser.add_argument("--port", type=int, default=0)
args = parser.parse_args()
prototype_dir = Path(__file__).resolve().parent
server = LoopbackHTTPServer(("127.0.0.1", args.port), partial(PreviewHandler, directory=str(prototype_dir)))
print(f"PROTOTYPE_URL=http://127.0.0.1:{server.server_port}/index.html?variant=A", flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    server.server_close()
