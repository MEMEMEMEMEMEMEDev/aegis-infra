"""Check 268 — aegis vulns and the round read the watch's books.

Since plan/21 the door lets findings in as debt with a due date, and the
watch keeps the books (check 267). The round (`aegis check`) had two
answers for what the watch found — no fixable CVE green, any failure — so
every round would have gone red over debt the platform accepted on
purpose, and a red nobody can act on is a red nobody reads.

`aegis vulns` reads the books and the round reads `aegis vulns`. This
sidecar LOADS libexec/aegis-vulns with PLATFORM_DIR at a clone of a bare
remote, injects the watch's heartbeat, and asserts:
  · the books are read from the REMOTE (the clone's working tree holds
    an older copy that says something else);
  · debt inside its window → rc 0, the image's step `done` with
    attention; overdue or exploited → rc 1; an unmeasured image, a
    silent watch, books never written → rc 2;
And it RUNS the round's reader (the heredoc in libexec/aegis-check, fed
by `aegis_exec vulns --json`) on those documents.

THE HEARTBEAT IS READ THROUGH A HEADLESS SERVICE (2026-10-02, found
re-reading before the series): vmsingle's clusterIP is the word `None`
here, and the first aegis-vulns read only the clusterIP — so on every
instance it could not read the watch and exited 2 for ever. The cases
above inject the heartbeat and could not see it. So read_watch() is also
RUN, with a `kubectl` that answers like the cluster does (clusterIP None,
an endpoint) against a local HTTP server standing in for vmsingle.
"""
import contextlib
import http.server
import threading
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import datetime

ROOT = os.path.abspath(sys.argv[1])
VULNS = os.path.join(ROOT, "libexec", "aegis-vulns")
CHECK = os.path.join(ROOT, "libexec", "aegis-check")
findings = []
os.environ.update({"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
                   "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"})

if not os.path.isfile(VULNS):
    print("libexec/aegis-vulns is missing: nothing reads the books")
    sys.exit(0)

H = "# h\n# STATE|IMAGE|KIND|DIGEST|CVE|SEVERITY|PKG|INSTALLED|FIXED|PKGPATH|SINCE|CLOCK|DUE|FIXER\n"
DEBT = "debt|python|mirror|sha256:1|CVE-2026-1|HIGH|libssl3|1|2||2026-10-01|published|2026-10-31|upstream\n"
OVER = "overdue|python|mirror|sha256:1|CVE-2026-2|CRITICAL|libc|1|2||2026-09-01|published|2026-09-16|upstream\n"
EXPL = "exploited|node|base|sha256:2|CVE-2026-3|HIGH|curl|1|2||2026-09-30|published|2026-10-30|the base loop\n"
CLEAN = "clean|garage|mirror|sha256:3||||||||||upstream\n"
UNME = "unmeasured|garage|mirror|sha256:3||||||the watch could not scan it this morning||||upstream\n"
TODAY = datetime.date(2026, 10, 5)


def g(cwd, *a):
    return subprocess.run(["git", "-C", str(cwd), *a], capture_output=True, text=True, check=True).stdout


def load(platform):
    os.environ["AEGIS_ROOT"] = ROOT
    os.environ["PLATFORM_DIR"] = platform
    loader = importlib.machinery.SourceFileLoader("aegis_vulns_268", VULNS)
    spec = importlib.util.spec_from_loader("aegis_vulns_268", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


def run(m, watch):
    from aegis import outcomes
    steps = outcomes.Steps(json_mode=True)
    out = io.StringIO()
    rc = None
    with contextlib.redirect_stdout(out):
        try:
            m.show(steps, False, today=TODAY, watch=watch)
        except SystemExit as e:
            rc = e.code
    return rc, json.loads(out.getvalue() or "{}")


reader = None
src = open(CHECK, encoding="utf-8").read()
mm = re.search(r'vulns_lines=\$\(VULNS_JSON="\$vulns_json" python3 - <<\'PY\'\n(.*?)\nPY\n', src, re.S)
if not mm:
    findings.append("aegis check does not read the books through `aegis vulns --json` (the reader heredoc is gone)")
else:
    reader = mm.group(1)
if not re.search(r"^\s*vulns_json=\$\(aegis_exec vulns --json", src, re.M):
    findings.append("aegis check does not call `aegis_exec vulns --json`: it keeps arithmetic of its own")
if "aegis_image_fixable_vulns" in "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#")):
    findings.append("aegis check still judges by aegis_image_fixable_vulns: any finding is a failure again")


def read_round(doc):
    if reader is None:
        return []
    p = subprocess.run([sys.executable, "-c", reader], capture_output=True, text=True,
                       env={**os.environ, "VULNS_JSON": json.dumps(doc)})
    return [l.split("|", 1)[0] for l in p.stdout.splitlines()]


