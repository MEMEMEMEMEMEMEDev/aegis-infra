# teeth of check 188 — aegis-data backs up every dumped type the
# catalogue declares, not only postgres.

_188() { python3 - "$AEGIS_ROOT/libexec/aegis-data" "$@"; }

# THE STATE THE ARTIFACT WAS IN until 2026-09-04, bug one: the set of
# dumped types stops being derived and _dump_types no longer selects on
# the method, so nothing but postgres is ever a source.
red_1() {
    sed -i 's/b.get("method") == "dump"/b.get("method") == "__nunca__"/' \
        "$AEGIS_ROOT/libexec/aegis-data"
}

# THE R1 REGRESSION: the declared set drops the mongo half, so a mongo
# StatefulSet reads as undeclared and the backup of every org aborts.
red_2() {
    _188 <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
m = re.search(r"\n\s*\|\s*\{\(m\[\"ns\"\], m\[\"servicio\"\]\) for m in mongos\}", s)
assert m, "the mongos half of `declared` could not be located"
open(p, "w", encoding="utf-8").write(s.replace(m.group(0), "", 1))
PYEOF
}

# bug two: restore sweeps mongo pieces into the bucket path.
red_3() {
    sed -i 's/if p\["tipo"\] not in ("postgres", "mongodb")/if p["tipo"] != "postgres"/' \
        "$AEGIS_ROOT/libexec/aegis-data"
}

# the dumped types are declared and fenced but never captured.
red_4() {
    _188 <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
m = re.search(r"\n        for mo in mongos:\n(?:            .*\n)+", s)
assert m, "the capture loop over mongos could not be located"
open(p, "w", encoding="utf-8").write(s.replace(m.group(0), "\n", 1))
PYEOF
}

# the restore stops running the catalogue's own template and would need
# a hard-coded mongo command that drifts from services.yaml.
red_5() {
    sed -i 's/_tmpl_run(p\["tmpl"\]\["restore"\]/_tmpl_run("mongorestore hardcoded"/' \
        "$AEGIS_ROOT/libexec/aegis-data"
}

# the measurement forgets mongodb, so a full mongo disk weighs nothing.
red_6() {
    sed -i 's/if m\["tipo"\] in ("postgres", "mongodb"):/if m["tipo"] == "postgres":/g' \
        "$AEGIS_ROOT/libexec/aegis-data"
}

# control: the PROSE that explains all of this, in the file that
# implements it, naming datos/dump/mongodb/buckets. The scanner strips
# comments first precisely so an explanation is neither mistaken for the
# code nor able to stand in for it.
control_1() {
    _188 <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
anchor = "def _dump_types():\n"
nota = ("    # note: datos + dump is the pair; mongodb rides this and buckets\n"
        "    # never do. See check 188.\n")
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, anchor + nota, 1))
PYEOF
}

# control: a THIRD dumped type added to the catalogue's shape — the path
# is generic, so nothing in aegis-data has to change to serve it.
control_2() {
    python3 - "$AEGIS_ROOT/seed/platform/services.yaml" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
# a harmless comment near the redis block: the scanner reads aegis-data,
# not services.yaml, so this must not move check 188.
anchor = "  redis:\n    imagen: redis\n"
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, "  # a third dumped type would ride the same generic path.\n" + anchor, 1))
PYEOF
}
