# title: the round cannot fall silent (the three silences)
# origin: verify-static.sh (v2) ══ 93
check() {
# Disease E has a worse shape than the false green: the MISSING LINE. A
# check that reports health without measuring can at least be argued
# with; one that reports nothing is counted by nobody, and the final
# line —«no failures, N warnings»— comes out just as calm.
#
# The three silences found in aegis check on 2026-08-22, which are the
# three ways this happens:
#
#   1. the copied DISPATCH. The big meters return lines carrying their
#      own verdict (MAL:/BIEN:/NOTA:/NO EVALUADO) and bash distributes
#      them. The distribution was written twice and both times with the
#      same hole: if the meter blows up, the traceback goes to stderr,
#      the output is empty, no branch of the case matches and the
#      section prints its title and NOTHING ELSE.
#      The fix was not to patch both: it was for the protocol to exist
#      ONCE, in `despachar`, with the guard inside. This check maintains
#      that uniqueness — a second copy is a second chance to make the
#      same mistake.
#
#   2. the `sys.exit(0)` inside an `except`. Exiting WITH SUCCESS from
#      an error handler is always a lie: the empty output reads
#      identically to «I measured and found nothing». It was the case
#      of the restarts meter: if kubectl's JSON did not parse, the round
#      said «all 52 pods are running, none restarting» without having
#      looked at one.
#      (A `continue` inside a loop can be legitimate —skipping an item
#      that does not apply— so the rule is about the exit, which never
#      is.)
#
#   3. degradation in grey. `nota()` counts nothing, and that is right
#      when it hangs off an already-counted failure/warning. When it is
#      the ONLY thing reporting that the measurement weakened, the final
#      verdict never finds out. That is what `degradado()` is for: it
#      prints just as discreetly and adds a warning; this check demands
#      that it exist and that the difference between the two stay real.
D93=""
CHQ="$LIBEXEC/aegis-check"
if [[ ! -f "$CHQ" ]]; then
    D93="$D93 aegis check does not exist in the seed (the round does not travel);"
else
    # 1) the protocol, in one single place.
    N_CASE="$(grep -c 'MAL:\*)' "$CHQ" || true)"
    [[ "$N_CASE" == "1" ]] \
        || D93="$D93 there are $N_CASE dispatches of MAL:/BIEN: lines (there must be ONE, inside despachar): a copy of the protocol is a copy of the hole;"
    grep -q '^despachar() {' "$CHQ" \
        || D93="$D93 the despachar function is missing: without it every big meter distributes its lines by hand again;"
    # and the guard that makes it count: without the «it said nothing»
    # branch, despachar is the same old case under another name.
    # The CONDITION is what is searched for, not the word: `grep dijo`
    # passed green with the guard neutralized to `true ||`, because the
    # `dijo=1` assignments were still there. A check satisfied by the
    # name appearing does not measure the guard, it measures the
    # spelling.
    sed -n '/^despachar() {/,/^}/p' "$CHQ" | grep -qE '\(\(\s*dijo\s*\)\)\s*\|\|\s*aviso' \
        || D93="$D93 despachar does not carry the «if it said nothing, it is a warning» guard — without that line it is the old case under another name;"
    # 2) exiting with success from an error handler.
    BAD93="$(python3 - "$CHQ" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
bad = []
for n, l in enumerate(lines):
    if not re.match(r"\s*except\b.*:\s*$", l):
        continue
    indent = len(l) - len(l.lstrip())
    # the handler's body: the lines indented more than the `except`
    for m in lines[n + 1:]:
        if not m.strip():
            continue
        if len(m) - len(m.lstrip()) <= indent:
            break
        if re.match(r"\s*sys\.exit\(0\)", m):
            bad.append(f"line {n + 1}: {l.strip()} … {m.strip()}")
        if m.strip().startswith(("print", "sys.exit")):
            break
print("\x1e".join(bad))
PY
)"
    [[ -z "$BAD93" ]] \
        || D93="$D93 error handler(s) that exit WITH SUCCESS and in silence [$(printf '%s' "$BAD93" | tr '\036' ';')] — the empty output reads exactly like «I measured and there was nothing»;"
    # 3) degradation counts.
    grep -q '^degradado() {.*avisos=' "$CHQ" \
        || D93="$D93 degradado() is missing (or stopped adding warnings): a weakened measurement would go back to being reported only in grey;"
    # And that it is USED. A helper nobody calls is a reverted helper:
    # degradation went back to being a grey note and the file still has
    # the function as an alibi. If some day no measurement degrades, the
    # right thing is to delete degradado(), not leave it dead — the same
    # rule as aegis dev seed's exclusions.
    N_DEG="$(grep -cE '^\s*degradado ' "$CHQ" || true)"
    [[ "$N_DEG" -ge 1 ]] \
        || D93="$D93 degradado() exists and nobody calls it: either degradation went back to being reported in grey, or the function is surplus;"
    grep -qE '^nota\(\)\s+\{[^}]*avisos=' "$CHQ" \
        && D93="$D93 nota() started counting warnings: then it no longer serves as a detail line of a failure/warning and every detail inflates the tally;"
fi
if [[ -n "$D93" ]]; then fail "the round can fall silent:$D93"
else pass "the round has no way of falling silent: a single dispatch with its guard, no except that exits with success, and degradation counts ($N_DEG use(s)) while nota() still does not count"; fi
}
