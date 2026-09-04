"""Scanner of check 188 — aegis-data implements the dump contract that
services.yaml declares, for EVERY dumped type and not only postgres.

Comments are stripped before scanning: the file documents the very bugs
this guards against, and a scanner that read the prose would find the
words it is looking for inside an explanation of why they must be there.
"""
import os
import re
import sys

ROOT = sys.argv[1]
DATA = os.path.join(ROOT, "libexec", "aegis-data")


def sin_prosa(text):
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


fallos = []
hechos = 0

if not os.path.exists(DATA):
    print("libexec/aegis-data does not exist: this check has no subject")
    print("__COUNT__ 0", file=sys.stderr)
    sys.exit(0)

s = sin_prosa(open(DATA, encoding="utf-8").read())

# 1 — the set of dumped types is DERIVED from the catalogue, not a
# hard-coded «postgres». A `_dump_types` that stopped reading
# backup.method / component would silently narrow to nothing.
hechos += 1
m = re.search(r"\ndef _dump_types\(.*?(?=\ndef )", s, re.S)
if not m:
    fallos.append("there is no _dump_types(): the types aegis-data dumps are no "
                  "longer derived from services.yaml, so a fourth stateful type is "
                  "a silent gap")
else:
    body = m.group(0)
    if '"datos"' not in body or '"dump"' not in body:
        fallos.append("_dump_types() no longer selects on component 'datos' AND "
                      "backup.method 'dump': it would admit the wrong types or none")

# 2 — THE R1 REGRESSION GUARD. The cluster-vs-contract comparison must
# count dump-type services as declared, or a mongodb StatefulSet reads
# as «alive and undeclared» and aborts the backup of EVERY organization.
hechos += 1
mdec = re.search(r"declared\s*=\s*\{[^}]*for\s+\w+\s+in\s+databases\s*\}"
                 r"\s*\\?\s*\|\s*\{[^}]*for\s+\w+\s+in\s+mongos\s*\}", s)
if not mdec:
    fallos.append("sources() does not build `declared` from BOTH the postgres "
                  "services AND the dumped (mongo) ones: a mongodb StatefulSet "
                  "would read as undeclared and `sources()` aborts — no "
                  "organization on the instance gets a backup (measured 2026-09-04)")

# 3 — restore must NOT sweep dumped types into `buckets`. The old
# `buckets = [p ... if tipo != "postgres"]` put every mongo piece where
# restore_bucket would choke on it.
hechos += 1
mb = re.search(r"buckets\s*=\s*\[[^\]]*if\s+p\[.tipo.\]\s*not in\s*\(([^)]*)\)", s)
if not mb:
    fallos.append("restore() does not carve buckets as `tipo not in (...)`: if it "
                  "still says `!= \"postgres\"`, every mongodb piece is handed to "
                  "restore_bucket, which is half a restore in the making")
elif '"postgres"' not in mb.group(1) or '"mongodb"' not in mb.group(1):
    fallos.append("restore()'s bucket split does not exclude both postgres and "
                  "mongodb: a dumped piece would be treated as an object store")

# 4 — the capture flow actually captures the dumped types.
hechos += 1
if not re.search(r"capture_mongo\(", s) or "capture_mongo(mo" not in s.replace(" ", ""):
    fallos.append("capture_org() does not call capture_mongo over the dumped "
                  "services: they are declared, fenced and rendered, and never "
                  "captured")

# 5 — dump and restore run the CATALOGUE's own templates, not commands
# hard-coded here: that is what lets a fourth dumped type work unedited.
hechos += 1
if '_tmpl_run(' not in s or 'tmpl' not in s:
    fallos.append("aegis-data does not run the templates services.yaml carries "
                  "(_tmpl_run / tmpl): a mongo command hard-coded here would drift "
                  "from the catalogue it is supposed to obey")
else:
    if not re.search(r'_tmpl_run\(\s*\w+\[.tmpl.\]\[.dump.\]', s):
        fallos.append("the capture does not run tmpl['dump'] from the catalogue")
    if not re.search(r'_tmpl_run\(\s*\w+\[.tmpl.\]\[.restore.\]', s):
        fallos.append("the restore does not run tmpl['restore'] from the catalogue")

# 6 — the measurement (sizes/metrics/measure) counts the dumped type as
# a database, not as an afterthought that falls into the bucket branch.
hechos += 1
if s.count('("postgres", "mongodb")') < 2:
    fallos.append("sizes()/metrics()/measure() do not treat mongodb alongside "
                  "postgres: the type renders and backs up but weighs nothing in "
                  "the series, so a full mongo disk is invisible until it stops "
                  "accepting writes")

for f in fallos:
    print(f)
print("__COUNT__ %d" % hechos, file=sys.stderr)
