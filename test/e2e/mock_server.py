#!/usr/bin/env python3
"""Deterministic mock for wm's two upstreams (Yahoo prices + CVM news feed).

Routes by request path so a single `wm run` over a crafted wallet yields a fully
predictable glance:

  prices (path contains ".SA"):
    PETR4  -> flat 30d then a +30% jump  -> abnormal      -> LOOK
    MXRF11 -> gentle alternating series  -> calm           -> ignore
    XPTO3  -> Yahoo error payload        -> no price data  -> ignore
    others -> calm series                                  (price-only)
  news (path contains "news"):
    one CVM "VALE3 - Fato Relevante" item dated *today* (UTC) -> VALE3 fresh

Binds to 127.0.0.1:0 (ephemeral) and prints the chosen port on the first stdout
line so the shell harness can read it; then serves until killed.
"""
import json
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer


def prices_payload(closes):
    return json.dumps({
        "chart": {"error": None, "result": [
            {"indicators": {"quote": [{"close": closes}]}}
        ]}
    }).encode()


PETR4 = prices_payload([10.0] * 30 + [13.0])           # abnormal jump
CALM = prices_payload([10.0, 10.1] * 20)               # |z| ~ 1 -> calm
XPTO3 = json.dumps({"chart": {"error": "Not Found", "result": None}}).encode()


def news_payload():
    today = datetime.now(timezone.utc).strftime("%a, %d %b %Y 09:00:00 GMT")
    return (
        "<rss><channel>"
        f"<item><title>VALE3 - Fato Relevante sobre projeto</title><pubDate>{today}</pubDate></item>"
        "</channel></rss>"
    ).encode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):  # quiet
        pass

    def do_GET(self):
        path = self.path
        if "news" in path:
            body, ctype = news_payload(), "application/xml"
        elif "PETR4" in path:
            body, ctype = PETR4, "application/json"
        elif "XPTO3" in path:
            body, ctype = XPTO3, "application/json"
        else:  # MXRF11, VALE3, anything else -> calm prices
            body, ctype = CALM, "application/json"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    srv = HTTPServer(("127.0.0.1", 0), Handler)
    print(srv.server_address[1], flush=True)  # port on first line
    srv.serve_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
