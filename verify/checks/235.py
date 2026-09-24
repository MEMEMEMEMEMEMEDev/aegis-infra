"""Check 235 — every path a base's nginx writes at run time is one its runtime test mounts.

2026-09-24, the second cloud VM, the first clean install to run the
base-images smoke test (b76f001, 2026-09-20) on the nginx member: the
image built, scanned clean, and died at start-up with
`open() "/tmp/nginx.pid" failed (30: Read-only file system)`. Its
nginx.conf puts the pid and every temp path under /tmp (tenant pods run
read-only); its runtime-test.yaml declared /var/cache/nginx and /run.
The php member, written later, declared all three. The house instance
never saw it: its nginx was signed before the smoke test existed.

The runtime test is also the base's contract with its consumers (the
paths every consumer mounts as emptyDir), so the two files disagreeing
is a consumer's pod dying after the signature.
"""
import os
import re
import sys

ROOT = sys.argv[1]
B = os.path.join(ROOT, "seed", "platform", "base-images")
findings = []
checked = 0

DIRECTIVE = re.compile(r"^\s*(pid|[a-z_]+_temp_path)\s+(/\S+?)\s*;", re.M)


def writable(rt_text):
    out, on = [], False
    for line in rt_text.splitlines():
        if re.match(r"^writable:\s*$", line):
            on = True
            continue
        if re.match(r"^[a-z]", line):
            on = False
        m = re.match(r"^\s*-\s*(\S+)\s*$", line) if on else None
        if m:
            out.append(m.group(1).rstrip("/"))
    return out


def under(path, roots):
    return any(path == r or path.startswith(r + "/") for r in roots)


members = sorted(d for d in os.listdir(B) if os.path.isdir(os.path.join(B, d)))
for m in members:
    conf = os.path.join(B, m, "nginx.conf")
    rt = os.path.join(B, m, "runtime-test.yaml")
    if not os.path.isfile(conf):
        continue
    if not os.path.isfile(rt):
        findings.append(f"base-images/{m} ships an nginx.conf and no runtime-test.yaml: nothing declares what it writes")
        continue
    src = "\n".join(l for l in open(conf, encoding="utf-8").read().splitlines()
                    if not re.match(r"^\s*#", l))
    roots = writable(open(rt, encoding="utf-8").read())
    for d, path in DIRECTIVE.findall(src):
        checked += 1
        if not under(path, roots):
            findings.append(f"base-images/{m}: nginx writes `{d} {path}` at run time and runtime-test.yaml "
                            f"declares only {roots or 'nothing'} writable: under a read-only root the "
                            "pod dies at start-up, after the signature, in every consumer")

if checked == 0:
    findings.append("no base's nginx.conf declared a pid or a temp path: the scan read nothing "
                    "(the seed's nginx and php members both do)")

for f in findings:
    print(f)
print(f"SCOPE: {checked} run-time paths of {len(members)} base members read against their runtime tests")
