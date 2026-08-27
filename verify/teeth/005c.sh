# teeth of check 005c (the canary's seed is complete)
# The org-personal → org-canary rename was left half done on 2026-07-28
# and the seed stopped starting up; this check comes from there.
red_1() { rm -f "$AEGIS_ROOT/seed/canary/k8s/base/deployment.yaml"; }
red_2() { rm -f "$AEGIS_ROOT/seed/canary/go.mod"; }
# 2026-08-27: phase 12 stops shipping the script the Jenkinsfile runs
red_3() {
    python3 - "$AEGIS_ROOT/init/phases/12-workrepos.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    run_cmd cp "$PLATFORM_DIR/docs/protocols/templates/write-digest.mjs" \\\n      "$SEED_TMP/ci/write-digest.mjs"\n'
assert t.count(old) == 1, t.count(old)
open(p, "w").write(t.replace(old, "", 1))
PY
}
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/12-workrepos.sh"; }
