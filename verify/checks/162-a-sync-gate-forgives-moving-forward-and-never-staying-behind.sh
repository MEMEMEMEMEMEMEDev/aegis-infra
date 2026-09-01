# title: a sync gate forgives moving forward and never forgives staying behind
# origin: new in v3 — 2026-09-01, after a correct cluster failed a 300 s gate
check() {
# `argo_secrets_gate` exists because of a real fault (F-B #15): a sync
# died from a transient DNS error and the App still read «Synced» — to
# the OLD revision. The fix asked for the just-pushed sha, and that
# was right.
#
# What it got wrong is the SHAPE of the question. The platform repo is
# not written only by the init: the base-images job pushes back the
# digest of the base it just built, and that push lands between a
# phase's push and ArgoCD's sync. The App then sits on a revision
# NEWER than the phase's, which is exactly correct, and a gate
# demanding equality waits out its whole timeout against a healthy
# cluster. Measured on 2026-09-01: phase 80 pushed at 09:27:58,
# base-images pushed on top at 09:31:29, the gate died at 09:39:01.
#
# The class this check watches is therefore not «git»: it is A GATE
# THAT MISTAKES A DIFFERENT STATE FOR A WORSE ONE. Ahead and behind
# are not the same failure, and a gate that cannot tell them apart
# either blocks a correct install (this bug) or passes a stale one
# (the bug it was born for). Three things have to hold:
#
#   1. the gate does not decide with a bare string comparison;
#   2. the direction is asymmetric and points forward — ancestry asked
#      as «is the pushed commit an ancestor of the live one». Reversed,
#      it accepts precisely the stale sync F-B #15 was about;
#   3. a caller that derives its sha from a clone HANDS OVER that
#      clone. Ancestry needs the objects; without them the gate falls
#      back to the strict question, so a caller that forgets the clone
#      silently loses the fix and gets the timeout back.
C="$AEGIS_ROOT/lib/common.sh"
[[ -f "$C" ]] || { fail "there is no lib/common.sh: $C"; return; }
grep -q 'argo_secrets_gate()' "$C" \
  || { skip "lib/common.sh no longer defines argo_secrets_gate"; return; }

D162=""

# (1)+(2): the decision, and its direction
if ! grep -q '_rev_is_applied' "$C"; then
    D162="$D162 argo_secrets_gate decides whether the push arrived without any ancestry test: a revision that is NEWER than the pushed one is read as one that stayed behind, and a correct install waits out the timeout;"
else
    grep -q 'merge-base --is-ancestor "\$expected" "\$live"' "$C" \
      || D162="$D162 the ancestry test is not asked as 'is the pushed commit an ancestor of the live one' — with the arguments the other way round the gate accepts a sync that STAYED BEHIND, which is the fault (F-B #15) it exists to catch;"
    grep -q 'argo_secrets_gate' "$C" && \
    grep -q '_rev_is_applied "\$expected" "\$revs" "\$repo"' "$C" \
      || D162="$D162 argo_secrets_gate does not route its decision through _rev_is_applied: the helper is there and the gate does not use it;"
fi

# (3): every caller that measures a clone hands the clone over
while IFS= read -r f; do
    # the call may span lines: join continuations before reading it
    python3 - "$f" <<'PY' || D162="$D162 (see the detail above);"
import re, sys
p = sys.argv[1]
src = open(p, encoding="utf-8").read().replace("\\\n", " ")
bad = []
for line in src.splitlines():
    if "argo_secrets_gate" not in line or line.lstrip().startswith("#"):
        continue
    m = re.search(r'git -C "?\$\{?(\w+)\}?"? rev-parse', line)
    if not m:
        continue                      # no local clone to hand over
    var = m.group(1)
    tail = line[m.end():]
    if not re.search(r'"\$\{?' + var + r'\}?"', tail):
        bad.append(line.strip())
if bad:
    print(f"{p}: derives the expected revision from a clone and does not pass it as the "
          f"fourth argument, so the gate falls back to the strict comparison:", file=sys.stderr)
    for b in bad:
        print("   " + b, file=sys.stderr)
    sys.exit(1)
PY
done < <(grep -rl 'argo_secrets_gate' "$AEGIS_ROOT/init/phases/" 2>/dev/null)

NCALL="$(grep -rc 'argo_secrets_gate' "$AEGIS_ROOT/init/phases/" 2>/dev/null \
        | awk -F: '{n+=$2} END{print n+0}')"
printf '    %s call sites of the sync gate · decided by %s\n' \
    "$NCALL" "$(grep -q '_rev_is_applied' "$C" && echo ancestry || echo 'string equality')"
if [[ -n "$D162" ]]; then fail "a sync gate cannot tell ahead from behind:$D162"
else pass "the sync gate accepts a revision that descends from the pushed one, still refuses one that stayed behind, and every caller that derives its sha from a clone hands that clone over"; fi
}