fresh = {"heartbeat": time.time() - 3 * 3600, "written": 1.0}
cases = 0
with tempfile.TemporaryDirectory() as tmp:
    remote, clone = os.path.join(tmp, "r.git"), os.path.join(tmp, "platform")
    subprocess.run(["git", "init", "--quiet", "--bare", "-b", "main", remote], check=True)
    subprocess.run(["git", "clone", "--quiet", remote, clone], check=True, capture_output=True)
    os.makedirs(os.path.join(clone, "image-watch"))
    m = load(clone)

    # No books at all: COULD NOT EVALUATE.
    open(os.path.join(clone, "README"), "w").write("x\n")
    g(clone, "add", "README"); g(clone, "commit", "--quiet", "-m", "0"); g(clone, "push", "--quiet", "-u", "origin", "main")
    rc, doc = run(m, fresh); cases += 1
    if rc != 2:
        findings.append(f"no books in the repo gave rc {rc}, not 2: an instance the watch never looked at reads as clean")

    def publish(text):
        other = os.path.join(tmp, "watch")
        if not os.path.isdir(other):
            subprocess.run(["git", "clone", "--quiet", remote, other], check=True, capture_output=True)
            os.makedirs(os.path.join(other, "image-watch"), exist_ok=True)
        g(other, "pull", "--quiet")
        open(os.path.join(other, "image-watch", "ledger.txt"), "w").write(text)
        g(other, "add", "image-watch/ledger.txt"); g(other, "commit", "--quiet", "-m", "books"); g(other, "push", "--quiet")

    # The clone's working tree says «overdue»; the remote says «debt only».
    open(os.path.join(clone, "image-watch", "ledger.txt"), "w").write(H + OVER)
    publish(H + DEBT + CLEAN)
    rc, doc = run(m, fresh); cases += 1
    if rc != 0:
        findings.append(f"debt inside its window (on the remote) gave rc {rc}, not 0"
                        + (" — the working tree was read instead of the remote" if rc == 1 else ""))
    st = {s["step"]: s for s in doc.get("steps", [])}
    if st.get("image:python", {}).get("state") != "done" or not st.get("image:python", {}).get("attention"):
        findings.append("debt inside its window is not a `done` step with attention")
    kinds = read_round(doc)
    if "NOTICE" not in kinds or "BAD" in kinds:
        findings.append(f"the round reads debt inside its window as {kinds}, not as a notice")

    publish(H + DEBT + OVER + EXPL)
    rc, doc = run(m, fresh); cases += 1
    if rc != 1:
        findings.append(f"overdue and exploited findings gave rc {rc}, not 1")
    if read_round(doc).count("BAD") < 2:
        findings.append("the round does not fail on an overdue image and on an exploited one")

    publish(H + DEBT + UNME)
    rc, doc = run(m, fresh); cases += 1
    if rc != 2:
        findings.append(f"an image the watch could not scan gave rc {rc}, not 2")
    if "NOTEVAL" not in read_round(doc):
        findings.append("the round does not say COULD NOT EVALUATE for an unmeasured image")

    publish(H + DEBT + CLEAN)
    rc, doc = run(m, {"heartbeat": time.time() - 5 * 86400, "written": 1.0}); cases += 1
    if rc != 2:
        findings.append(f"a watch silent for 5 days gave rc {rc}, not 2: yesterday's books read as today's")
    if "BAD" not in read_round(doc):
        findings.append("the round does not say the watch STOPPED when its heartbeat is 5 days old")
    rc, doc = run(m, {"heartbeat": time.time() - 3600, "written": 0.0}); cases += 1
    if rc != 2:
        findings.append(f"a run that could not write the books gave rc {rc}, not 2")
    rc, doc = run(m, {"error": "the vmsingle Service was not found"}); cases += 1
    if rc != 2:
        findings.append(f"a heartbeat that could not be read gave rc {rc}, not 2")

    publish(H + CLEAN)
    rc, doc = run(m, fresh); cases += 1
    if rc != 0:
        findings.append(f"clean books with a fresh watch gave rc {rc}, not 0")
    if "TOTAL" not in read_round(doc) or "BAD" in read_round(doc):
        findings.append("the round does not reach its green on clean books")

# ── the heartbeat, read the way the cluster serves it ──
class _VM(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"data": {"result": [{"metric": {}, "value": [0, "1790000000"]}]}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def log_message(self, *_a):
        pass


srv = http.server.HTTPServer(("127.0.0.1", 0), _VM)
threading.Thread(target=srv.serve_forever, daemon=True).start()
with tempfile.TemporaryDirectory() as tmp:
    kc = os.path.join(tmp, "kubectl")
    with open(kc, "w") as f:
        f.write("#!/bin/sh\ncase \"$*\" in\n"
                "  *endpoints*) printf 127.0.0.1 ;;\n"
                "  *clusterIP*) printf None ;;\n"
                f"  *ports*) printf {srv.server_address[1]} ;;\n"
                "  *) exit 1 ;;\nesac\n")
    os.chmod(kc, 0o755)
    old = os.environ["PATH"]
    os.environ["PATH"] = tmp + os.pathsep + old
    try:
        w = load(tmp).read_watch()
    finally:
        os.environ["PATH"] = old
        srv.shutdown()
    cases += 1
    if w.get("heartbeat") != 1790000000.0:
        findings.append(f"with vmsingle headless (clusterIP None, an endpoint) the heartbeat is not read ({w.get('error') or w}): aegis vulns exits 2 on every instance")

for x in findings:
    print(x)
print(f"SCOPE: read_watch run through a headless Service; aegis vulns loaded against a bare remote and a clone, {cases} situations (no books, remote≠working tree, debt, overdue+exploited, unmeasured, silent, not written, unreadable heartbeat, clean); the round's reader run on each document")
