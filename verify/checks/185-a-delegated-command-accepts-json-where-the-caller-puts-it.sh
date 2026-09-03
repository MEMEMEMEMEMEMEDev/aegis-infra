# title: a command another command delegates to accepts --json where the caller actually puts it
# origin: new in v3 — 2026-09-03, after app apply could not register a single webhook
check() {
# MEASURED 2026-09-03, installing from zero.
#
# `cli.run_json` appends `--json` at the END of whatever it was handed,
# so a delegating command always says `<cmd> <verb> --json`. That is
# the contract, and it is invisible: nothing in the delegate's source
# says which POSITION its caller will use.
#
# `aegis webhook` declared `--json` only before the verb. argparse
# answered «unrecognized arguments: --json», run_json could not parse
# the output, and what the operator saw was
#
#     ! webhooks: COULD NOT EVALUATE — aegis webhook --json did not
#       return a readable document
#
# a sentence about the SHAPE OF THE OUTPUT when the fault was the shape
# of the input. `aegis app apply` could not register one webhook, and
# the repos of a fresh installation sat there with no delivery.
#
# The check is behavioural and derives its own subject: it finds every
# command `run_json` delegates to and reads that command's own
# `# aegis-subcommands:` header for its verbs.
#
# HOW IT ASKS WITHOUT TOUCHING ANYTHING, because the obvious way does
# not work: `<verb> --json --help` is useless — argparse serves --help
# and exits BEFORE it complains about an unknown flag, so the probe
# comes back clean over a parser that would have refused. Measured
# while writing this check, and it is the reason it looks odd.
#
# What works is an invalid POSITIONAL: `<verb> --json __aegis_probe__`
# always ends in «unrecognized arguments», and the question is whether
# `--json` is NAMED in that list. argparse decides it before the
# program body runs, so nothing is created, deleted or contacted.
#
# And a second question, for the read-only verb the house convention
# calls `check`: the two ORDERS have to agree. A subparser that
# declares --json with a normal default writes its own False over a
# --json that came before the verb, so repairing one order silently
# breaks the other. Comparing whether both outputs are JSON catches
# that without needing a cluster: it asks them to agree, not to
# succeed.
D185=""
[[ -d "$AEGIS_ROOT/libexec" ]] || { skip "there is no libexec/: nothing delegates"; return; }

# Who is delegated to. Derived from the call sites, never listed here:
# a check with its own roster of delegations is one more place to go
# stale, and staleness is the disease this whole family treats.
CMDS="$(grep -rhoE 'run_json\("[a-z-]+"' "$AEGIS_ROOT/libexec/" 2>/dev/null \
        | sed -E 's/run_json\("([a-z-]+)"/\1/' | sort -u)"
if [[ -z "$CMDS" ]]; then
    skip "nothing in libexec/ delegates through run_json: this check has no subject"
    return
fi

N=0
for c in $CMDS; do
    f="$AEGIS_ROOT/libexec/aegis-$c"
    [[ -f "$f" ]] || { D185="$D185 something delegates to \`$c\` and libexec/aegis-$c does not exist;"; continue; }
    verbs="$(head -20 "$f" | sed -nE 's/^#[[:space:]]*aegis-subcommands:[[:space:]]*(.*)$/\1/p' | head -1)"
    [[ -n "$verbs" ]] || continue     # no subcommands: --json can only go in one place
    for v in $verbs; do
        N=$((N + 1))
        # ONLY the «unrecognized arguments:» line. argparse prints a
        # usage line beside it that lists [--json] whether or not the
        # flag was accepted, and reading that instead is a false red —
        # measured while writing this check, over its own controls.
        out="$("$AEGIS_ROOT/bin/aegis" "$c" "$v" --json __aegis_probe__ 2>&1 \
               | grep -i 'unrecognized arguments' | head -1)"
        if grep -q -- '--json' <<< "$out"; then
            D185="$D185 \`aegis $c $v --json\` is refused by its own parser, and that is exactly how run_json calls it: the caller gets no document and reports COULD NOT EVALUATE, never a syntax error;"
        fi
    done

    # AND THE TWO ORDERS MUST NOT FIGHT. When the same flag is declared
    # at the top level AND on the subparsers, argparse writes the
    # subparser's default over whatever the earlier one set: `<cmd>
    # --json <verb>` silently loses it, so repairing one order breaks
    # the other. `argparse.SUPPRESS` is the one default that does not
    # overwrite, which makes its presence the invariant here.
    #
    # Measured, and this is why it is asserted on the source instead of
    # by running the command: the behavioural version of this question
    # has to invoke a verb for real, and a verb that reaches GitHub
    # answers differently under load. A check that is right only on a
    # quiet machine is not a check.
    _code="$(grep -vE '^[[:space:]]*#' "$f")"
    if [[ "$(grep -c -- '--json' <<< "$_code")" -ge 2 ]] \
       && ! grep -q 'argparse.SUPPRESS' <<< "$_code"; then
        N=$((N + 1))
        D185="$D185 aegis-$c declares --json in more than one place and none of them suppresses its default: argparse then writes the subparser's value over a --json given BEFORE the verb, so one of the two orders loses the flag silently;"
    fi
done

printf '    %s (command, verb) pairs probed, derived from the run_json call sites\n' "$N"
if [[ -n "$D185" ]]; then fail "a delegation cannot work because of where the flag goes:$D185"
else pass "every verb of every command reached through run_json accepts --json in the position run_json puts it"; fi
}
