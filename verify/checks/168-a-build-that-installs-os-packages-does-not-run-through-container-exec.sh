# title: a build that installs OS packages does not run through the container exec API
# origin: new in v3 — 2026-09-01, measured against five refuted hypotheses
check() {
# MEASURED, and the measurement is the whole content of this check.
#
# kaniko started through the container EXEC API — which is exactly
# what `container('name'){ sh … }` does in a Jenkins Kubernetes agent
# — dies with «failed to execute command: permission denied» as soon
# as the build installs an OS package with apt. One
# `apt-get install -y less` is enough. The RUN itself COMPLETES first
# and prints its whole output, so the error lands nowhere near its
# cause: the four-hour GPU build died looking like a compiler problem.
#
# The same Containerfile, the same pod, the same kaniko, started
# inside the container's OWN process tree, builds fine.
#
# Refuted along the way, each by its own probe, so nobody repeats
# them: the Debian base itself (a trivial two-RUN build works), apt's
# download sandbox (`apt-get update` alone works), dpkg triggers
# (`--no-triggers` still fails), the snapshot mode (redo, time,
# single-snapshot, use-new-run all fail), and the parent shell
# (no shell, and `exec`-replaced shell, both still fail). Alpine with
# `apk add` works through exec, which is why every other lane in this
# seed never met this.
#
# So the rule is narrow on purpose, because that is what was measured:
# a Containerfile that runs `apt-get install` must be built by a
# pipeline that drives kaniko from the container's own process tree.
D168=""
# The scan is python, in its own file, for two reasons measured today:
# a sed that fails silently turns a check green (check 166), and a
# grep that reads the paragraph explaining the fix accuses the fix
# (checks 161, 163, 165, 166, 167 — and the first version of this one).
if ! OUT="$(python3 "$AEGIS_ROOT/verify/checks/168.py" "$SEED" 2>/dev/null)"; then
    D168="$D168 the scan itself failed and this check measured nothing;"
elif [[ -n "$OUT" ]]; then
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        D168="$D168 $hit;"
    done <<< "$OUT"
fi
N="$(python3 "$AEGIS_ROOT/verify/checks/168.py" "$SEED" 2>&1 >/dev/null | awk '/__COUNT__/{print $2}')"

printf '    %s Containerfiles in the seed install OS packages with apt\n' "$N"
if [[ -n "$D168" ]]; then fail "a build that installs OS packages runs through the exec API:$D168"
else pass "every Containerfile in the seed that installs OS packages is built by a pipeline that drives kaniko from the container's own process tree, which is the arrangement measured to work"; fi
}
