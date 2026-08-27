# teeth for check 071 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'app-repo-estado-igual-al-seed' "$AEGIS_ROOT/init/phases/12-workrepos.sh" > "$AEGIS_ROOT/init/phases/12-workrepos.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/12-workrepos.sh.tooth" "$AEGIS_ROOT/init/phases/12-workrepos.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/12-workrepos.sh"; }

# 2026-08-27: the digest branch of the effective-image gate disappears
red_2() {
    python3 - "$AEGIS_ROOT/init/phases/70-deploy-auto.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '"https://$REGISTRY_CLUSTER_IP:5000/v2/hello-aegis/manifests/$EFF_REF")'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, '"https://$REGISTRY_CLUSTER_IP:5000/v2/hello-aegis/tags/list")', 1))
PY
}

# 2026-08-27: phase 80 goes back to accepting any '@sha256:'
red_3() {
    python3 - "$AEGIS_ROOT/init/phases/80-supply-chain.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "   | grep -qF '@$DIGEST'\"\n"
assert t.count(old) == 1, t.count(old)
open(p, "w").write(t.replace(old, "   | grep -q '@sha256:'\"\n", 1))
PY
}
