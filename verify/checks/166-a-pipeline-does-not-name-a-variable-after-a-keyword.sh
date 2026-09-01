# title: a pipeline does not name a variable after a word the language reserves
# origin: new in v3 — 2026-09-01, after a translation turned a name into a keyword
check() {
# `def short = …` does not parse: short is a primitive type in Groovy,
# like int or byte. The pipeline dies in the parser, BEFORE its first
# stage, so nothing it declares ever runs — no build, no scan, no
# signature, and a stack trace of the Groovy compiler where a build
# log should be.
#
# How it got there is the part worth keeping. This lane's twin,
# engine-cpu, called the same variable `corto` and parsed fine.
# Translating the product into English turned that name into a
# keyword. Nothing measured it because a Jenkinsfile is DATA to the
# artifact: it is shipped, not executed, and the first parse happens
# on an instance, in a phase, at the end of an install. Measured on
# 2026-09-01: engine-gpu had never been parsed by anything, and it
# surfaced as the four-hour GPU build dying in 22 seconds.
#
# The check is narrow on purpose. It does not try to be a Groovy
# parser — it asks the one question with an exact answer: does a `def`
# name collide with a word the language reserves? That list is the
# LANGUAGE's, not the project's, which is why it is written down
# rather than derived: external truth does not drift with the artifact.
KEYWORDS='abstract assert boolean break byte case catch char class const continue
default do double else enum extends final finally float for goto if implements
import instanceof int interface long native new package private protected public
return short static strictfp super switch synchronized this throw throws
transient try void volatile while as in trait null true false'

N="$(find "$AEGIS_ROOT/seed" -name 'Jenkinsfile*' -type f 2>/dev/null | wc -l)"
(( N > 0 )) || { skip "the seed ships no Jenkinsfile"; return; }

D166=""
# The scan is python and not a sed pipeline for a measured reason: the
# first version used sed, the expression was malformed, sed wrote its
# error to stderr and printed NOTHING — so the check found no
# declarations and reported ALL PASS. A scanner that fails silently
# turns a check into decoration. Here a failed scan is a failed check.
if ! OUT="$(KEYWORDS="$KEYWORDS" python3 "$AEGIS_ROOT/verify/checks/166.py" "$AEGIS_ROOT/seed" 2>&1)"; then
    D166="$D166 the scan itself failed and this check measured nothing: $OUT;"
elif [[ -n "$OUT" ]]; then
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        D166="$D166 ${hit#"$AEGIS_ROOT"/} and that word is reserved by the language: the file does not parse, so the pipeline dies before its first stage and NOTHING it declares runs;"
    done <<< "$OUT"
fi

printf '    %s pipelines read · %s reserved words\n' "$N" "$(wc -w <<< "$KEYWORDS")"
if [[ -n "$D166" ]]; then fail "a pipeline names a variable after a keyword:$D166"
else pass "no pipeline in the seed names a variable after a word the language reserves, so every one of them reaches its first stage"; fi
}
