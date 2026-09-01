# title: the base of an AI lane is resolved before its build, and the guard reads the FROM
# origin: new in v3 — 2026-09-01, after a guard matched its own explanation
check() {
# Each AI Containerfile ships with `__FROM_X__` where a base belongs.
# It is resolved against the INTERNAL registry, by digest, because a
# base that did not come through the mirror was neither scanned nor
# signed and a pod built on it is refused at admission.
#
# Two failures on 2026-09-01, and they compound:
#
#   The resolver existed, was correct, and NOTHING CALLED IT before a
#   build. The same shape as every other hole this phase had: a
#   section that arrived without its precondition. Worse, the only
#   caller was `aegis ai images` — which reads like a question and
#   rewrote two Containerfiles as a side effect of being asked.
#
#   And the guard that catches an unresolved base did `grep -q
#   '__FROM_'` over THE WHOLE FILE, while the file documents its own
#   placeholder in a comment directly above the FROM. So the guard
#   matched its own explanation: unbuildable whether or not anybody
#   resolved anything, and the error told the operator to run a
#   command that had already been run. Prose read as code, for the
#   fifth time in one day — checks 161, 163, 165 and 166 were all
#   corrected for the same trap.
CFS="$(ls "$SEED"/platform/ai/*/Containerfile 2>/dev/null || true)"
[[ -n "$CFS" ]] || { skip "the seed carries no AI Containerfile"; return; }

D167=""
for cf in $CFS; do
    lane="$(basename "$(dirname "$cf")")"
    jf="$(dirname "$cf")/Jenkinsfile"
    # only a lane that actually SHIPS a placeholder has this obligation
    grep -E '^[[:space:]]*FROM[[:space:]]' "$cf" | grep -q '__FROM_' || continue
    [[ -f "$jf" ]] || { D167="$D167 $lane ships a placeholder base and has no pipeline to guard it;"; continue; }

    g="$(grep -n '__FROM_' "$jf" | grep -i 'grep' || true)"
    if [[ -z "$g" ]]; then
        D167="$D167 the $lane pipeline never checks that its base was resolved: kaniko would be handed a FROM that is not an image, and the message would be about a manifest instead of about the missing step;"
    elif ! grep -qE "FROM\[\[:space:\]\]|\^\[\[:space:\]\]\*FROM|\^FROM" <<< "$g"; then
        D167="$D167 the $lane guard tests the WHOLE file for the placeholder, and the Containerfile documents that placeholder in a comment — so the guard matches its own explanation and the lane can never be built, resolved or not;"
    fi
done

# the command the guard NAMES has to be one the CLI dispatches: the
# first version pointed at `aegis ai images`, which by then only
# reported. An error that names the wrong command costs the reader the
# same as no error at all.
AI="$AEGIS_ROOT/libexec/aegis-ai"
if [[ -f "$AI" ]]; then
    SUBS="$(grep -m1 '^# aegis-subcommands:' "$AI" | cut -d: -f2-)"
    while IFS= read -r named; do
        [[ -n "$named" ]] || continue
        grep -qw -- "$named" <<< "$SUBS" \
          || D167="$D167 a pipeline tells the operator to run «aegis ai $named» and the CLI declares no such subcommand;"
    done < <(grep -ohE 'aegis ai [a-z-]+' $CFS "$SEED"/platform/ai/*/Jenkinsfile 2>/dev/null \
             | awk '{print $3}' | sort -u)
fi

# and the phase resolves BEFORE it builds, not after
P87="$AEGIS_ROOT/init/phases/87-ai.sh"
if [[ -f "$P87" ]] && grep -q 'jenkins_build_retry' "$P87"; then
    # Comments excluded on BOTH sides. Without that, the paragraph of
    # 87.1a that explains the shape by citing «jenkins_build_retry
    # ci-images» counts as the first build, and this check — the one
    # about guards that read prose as code — read prose as code.
    _code() { grep -vE '^[[:space:]]*#' "$1" | grep -n "$2" | head -1 | cut -d: -f1; }
    RES="$(_code "$P87" 'aegis-ai" bases\|aegis-ai bases')"
    BLD="$(_code "$P87" 'jenkins_build_retry')"
    if [[ -z "$RES" ]]; then
        D167="$D167 87-ai.sh fires AI builds and never resolves the bases: the pipelines refuse to build and the step that was missing is not named anywhere;"
    elif (( RES > BLD )); then
        D167="$D167 87-ai.sh resolves the bases at line $RES, AFTER firing its first build at line $BLD — a precondition that runs afterwards is not a precondition;"
    fi
fi

printf '    %s AI lanes with a placeholder base\n' "$(wc -w <<< "$CFS")"
if [[ -n "$D167" ]]; then fail "an AI lane cannot reach its build:$D167"
else pass "every AI lane with a placeholder base is guarded by a test that reads its FROM and not its prose, the guard names a subcommand the CLI dispatches, and the phase resolves the bases before it fires a build"; fi
}
