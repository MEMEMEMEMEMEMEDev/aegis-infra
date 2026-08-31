# title: a host step a manifest declares is executed by somebody, and measured where it becomes true
# origin: new in v3 — 2026-08-31, after a comment installed nothing for a week
check() {
# `k8s/base/gpu/runtimeclass.yaml` opens by enumerating three steps in
# order: install the toolkit on the HOST, restart k3s, then apply this
# RuntimeClass. It is correct and it is well written, and until
# 2026-08-31 step 1 existed ONLY as that comment. Nothing in the
# artifact installed it and nothing measured it, so its absence
# surfaced far from its cause — a 300 s timeout of `gpu-units-advertised`
# about forty minutes into an install, with a diagnosis listing four
# possible causes.
#
# The class this check watches is not «the GPU»: it is A MANIFEST THAT
# DESCRIBES A HOST STEP NOBODY EXECUTES. A comment installs nothing,
# and the cost of that is always the same shape — the symptom appears
# in a place that has nothing to do with the cause.
#
# So three things have to hold together, and each covers a different
# way to break the chain:
#
#   1. the package the comment names is INSTALLED by the artifact
#      (an ansible task, in the playbook that runs BEFORE k3s exists —
#      that ordering is the whole reason step 2 disappears);
#   2. some phase MEASURES the result, and measures the generated
#      containerd config rather than the binary: an apt package that
#      installed fine and a containerd that never saw it look identical
#      from the playbook's side;
#   3. nothing edits k3s's containerd config by hand. k3s regenerates
#      it from a template on every boot, so an edit is erased on the
#      next reboot and the drift is silent — the one failure mode this
#      whole arrangement exists to avoid.
RC="$SEED/platform/k8s/base/gpu/runtimeclass.yaml"
BOOTSTRAP="$SEED/platform/ansible/playbooks/bootstrap-host.yml"
[[ -f "$RC" ]] || { skip "there is no gpu/runtimeclass.yaml in the seed"; return; }
[[ -f "$BOOTSTRAP" ]] || { fail "bootstrap-host.yml is not there: $BOOTSTRAP"; return; }

PKG="$(grep -oE '\bnvidia-container-toolkit\b' "$RC" | head -1)"
D161=""
if [[ -z "$PKG" ]]; then
    D161="$D161 the RuntimeClass no longer names the host package it depends on: the coupling stopped being written down, and this check lost the subject it derives from;"
else
    # (1) installed by the artifact, in the playbook that runs first
    grep -q "$PKG" "$BOOTSTRAP" \
      || D161="$D161 $RC names $PKG as a host step and no task of bootstrap-host.yml installs it — a comment installs nothing;"
    # (2) measured, and against the config k3s GENERATES
    MEASURED="$(grep -rl 'nvidia-runtime-in-containerd' "$AEGIS_ROOT/init/phases" 2>/dev/null | head -1)"
    if [[ -z "$MEASURED" ]]; then
        D161="$D161 no phase carries a nvidia-runtime-in-containerd gate: the package could install and containerd never see it, and the two look identical from the playbook;"
    elif ! grep -q 'containerd/config' "$MEASURED"; then
        D161="$D161 $(basename "$MEASURED") gates the runtime without reading the containerd config k3s generates: whether the binary exists is not the question, whether the runtime k3s hands a Pod exists is;"
    fi
fi
# (3) nobody rewrites what k3s regenerates
# NON-COMMENT lines only, and the first version of this check did not
# do that: it read the paragraph of bootstrap-host.yml that explains
# why this is NOT done and accused the file of doing it. A check that
# bites the prose documenting the defect it hunts is the same failure
# the 152 had to be corrected for — an instrument that accuses is worse
# than one that misses.
HANDEDIT="$(grep -rn 'nvidia-ctk[[:space:]]\+runtime[[:space:]]\+configure' \
            "$AEGIS_ROOT/init" "$SEED" 2>/dev/null \
            | grep -vE ':[0-9]+:[[:space:]]*#' | cut -d: -f1 | sort -u | head -3)"
[[ -n "$HANDEDIT" ]] && D161="$D161 $(echo "$HANDEDIT" | paste -sd' ') runs \`nvidia-ctk runtime configure\` against k3s's containerd: k3s regenerates that file from its template on every boot, so the edit is erased on the next reboot and the drift is silent;"

printf '    the RuntimeClass names %s · measured by %s\n' \
    "${PKG:-nothing}" "$(basename "${MEASURED:-nobody}")"
if [[ -n "$D161" ]]; then fail "a host step is declared and not carried out:$D161"
else pass "the host package the RuntimeClass depends on is installed by the playbook that runs before k3s, measured against the containerd config k3s generates, and nothing edits that config by hand"; fi
}
