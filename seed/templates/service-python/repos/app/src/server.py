"""__ORG__-app — the initial HTTP service of the __ORG__ organization.

It was born from aegis's `service-python` template and from that moment
on it is YOURS: the template never touches it again. Zero external
dependencies on purpose: an empty dependency tree is a tree that does
not rot, and nothing here has to be explained to Trivy.

The only thing the platform asks of this process is that it listen on
the port the contract declares (8080, and on 0.0.0.0 — a server bound to
localhost is unreachable from the kubelet's probe and from the edge) and
answer /healthz, which the readinessProbe polls.
"""
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8080


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):                                # noqa: N802 (stdlib name)
        body = respond(self.path)
        self.send_response(200)
        self.send_header("content-type", "text/plain; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # The default writes to stderr with a timestamp of its own; the
        # pod's log already carries one. One line, one request.
        print(f"{self.address_string()} {fmt % args}")


def respond(path):
    """The whole app, kept apart from the server so the tests can call it
    without binding a port."""
    if path == "/healthz":
        return b"ok\n"
    return (f"__ORG__ — initial app of the service-python template, "
            f"pod {os.uname().nodename}\n").encode()


def main():
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
