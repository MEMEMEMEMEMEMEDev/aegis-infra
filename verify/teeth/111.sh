# teeth for check 111 (the glossary's ratchet)
#
# The real risk is not that somebody rewrites `paths.py` as `rutas.py`
# on purpose: it is that a NEW file is born out of the old habit and
# nobody notices, because the tree is still half in Spanish and one
# more word does not draw attention.
red_1() {
    printf '\nOLD_PATHS = "lib/aegis/rutas.py"\n' >> "$AEGIS_ROOT/lib/aegis/paths.py"
}

# the same return by way of the artifact, which is where it hurts most:
# a manifest that names the file by its retired name again.
red_2() {
    printf '\n# nothing\nold: planes.yaml\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/bootstrap/appprojects.yaml"
}

# and the case that proves the list is DERIVED from the document and is
# not written in the check: adding a word to the glossary has to start
# watching it immediately.
red_3() {
    sed -i 's|^| `dominio_raiz` | `root_domain` | contract and edge key |$|\0\n| `gris` | `gray` | |' \
        "$AEGIS_ROOT/docs/glossary.md" 2>/dev/null || \
    python3 - "$AEGIS_ROOT/docs/glossary.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "| `equivalencia-org.sh` | `org-equivalence.sh` | |\n"
s = s.replace(anchor, anchor + "| `gris` | `gray` | |\n", 1)
open(p, "w").write(s)
PY
}

# control: telling the story in a COMMENT that names a retired word is
# legitimate, and it is what checks 108 and 001 do. If this turned red,
# the ratchet would be erasing the repo's memory.
control_1() {
    printf '\n# history: this used to be called rutas.py and planes.yaml\n' \
        >> "$AEGIS_ROOT/lib/aegis/paths.py"
}
