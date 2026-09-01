# title: a phase that builds a file the seed ships says whether the instance's copy differs
# origin: new in v3 — 2026-09-01, after the same fix failed to arrive three times
check() {
# `seed_platform_dir` refuses to copy the seed over an instance that
# has a history of its own, and that refusal is right: the operator's
# working tree is the truth. What nobody had measured is the other
# half — a fix made in the PRODUCT never reaches a live instance, and
# says nothing while not reaching it.
#
# Measured three times on 2026-09-01. The worst one: a pipeline was
# corrected in the seed, the instance kept the old copy, and the build
# failed with the error that had already been fixed — byte for byte,
# same line number. Nothing in the output hinted that the file being
# executed was not the file being read, so the natural conclusion was
# that the fix was wrong. It was not; it was simply somewhere else.
#
# The remedy is deliberately NOT to copy: an instance is allowed to
# differ. It is not allowed to differ SILENTLY. So a phase that fires
# a build from a file the seed also ships has to say, before firing,
# whether the two are the same.
D170=""
C="$AEGIS_ROOT/lib/common.sh"

grep -q '^seed_drift_report()' "$C" \
  || D170="$D170 lib/common.sh does not define seed_drift_report: nothing can tell an operator that what is about to run is not what the artifact ships;"

# it REPORTS, it does not overwrite: copying would destroy the tree
# seed_platform_dir deliberately protects.
if grep -q '^seed_drift_report()' "$C"; then
    # Lines that PRINT are not lines that RUN. The helper's whole
    # output is a `cp` command suggested to the operator, and the
    # first version of this check read that suggestion as the helper
    # copying. Eighth time in one day; comments and output lines both
    # get dropped before looking for an execution.
    awk '/^seed_drift_report\(\)/,/^}/' "$C" \
      | grep -vE '^[[:space:]]*#' \
      | grep -vE '^[[:space:]]*(log_[a-z]+|echo|printf)\b' \
      | grep -qE '(^|[^-])\bcp\b|rsync|install -m' \
      && D170="$D170 seed_drift_report COPIES: the instance's working tree is the truth, and overwriting it is the thing seed_platform_dir refuses to do for good reason;"
    awk '/^seed_drift_report\(\)/,/^}/' "$C" | grep -q 'diff' \
      || D170="$D170 seed_drift_report never compares anything: it cannot report a difference it does not measure;"
fi

# and the phase that fires AI builds actually calls it, BEFORE building
P87="$AEGIS_ROOT/init/phases/87-ai.sh"
if [[ -f "$P87" ]] && grep -qE '(^|[^#])jenkins_build_retry' "$P87"; then
    _c() { grep -vE '^[[:space:]]*#' "$1" | grep -n "$2" | head -1 | cut -d: -f1; }
    R="$(_c "$P87" 'seed_drift_report')"
    B="$(_c "$P87" 'jenkins_build_retry')"
    if [[ -z "$R" ]]; then
        D170="$D170 87-ai.sh builds images from files the seed also ships and never says whether the instance's copies match: the failure mode is a build dying on an error that was already fixed;"
    elif (( R > B )); then
        D170="$D170 87-ai.sh reports the drift at line $R, AFTER firing its first build at line $B — the point of saying it is to say it BEFORE twenty minutes of build;"
    fi
fi

printf '    %s files compared before the AI builds\n' \
    "$(grep -A4 'seed_drift_report ai/' "$P87" 2>/dev/null | grep -oE 'ai/[a-z-]+/[A-Za-z]+' | sort -u | wc -l)"
if [[ -n "$D170" ]]; then fail "a product fix can fail to reach an instance in silence:$D170"
else pass "the artifact compares the instance's copy against the one it ships, says so without overwriting, and says it before firing a build"; fi
}
