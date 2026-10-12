"""Check 281 — a webhook delivery is waited for the way GitHub delivers.

GitHub does not re-deliver on its own. Phase 60 learned it in the P1.5
audit (2026-07-18) and re-delivered inside its wait; phase 35 kept the
old shape —redeliver once, then poll that one finished delivery— and lost
alpha-ubuntu on 2026-10-12: the redeliver hit a 502 («failed to connect
to host») four seconds after cloudflared connected, the gate re-read that
dead delivery for 180 s, and the same redeliver by hand, minutes later,
answered 200. One helper for both: lib/access.sh's hook_delivery_2xx.

Driven, against a fake GitHub (a gh that keeps a list of deliveries and,
on every redeliver, appends a new one that is in flight for a read and
then answers what the scenario says); the --jq filters run through the
real jq, as gh runs them:
  · a failed redelivery is re-delivered, and the next 200 passes;
  · a 400 stops at once, without re-delivering (an HMAC out of sync does
    not heal);
  · an OLD 2xx (not newer than since_id) never passes;
  · a delivery in flight is waited for, not re-delivered;
  · an edge that never answers is re-delivered at a bounded pace, and
    the wait ends;
  · with an event, a 2xx of another event does not count.
Read, comment-stripped: phase 35 and phase 60 gate on the helper, each
with a since_id taken BEFORE the delivery it wants measured.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(sys.argv[1])
findings = []
scope = []


def code(rel):
    try:
        text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    except OSError:
        findings.append(f"{rel} is missing")
        return ""
    lines = [l for l in text.splitlines() if not re.match(r"^\s*#", l)]
    return "\n".join(lines).replace("\\\n", " ")


# ── read: the two phases ────────────────────────────────────────────────
p35 = code("init/phases/35-gitops.sh")
m = re.search(r'\bgate(?:_diag)?\s+"webhook-redeliver-2xx"(.*?)(?:\n\s*\n|\n\s*EDGE_VERDICT)', p35, re.S)
g35 = m.group(1) if m else ""
if "hook_delivery_2xx" not in g35:
    findings.append("phase 35's webhook-redeliver-2xx does not wait through hook_delivery_2xx: a redelivery that "
                    "fails is read again until the timeout, and never sent again")
elif not re.search(r'hook_delivery_2xx\s+"\$GH_OWNER/\$PLATFORM_REPO"\s+"\$HOOK_ID"\s+""\s+"\$DELIVERY_ID"', g35):
    findings.append("phase 35 waits without the id of the delivery it re-sent as since_id: an old 2xx would pass it")
if re.search(r'\bpoll\b', g35):
    findings.append("phase 35's webhook-redeliver-2xx still polls one finished delivery")
scope.append("phase 35 read")

p60 = code("init/phases/60-webhook.sh")
m = re.search(r'gate_diag\s+"delivery-push-2xx"(.*?)\nfi', p60, re.S)
g60 = m.group(1) if m else ""
if not re.search(r'hook_delivery_2xx\s+"\$GH_OWNER/\$APP_REPO"\s+"\$HOOK_ID"\s+push\s+"\$PUSH_SINCE"', g60):
    findings.append("phase 60's delivery-push-2xx does not wait through hook_delivery_2xx for a push newer than "
                    "$PUSH_SINCE")
since_at = p60.find('PUSH_SINCE="$(hook_newest_delivery')
push_at = p60.find("git push")
if since_at < 0 or push_at < 0 or since_at > push_at:
    findings.append("phase 60 takes PUSH_SINCE after the push (or not at all): the push's own delivery could be "
                    "taken for an old one, or an old 2xx for the push's")
scope.append("phase 60 read")

# ── driven: the helper, against a fake GitHub ───────────────────────────
FAKE_GH = r'''#!/usr/bin/env python3
import json, os, re, subprocess, sys
a = sys.argv[1:]
st_path = os.environ["FAKE_STATE"]
st = json.load(open(st_path))
if a[:3] == ["api", "-X", "POST"]:
    m = re.search(r"/deliveries/(\d+)/attempts$", a[3])
    old = next(d for d in st["deliveries"] if d["id"] == int(m.group(1)))
    st["redelivered"].append(old["id"])
    nxt = st["queue"].pop(0) if st["queue"] else st["default"]
    st["deliveries"].insert(0, {"id": max(d["id"] for d in st["deliveries"]) + 1, "event": old["event"],
                                "status_code": None, "pending": 1, "then": nxt})
    json.dump(st, open(st_path, "w"))
    sys.exit(0)
filt = a[a.index("--jq") + 1]
view = [{k: d[k] for k in ("id", "event", "status_code")} for d in st["deliveries"]]
for d in st["deliveries"]:
    if d.get("pending"):
        d["pending"] -= 1
    elif "then" in d:
        d["status_code"] = d.pop("then")
json.dump(st, open(st_path, "w"))
p = subprocess.run(["jq", "-r", filt], input=json.dumps(view), capture_output=True, text=True)
sys.stdout.write(p.stdout)
sys.exit(p.returncode)
'''

if not shutil.which("jq"):
    findings.append("`jq` is not on this machine: the delivery wait cannot be driven here")
else:
    with tempfile.TemporaryDirectory() as tmp:
        bindir = os.path.join(tmp, "bin")
        os.makedirs(bindir)
        with open(os.path.join(bindir, "gh"), "w") as f:
            f.write(FAKE_GH)
        os.chmod(os.path.join(bindir, "gh"), 0o755)
        state = os.path.join(tmp, "state.json")
        lib = os.path.join(ROOT, "lib", "access.sh")

        def drive(name, deliveries, queue, event, since, timeout, want_rc, redeliveries, default=502, poll="0.2"):
            with open(state, "w") as f:
                json.dump({"deliveries": deliveries, "queue": queue, "default": default, "redelivered": []}, f)
            script = (f'log_warn() {{ printf "%s\\n" "$*" >&2; }}; source "{lib}"; '
                      f'hook_delivery_2xx o/r 7 "{event}" {since} {timeout}')
            env = dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"], FAKE_STATE=state,
                       AEGIS_HOOK_POLL_S=poll, AEGIS_HOOK_REDELIVER_S="1")
            t0 = time.time()
            try:
                p = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env, timeout=60)
                rc = p.returncode
            except subprocess.TimeoutExpired:
                findings.append(f"{name}: the wait never ended")
                return
            took = time.time() - t0
            red = json.load(open(state))["redelivered"]
            if (rc == 0) != (want_rc == 0):
                findings.append(f"{name}: hook_delivery_2xx {'passed' if rc == 0 else 'failed'} (rc {rc})")
            if not redeliveries(red):
                findings.append(f"{name}: re-delivered {red}")
            return took

        D = lambda i, c, e="push": {"id": i, "event": e, "status_code": c}

        drive("a redelivery that failed (alpha-ubuntu, 2026-10-12)",
              [D(101, 502), D(100, 530)], [200], "", 100, 20, 0, lambda r: r == [101])
        took = drive("a 400 (an HMAC out of sync)", [D(101, 400)], [], "", 100, 20, 1, lambda r: r == [])
        if took is not None and took > 5:
            findings.append(f"a 400 kept the wait going for {took:.0f}s: an HMAC out of sync does not heal "
                            "by waiting, and the diagnosis arrives at the timeout instead of now")
        drive("an old 2xx, not newer than since_id", [D(100, 200)], [], "", 100, 3, 1, lambda r: r == [])
        drive("a delivery in flight",
              [{"id": 101, "event": "push", "status_code": None, "pending": 2, "then": 200}],
              [], "", 100, 20, 0, lambda r: r == [])
        # polled fast, so that only the pace (once a second here) keeps the count down: 0..4 s → at most 5
        drive("an edge that never answers", [D(101, 502)], [], "", 100, 4, 1, lambda r: 2 <= len(r) <= 6,
              poll="0.02")
        drive("a 2xx of another event", [D(102, 200, "ping"), D(101, 502)], [200], "push", 100, 20, 0,
              lambda r: r == [101])
        scope.append("the helper driven over six deliveries' fates against a fake GitHub with the real jq")

for x in findings:
    print(x)
print(f"SCOPE: {'; '.join(scope)}")
