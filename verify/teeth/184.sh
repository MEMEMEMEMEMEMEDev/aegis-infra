# teeth of check 184 — the application pipeline's anti-loop asks the
# registry, not only whether the source changed.

_184_py() { python3 - "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app" "$@"; }

# THE STATE THE ARTIFACT WAS IN until 2026-09-03: the skip read the
# commit's paths and nothing else, so a repo arriving at a new
# installation skipped its own first build.
red_1() {
    _184_py <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r'\n          if \(onlyManifests\) \{\n.*?\n          \}\n', s, re.S)
assert m, "the registry check could not be located"
open(p, "w", encoding="utf-8").write(s.replace(m.group(0), "\n", 1))
PYEOF
}

# present but toothless: it asks nothing of the registry.
red_2() {
    sed -i 's|cosign verify --key /tmp/cosign.pub|true --key /tmp/cosign.pub|' \
        "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"
}

# it verifies AFTER the decision is taken, which is watching, not
# guarding.
red_3() {
    _184_py <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
blk = re.search(r'\n          if \(onlyManifests\) \{\n.*?\n          \}\n', s, re.S).group(0)
anchor = "          env.SKIP_BUILD = onlyManifests ? 'true' : 'false'\n"
assert s.count(anchor) == 1
s = s.replace(blk, "\n", 1).replace(anchor, anchor + blk, 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# it verifies the wrong thing: not the digests the deploy stage pinned
# in the overlay, so the answer is about another image.
red_4() {
    sed -i 's|OVERLAY="${OVERLAY:-k8s/overlays/dev/kustomization.yaml}"|OVERLAY="${OVERLAY:-/dev/null}"|' \
        "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"
}

# the bootstrap window stops being survivable: with no key yet, an
# installation could never build its first image.
red_5() {
    sed -i 's|\[ -f /cosign/keys/cosign.key \] \|\| exit 0|true|' \
        "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"
}

# control: the PROSE that argues the whole decision, in the same stage
# and in the same words. This check strips comments before looking
# precisely so the paragraph cannot stand in for the guard.
control_1() {
    _184_py <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "    stage('detect-change') {\n"
nota = ("      // note: a manifest-only commit is only a reason to skip if\n"
        "      // cosign verify says THIS registry serves that digest signed;\n"
        "      // an application repo travels between installations.\n")
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, anchor + nota, 1))
PYEOF
}

# control: one more read-only call inside the stage. Asking the
# registry something extra is not a defect; the guarantee is about
# what the skip depends on.
control_2() {
    sed -i 's|                cosign public-key --key /cosign/keys/cosign.key|                cosign version >/dev/null 2>\&1 \|\| true\n                cosign public-key --key /cosign/keys/cosign.key|' \
        "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"
}
