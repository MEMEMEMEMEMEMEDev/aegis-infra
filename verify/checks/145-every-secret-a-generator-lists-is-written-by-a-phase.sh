# title: every encrypted secret a ksops generator lists is written by some phase
# origin: new in v3 — 2026-08-27, the first clean instance: garage never rendered (ksops: no such file)
check() {
# A ksops secret-generator names the .enc.yaml files it decrypts. Those
# files are NOT in the seed (they are born on the instance, encrypted
# to its age key) — so somebody in init/phases has to write each one,
# or the whole App fails to render: "error reading X.enc.yaml: no such
# file" and ArgoCD reports ComparisonError while the App shows Healthy
# (nothing was ever created to be unhealthy). On the house machine
# garage-system's file existed from a hand-run `aegis secret`; on the
# first clean instance the garage App never rendered, and with it no
# bucket, no data backup, no tenant storage. Derived from the
# generators, so the next namespace cannot be forgotten either.
D145=""; N145=0
_gen_files() {   # <generator.yaml> → the .enc.yaml files it lists
    python3 - "$1" <<'PY'
import sys, yaml
for doc in yaml.safe_load_all(open(sys.argv[1])):
    if not isinstance(doc, dict): continue
    for x in (doc.get("files") or []):
        if isinstance(x, str) and x.endswith(".enc.yaml"): print(x)
PY
}
GENS="$(find "$SEED/platform/k8s" -name 'secret-generator.yaml' | sort)"
# how many generators list each file name: a name that only ONE
# generator uses is identified by itself; one that several share
# (secret-regcred-internal.enc.yaml, one per namespace) is identified
# by "<dir>/<file>" — the phases build paths from a variable plus that
# tail, so it is the longest literal there is
ALL145="$(for g in $GENS; do _gen_files "$g"; done | sort | uniq -c)"
while IFS= read -r gen; do
    dir="$(dirname "$gen")"
    rel="${dir#"$SEED"/platform/}"
    for f in $(_gen_files "$gen"); do
        N145=$((N145+1))
        [[ -f "$dir/$f" ]] && continue          # shipped with the seed: nothing to write
        shared="$(echo "$ALL145" | awk -v f="$f" '$2 == f {print $1}')"
        if (( shared > 1 )); then needle="$(basename "$dir")/$f"; else needle="$f"; fi
        if ! command grep -rqF -- "$needle" "$PHASES"/; then
            D145="$D145 $rel/$f is listed by $(basename "$dir")'s generator and no phase writes it (the App will not render on a clean instance);"
        fi
    done
done <<< "$GENS"
printf '    %s generator entries checked\n' "$N145"
if [[ -n "$D145" ]]; then fail "secrets nobody writes:$D145"
else pass "every .enc.yaml a generator lists is either in the seed or written by a phase"; fi
}
