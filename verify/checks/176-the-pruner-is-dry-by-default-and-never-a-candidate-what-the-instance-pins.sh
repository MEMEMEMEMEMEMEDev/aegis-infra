# title: the pruner is dry by default, and what the instance pins is never a candidate
# origin: new in v3 — 2026-09-02, after pruning the registry by hand three times in one day
check() {
# MEASURED 2026-09-01. The internal registry stores every image that is
# ever built and nothing prunes it. With the GPU engine at about 5.6 GB
# compressed per build, two rebuilds occupied 11.2 GB; deleting the
# manifests through the registry's API and running
# `registry garbage-collect --delete-untagged` inside the pod by hand
# brought it back to 3.5 GB. That had to be done three times in one
# day, and one of the images deleted had never even started.
#
# It composes with the other consumer of the same disk, which is what
# makes it expensive: the build of that engine needs about 42 GiB of
# ephemeral storage and the kubelet evicts pods below roughly 11 GiB
# free (phase 87 and check 171 measure exactly that). So every rebuild
# makes the next one harder, and the symptom never mentions a disk —
# the pod is «Evicted» and the pipeline says ABORTED.
#
# THIS CHECK IS NOT ABOUT THE DISK. It is about the two ways in which a
# pruner is worse than no pruner at all:
#
#   · one that acts without being asked. A verb that deletes images the
#     first time somebody types it to see what it would do is a verb
#     nobody can safely explore. So: dry by default, and the only thing
#     that changes that is a person typing --yes.
#   · ONE THAT DELETES WHAT IS RUNNING, which is the part that matters.
#     What a manifest of this instance fixes by digest is IN USE even
#     when its tag is a year old — that is the whole point of pinning
#     by digest — and the tenants' overlays live in the organisations'
#     repositories, not on this disk, so the cluster is the only place
#     that can answer for them. A prune planned without those answers
#     is a prune planned blind.
#
# The scan is python, in its own file, for the reason rule 6 of this
# tree keeps paying for: a pipeline that dies mid-way prints nothing,
# and «nothing is pinned» is the one wrong answer this command must
# never get. And it strips comments first, because this file argues
# every decision beside the code that makes it — the paragraph above
# the deleter names the very shapes the deleter refuses.
D176=""
[[ -f "$LIBEXEC/aegis-image" ]] || { fail "libexec/aegis-image does not exist: this check has no subject"; return; }

ERR176="$(mktemp)"
if ! OUT="$(python3 "$AEGIS_ROOT/verify/checks/176.py" "$AEGIS_ROOT" 2>"$ERR176")"; then
    D176="$D176 the scan itself failed and this check measured nothing: $(tail -1 "$ERR176" 2>/dev/null);"
elif [[ -n "$OUT" ]]; then
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        D176="$D176 $hit;"
    done <<< "$OUT"
fi
KEEP176="$(awk '/__KEEP__/{print $2}' "$ERR176" 2>/dev/null)"
DEL176="$(awk '/__DELETERS__/{print $2}' "$ERR176" 2>/dev/null)"
rm -f "$ERR176"

printf '    the pruner keeps %s image(s) per repository on age alone · %s place(s) in the command delete\n' \
    "${KEEP176:-?}" "${DEL176:-?}"
if [[ -n "$D176" ]]; then fail "the pruner of the internal registry acts on its own or can delete what is in use:$D176"
else pass "aegis image gc explains its plan and touches nothing unless --yes is given, derives what is protected from the instance's manifests, the declared list and the live cluster, deletes from one guarded place only, carries each signature with the manifest it signs, and keeps the same retention default the protocol argues"; fi
}
