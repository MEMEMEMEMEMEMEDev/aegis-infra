# title: every init write destination in platform/ survives a clean clone
# origin: verify-static.sh (v2) ══ 84
check() {
# Run on native Linux (2026-07-25): phase 15 does
# `mv "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"` and
# platform/tofu/secrets/ did NOT exist after a `git clone` — git does
# not version empty directories and that was the ONLY write destination
# with no versioned file at all. With errexit alive (the #15 fix) the
# mv killed the phase stone dead, before producing a single encryption.
# Latent for 18 runs: the VM was populated by COPYING the operator's
# directory (which already had the dir from an earlier run), not by
# cloning; the first virgin clone uncovered it. Class: "static
# references must exist" (#3) + "dirty state: greenfield != clean"
# (failure-modes.md). The check resolves the phases' path variables and
# demands that EVERY destination directory have at least one VERSIONED
# file — a dir that only exists in the operator's tree does not count,
# which is exactly what fooled 18 runs.
# SECOND instance (same run, phase 80): `cp ...
# "$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub"` — same bug,
# ANOTHER path variable. This check's 1st version only looked at
# $B/$TOKENS_DIR/$IU_DIR and went green anyway: a narrow check is a
# check that LIES. That is why the list of variables is now DERIVED
# from the code (the ones pointing at the platform repo) instead of
# being hardcoded, and any new unmapped variable is a FAIL.
# SECOND instance (same run, phase 80): `cp ...
# "$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub"` — same bug,
# ANOTHER path variable. This check's 1st version only looked at
# $B/$TOKENS_DIR/$IU_DIR and went green anyway: a narrow check is a
# check that LIES, and this is the meta-class "mention != use" applied
# to the verifier itself. That is why the paths are RESOLVED from the
# code (chained VAR="$OTHER/sub" assignments, seeded with
# PLATFORM_DIR) instead of being hardcoded: a new variable enters the
# check on its own. What cannot be resolved statically (dynamic
# interpolation) is REPORTED, never silently ignored.
D84=""
_OUT84="$(python3 - "$AEGIS_ROOT" <<'PY84' 2>&1
import os, re, sys, glob
root = sys.argv[1]
files = sorted(glob.glob(os.path.join(root, "init/phases/*.sh")) +
               glob.glob(os.path.join(root, "init/lib/*.sh")))
text = {f: open(f, encoding="utf-8", errors="replace").read() for f in files}
# 1) map of variables -> path relative to the repo, resolving chains
# $PLATFORM_DIR is the instance's WORKING directory, which since
# 2026-08-05 is no longer versioned (it is the checkout of the
# instance's repo). Its versioned counterpart —the one a virgin clone
# DOES bring, and the one phase 10 seeds it from— is the seed. The
# invariant did not change: every write destination has to exist after
# a git clone. What changed is where it is checked.
resolved = {"PLATFORM_DIR": "seed/platform"}
assign = re.compile(r'^\s*([A-Z_]+)="\$\{?([A-Z_]+)\}?(/[^"]*)?"\s*$', re.M)
dynamic = []
for _ in range(5):                      # fixed point: chains of 5 hops
    for f, t in text.items():
        for var, base, sub in assign.findall(t):
            if base not in resolved or var in resolved:
                continue
            if "${" in (sub or "") or "$(" in (sub or ""):
                dynamic.append(var); continue
            resolved[var] = (resolved[base] + (sub or "")).rstrip("/")
# variables that point at platform/ but could NOT be resolved:
for f, t in text.items():
    for var, base, sub in assign.findall(t):
        if base == "PLATFORM_DIR" and var not in resolved:
            dynamic.append(var)
# 2) all the uses: $VAR and $VAR/subpath
targets = set()
use = re.compile(r'\$\{?([A-Z_]+)\}?(/[A-Za-z0-9._/-]+)?')
for f, t in text.items():
    for var, sub in use.findall(t):
        if var not in resolved:
            continue
        p = (resolved[var] + (sub or "")).rstrip("/")
        if p and p != "seed/platform":
            targets.add(p)
# $APP_VALUES = "$PLATFORM_DIR/${CONTRACT[4]}", and CONTRACT comes from
# parsing core.yaml (the adoption contract, the SINGLE SOURCE — phase
# 30). It is resolved from that same source instead of being excluded
# by name: if core.yaml changes shape, this check FAILS instead of
# going blind, which is exactly what let the bug's 2nd instance
# through.
dynamic = set(dynamic)
if "APP_VALUES" in dynamic:
    try:
        import yaml
        core = os.path.join(root, "seed/platform/k8s/argocd-apps/core.yaml")
        docs = [d for d in yaml.safe_load_all(open(core)) if d]
        app = next(d for d in docs if d.get("kind") == "Application"
                   and d["metadata"]["name"] == "argocd")
        src = next(s for s in app["spec"]["sources"] if "chart" in s)
        vf = src["helm"]["valueFiles"][0]
        assert vf.startswith("$values/"), f"valueFiles without a $values ref: {vf}"
        resolved["APP_VALUES"] = "seed/platform/" + vf[len("$values/"):]
        targets.add(resolved["APP_VALUES"])     # enters the verified set
        dynamic.discard("APP_VALUES")
    except Exception as e:
        print("ERR could not resolve APP_VALUES from core.yaml:", e)
for v in sorted(dynamic):
    print("DYN", v)
for p in sorted(targets):
    # the write's destination is the containing directory; if the last
    # segment has no extension, the path itself may also be a
    # destination directory (cp/mkdir), so both are demanded.
    d = os.path.dirname(p)
    if d and d != "platform":
        print("DIR", d)
    if "." not in os.path.basename(p):
        print("DIR", p)
PY84
)"
# This check's instrument is git: it asks which files are VERSIONED.
# With no repository there is nothing to ask, and answering «none»
# would be confusing «I could not measure» with «it is wrong» — the
# mistake this house's whole doctrine exists in order not to make. It
# happened for real on 2026-08-23: the product was copied to the
# development machine with rsync without .git and this check reported
# 26 broken directories that were perfectly fine.
if ! git -C "$AEGIS_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    skip "no git repository in $AEGIS_ROOT: without it there is no way to know which files survive a clone (this is NOT a pass)"
    return
fi
_n84=0
while read -r _k84 _p84; do
    case "$_k84" in
      DYN) D84="$D84 \$$_p84 points at platform/ with dynamic interpolation — the check CANNOT verify its destination (resolve it or document it);" ;;
      DIR)
        _n84=$((_n84 + 1))
        if [[ ! -d "$AEGIS_ROOT/$_p84" ]]; then
            D84="$D84 $_p84 does not exist in the tree;"
        elif [[ -z "$(git -C "$AEGIS_ROOT" ls-files -- "$_p84" 2>/dev/null)" ]]; then
            D84="$D84 $_p84 has NO versioned file at all — it does not survive a git clone (add a .gitkeep);"
        fi ;;
      *) [[ -n "$_k84" ]] && D84="$D84 the path resolver failed: $_k84 $_p84;" ;;
    esac
done <<< "$(printf '%s\n' "$_OUT84" | sort -u)"
[[ "$_n84" -ge 20 ]] || D84="$D84 only $_n84 destinations detected (expected >=20) — the resolver stopped finding paths, the check has gone blind;"
if [[ -n "$D84" ]]; then fail "clean-clone:$D84"
else pass "the $_n84 init write destinations in platform/ have versioned files (they survive a git clone)"; fi
}
