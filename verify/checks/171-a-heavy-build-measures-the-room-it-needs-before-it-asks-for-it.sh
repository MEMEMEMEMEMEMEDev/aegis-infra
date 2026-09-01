# title: a heavy build measures the room it needs before asking for it
# origin: new in v3 — 2026-09-01, after three evictions twenty minutes in
check() {
# kaniko unpacks the whole image and writes its layers and its tar on
# the NODE, so a build's cost is not only time: the GPU engine's build
# takes about 36 GiB of ephemeral storage, measured, and the kubelet
# starts evicting pods when the node drops below roughly 11 GiB free.
#
# Measured 2026-09-01: that build was evicted three separate times,
# each after fifteen or twenty minutes of real work, and what the
# operator saw was «ABORTED» — a word about a pipeline, not about a
# disk. Worse, it compounds: every build leaves its image in the
# registry and nothing prunes it, so each rebuild makes the next one
# likelier to be evicted.
#
# The fix is not a bigger disk, it is asking one second before instead
# of twenty minutes after. So: every image this phase can build
# declares what its build needs, and the phase compares that against
# the node before firing.
P87="$AEGIS_ROOT/init/phases/87-ai.sh"
[[ -f "$P87" ]] || { skip "there is no 87-ai.sh"; return; }
grep -qE '(^|[^#])jenkins_build_retry' "$P87" || { skip "phase 87 fires no builds"; return; }

D171=""
_code() { grep -vE '^[[:space:]]*#' "$P87"; }

# every buildable image declares its cost, next to its timeout —
# the two numbers that say what a build spends
N=0; MISSING=""
while IFS= read -r line; do
    N=$(( N + 1 ))
    grep -q '_gib=' <<< "$line" \
      || MISSING="$MISSING $(sed -E 's/^[[:space:]]*([a-z0-9-]+)\).*/\1/' <<< "$line")"
done < <(_code | grep -E '^\s+(aegis-[a-z0-9-]+|ai-gateway)\)\s+_job=')
(( N > 0 )) || D171="$D171 no image in 87-ai.sh declares a job to build it: the table this check derives from is gone;"
[[ -z "$MISSING" ]] || D171="$D171 these build with no declared cost:$MISSING — a build whose size nobody wrote down cannot be refused before it is too late;"

# and the room is measured BEFORE the build is fired
R="$(_code | grep -n 'df ' | head -1 | cut -d: -f1)"
B="$(_code | grep -n 'jenkins_build_retry' | head -1 | cut -d: -f1)"
if [[ -z "$R" ]]; then
    D171="$D171 87-ai.sh never measures the node's free space: the eviction arrives as ABORTED, twenty minutes in, saying nothing about a disk;"
elif [[ -n "$B" ]] && (( R > B )); then
    D171="$D171 87-ai.sh measures the free space at line $R, AFTER firing its first build at line $B — measuring afterwards is watching, not checking;"
fi

# the refusal has to name what to do, not just what is wrong
_code | grep -q 'Free space and run this phase again' \
  || D171="$D171 the refusal does not tell the operator what to do about it: an error that names no next step spends the reader's time twice;"

printf '    %s buildable images · costs declared beside their timeouts\n' "$N"
if [[ -n "$D171" ]]; then fail "a heavy build can be fired into a node that cannot hold it:$D171"
else pass "every image this phase builds declares the scratch its build needs, and the phase compares it against the node before firing instead of discovering it as an eviction"; fi
}
