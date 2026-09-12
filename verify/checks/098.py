"""Check 098 — the console refuses what it cannot attribute.

Two attacks reach a server on 127.0.0.1 from the internet, and neither
of them looks like an attack from inside the process: the request is
well-formed, it arrives over loopback, and the operator is sitting in
front of the browser that sent it.

  · DNS REBINDING gets the read-only console. A page keeps its own
    origin while its name starts resolving to 127.0.0.1, so same-origin
    policy is not violated — it simply does not apply. The only thing
    that gives it away is the `Host` header.

  · CSRF gets the write. Cross-origin form POSTs have never been blocked
    by same-origin policy. The defence is a token the attacking page
    cannot READ, because it can send a request and not see the answer.

The rules live in a pure function so they can be exercised, and this
runs them over a table of hostile requests. The second half matters as
much as the first: a guard that refuses EVERYTHING would satisfy every
line of the table and serve nobody, so the legitimate request has to be
let through.

And then the rules have to be CONSULTED. A module that is right and
unused is the most reassuring kind of wrong, so the server's own source
is read and every method that answers a request has to ask.
"""
import ast
import os
import sys

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
SERVER = os.path.join(ROOT, "libexec", "aegis-console")

try:
    from aegis import guard
except ImportError:
    print("SCOPE: there is no lib/aegis/guard.py: this check has no subject")
    sys.exit(0)

PORT = 7391


class Headers(dict):
    """Headers the way http.server hands them over: case-insensitive
    lookup with a default, and missing means None."""
    def get(self, key, default=None):
        for k, v in self.items():
            if k.lower() == key.lower():
                return v
        return default


def h(**kw):
    return Headers({k.replace("_", "-"): v for k, v in kw.items()})


GOOD = h(Host=f"127.0.0.1:{PORT}", Origin=f"http://127.0.0.1:{PORT}",
         Sec_Fetch_Site="same-origin")

# Each row: what it is, and the request that must be refused.
HOSTILE_READS = [
    ("a name that resolves here from the internet (DNS rebinding)",
     h(Host="evil.test")),
    ("a name that merely STARTS with the loopback address",
     h(Host=f"127.0.0.1.evil.test:{PORT}")),
    ("a request with no Host header at all", h()),
    ("the right name on somebody else's port", h(Host="127.0.0.1:1")),
]

HOSTILE_WRITES = [
    ("a GET that changes something — which a link in another page can send",
     "GET", GOOD, "the-token"),
    ("a POST with no Origin: it did not come from this console's page",
     "POST", h(Host=f"127.0.0.1:{PORT}"), "the-token"),
    ("a form on another site posting here (CSRF)",
     "POST", h(Host=f"127.0.0.1:{PORT}", Origin="http://evil.test"), "the-token"),
    ("a POST the browser itself says came from another site",
     "POST", h(Host=f"127.0.0.1:{PORT}", Origin=f"http://127.0.0.1:{PORT}",
               Sec_Fetch_Site="cross-site"), "the-token"),
    ("a POST carrying no token", "POST", GOOD, ""),
    ("a POST carrying a token that is not this console's", "POST", GOOD, "otro"),
]

findings = []

for what, headers in HOSTILE_READS:
    if not guard.why_not_read(headers, PORT):
        findings.append(f"{what} is answered: everything the round can see about this "
                        f"instance goes to whoever asked")

for what, method, headers, sent in HOSTILE_WRITES:
    if not guard.why_not_write(method, headers, "the-token", sent):
        findings.append(f"{what} is allowed to write: something lands in the operator's "
                        f"repository because they visited a page")

# A server with no token of its own must refuse rather than wave
# everything through: a defence that silently does not exist is worse
# than one that was never claimed.
if not guard.why_not_write("POST", GOOD, "", "anything"):
    findings.append("a console with no token of its own accepts a write anyway: the "
                    "defence is absent and nothing says so")

# THE OTHER HALF. Without it a guard that refused every request would
# pass every line above.
if guard.why_not_read(h(Host=f"127.0.0.1:{PORT}"), PORT):
    findings.append("the console refuses its own loopback address: it would refuse "
                    "everybody, which passes every hostile row above and serves nobody")
if guard.why_not_read(h(Host=f"localhost:{PORT}"), PORT):
    findings.append("the console refuses `localhost`, which is what a browser sends when "
                    "the operator types it")
if guard.why_not_write("POST", GOOD, "the-token", "the-token"):
    findings.append("a POST from this console's own page, carrying its own token, is "
                    "refused: the console cannot write at all")

# ── and the rules have to be consulted ───────────────────────────────
if not os.path.isfile(SERVER):
    findings.append("there is no server to guard")
else:
    with open(SERVER, encoding="utf-8") as fh:
        tree = ast.parse(fh.read())
    handlers, asked = {}, set()
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name.startswith("do_"):
            handlers[node.name] = node
            for inner in ast.walk(node):
                if (isinstance(inner, ast.Attribute)
                        and inner.attr in ("why_not_read", "why_not_write")):
                    asked.add(node.name)
    if not handlers:
        findings.append("the server answers no HTTP method: there is nothing to guard")
    # do_HEAD delegating to do_GET is the one legitimate exception, and
    # it is named rather than assumed: a handler that answers on its own
    # and asks nobody is exactly what this is looking for.
    for name, node in sorted(handlers.items()):
        if name in asked:
            continue
        delegates = any(isinstance(inner, ast.Attribute) and inner.attr in handlers
                        for inner in ast.walk(node))
        if not delegates:
            findings.append(f"`{name}` answers requests and never asks the guard: the "
                            f"rules can be perfect and unused, which is the most "
                            f"reassuring kind of wrong")

for f in findings:
    print(f)
print(f"SCOPE: {len(HOSTILE_READS)} hostile read(s) and {len(HOSTILE_WRITES)} hostile "
      f"write(s) refused, the legitimate pair allowed, {len(handlers)} handler(s) read")
