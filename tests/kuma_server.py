#!/usr/bin/env python3
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer


output_path = sys.argv[1]


class Handler(BaseHTTPRequestHandler):
    requests_seen = 0

    def do_GET(self):
        with open(output_path, "a", encoding="utf-8") as output:
            output.write(self.path + "\n")
        self.send_response(200)
        self.end_headers()
        Handler.requests_seen += 1
        if Handler.requests_seen >= 2:
            threading.Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, _format, *_args):
        pass


HTTPServer(("0.0.0.0", 18080), Handler).serve_forever()
