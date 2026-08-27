# teeth of check 036 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.
# Extended 2026-08-27: the check sums EVERY seed/platform/*/Jenkinsfile,
# so a heavy pod in any of them has to move the arithmetic.

# the subject disappears: if the check does not notice, it was not
# reading it
red_1() { rm -f "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"; }

# a 9-core container in a pipeline the old list never read
# (mirror-images: 9000m + 3 others > half of what the RQ leaves)
red_2() {
    python3 - "$AEGIS_ROOT/seed/platform/mirror-images/Jenkinsfile" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "      limits:   { cpu: 1000m, memory: 1Gi }\n"
assert old in t
open(p, "w").write(t.replace(old, "      limits:   { cpu: 9, memory: 1Gi }\n", 1))
PY
}
# the same in base-images (its kaniko). If the file is not in the tree
# yet, the tooth writes one with that pod, so it bites either way.
red_3() {
    local f="$AEGIS_ROOT/seed/platform/base-images/Jenkinsfile"
    if [[ -f "$f" ]]; then
        python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"limits:\s*\{\s*cpu:\s*1500m,\s*memory:\s*2Gi\s*\}", "limits:   { cpu: 9, memory: 2Gi }", t, count=1)
assert n[1] == 1, "the kaniko limit of base-images is not 1500m/2Gi any more: re-aim this tooth"
open(p, "w").write(n[0])
PY
    else
        mkdir -p "$(dirname "$f")"
        printf "pipeline {\n  agent { kubernetes { yaml '''\n  - name: kaniko\n    resources:\n      limits:   { cpu: 9, memory: 2Gi }\n''' } }\n}\n" > "$f"
    fi
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"; }
# control: a new light pipeline does not move the heaviest
control_2() {
    mkdir -p "$AEGIS_ROOT/seed/platform/tooth-job"
    printf "pipeline {\n  agent { kubernetes { yaml '''\n  - name: jnlp\n    resources:\n      limits:   { cpu: 500m, memory: 512Mi }\n''' } }\n}\n" > "$AEGIS_ROOT/seed/platform/tooth-job/Jenkinsfile"
}
