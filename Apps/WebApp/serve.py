"""Local WebApp development host; forwards /api/ to a separate ReceptionDesk.

Deployment can serve the static build with an equivalent reverse-proxy rule.
This helper is not a node runtime or an internet relay.
"""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
DESK = os.environ.get('PARVI_RECEPTION_DESK_URL', 'http://127.0.0.1:8765').rstrip('/')


class WebAppHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/'):
            self.proxy()
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api/'):
            self.proxy()
        else:
            self.send_error(405)

    def proxy(self):
        length = int(self.headers.get('Content-Length', 0))
        if length < 0 or length > 1024:
            self.send_error(413)
            return
        body = self.rfile.read(length) if self.command == 'POST' else None
        request = urllib.request.Request(
            DESK + self.path, data=body, method=self.command,
            headers={'Content-Type': self.headers.get('Content-Type', 'application/json')})
        try:
            response = urllib.request.urlopen(request, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        except urllib.error.URLError:
            self.send_error(502, 'Reception Desk unavailable')
            return
        with response:
            data = response.read()
            self.send_response(response.status)
            self.send_header('Content-Type', response.headers.get('Content-Type', 'application/json'))
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(data)


if __name__ == '__main__':
    address = ('127.0.0.1', int(os.environ.get('PARVI_WEBAPP_PORT', '8766')))
    handler = partial(WebAppHandler, directory=str(ROOT / 'builds/WebApp'))
    print(f'WebApp: http://{address[0]}:{address[1]} · Reception Desk: {DESK}', flush=True)
    ThreadingHTTPServer(address, handler).serve_forever()
