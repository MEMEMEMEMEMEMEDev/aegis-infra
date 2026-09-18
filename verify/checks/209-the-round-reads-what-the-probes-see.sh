# title: the round reads what the tenant probes SEE, not only that they exist
# origin: new in v3 — 2026-09-18, the acceptance of an update window rests on this line (plan/17)
check() {
# COUNTING WATCHERS IS NOT WATCHING.
#
# Until 2026-09-18 this section counted that every organization with a
# domain had a blackbox probe, and stopped there. A tenant returning
# 500 to every customer passed it: the probe existed, the count matched,
# the line was green. The only place the truth lived was an alert, and
# an alert is what wakes somebody at 3am — not what the operator reads
# when they ask «how is it».
#
# It matters twice as much now: «every public site answers» is one of
# the three legs of the acceptance an update window rolls back on. A
# window cannot accept on a measurement the round does not take.
#
# And the read has to tell THREE things apart, because two of them are
# not failures: a site that does not answer at all, a site that answers
# with a redirect the module refuses on purpose (its own login, or
# Access), and a site that answers. Collapsing the middle one into
# «down» would make this line permanently red on any instance with a
# tenant behind Access — and a signal that never changes is a signal
# nobody reads.
D209=""
[[ -f "$LIBEXEC/aegis-check" ]] || { skip "there is no round: nothing reads a probe"; return; }

BODY209="$(nc "$LIBEXEC/aegis-check")"

grep -q 'probe_success{job=~"sitio-\.\*"}' <<<"$BODY209" \
    || D209="$D209 the round never reads probe_success for the tenant jobs: it counts that the probes exist and never what they see;"

grep -qE 'probe_http_status_code' <<<"$BODY209" \
    || D209="$D209 the round reads probe_success and not the status code beside it: a redirect to a login and a site that is down would be reported as the same thing;"

# The verdict has to be able to be BAD. A read whose only outcome is a
# note is a measurement nobody acts on.
if ! grep -B4 -A12 'probe_success{job=~"sitio-\.\*"} == 0' <<<"$BODY209" | grep -q 'bad '; then
    D209="$D209 nothing in the block that reads the probes can report a failure: a site that is down would be a note;"
fi

printf '    %s\n' "$(grep -c 'probe_success' <<<"$BODY209") read(s) of probe_success in the round"
if [[ -n "$D209" ]]; then
    fail "the round does not read what the probes see:$D209"
else
    pass "the round reads probe_success and its status code, and a site that does not answer is a failure"
fi
}
