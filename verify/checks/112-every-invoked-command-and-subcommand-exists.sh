# title: every command a phase invokes exists, and so does its subcommand
# origin: new in v3 — the dead call found in phase 85 on 2026-08-24
check() {
# Phase 85 step 85.6 read, until 2026-08-24:
#
#     run_cmd bash -c "cd '$PLATFORM_DIR' && bin/aegis-org borde"
#
# and it was dead in TWO ways at once. The code no longer lives in the
# instance —it moved to the product, and check 134 forbids the seed
# from carrying executables at all, so that path cannot exist by
# construction— and the subcommand had been renamed `borde` -> `edge`
# when the CLI surface went English. Either one alone was fatal. The
# phase would have died at 85.6 on the first real run.
#
# Nobody was watching. Check 017 verifies that the FILES a phase
# references exist; check 106 verifies that the commands the DOCS cite
# exist; check 103 verifies that no MESSAGE names a command by hand.
# Between them there was a hole exactly the shape of "a phase invoking
# a command", and the most expensive kind of code fell through it: the
# kind that only runs during a real installation.
#
# So this check asks the two questions that line failed:
#
#   (a) does the command exist? — derived from libexec/, never a list;
#   (b) does the SUBCOMMAND exist? — derived from the command's own
#       `# aegis-subcommands:` metadata, the same source the menu and
#       check 106 read. A command without that line declares that it
#       takes no subcommand, and nothing is checked for it.
#
# And it refuses any invocation through a PATH. `aegis` is on PATH from
# phase 05 onward (the dispatcher is symlinked into /usr/local/bin), so
# an invocation that needs a directory to work is one that breaks the
# day the directory moves — which is precisely what happened.
#
# HISTORY. The first version (2026-08-24) was parked in a scratchpad and
# lost with it. Rewritten on 2026-08-26 from the transcript, minus three
# defects it carried: a backtick inside a double-quoted message that
# EXECUTED `aegis` while composing the failure text; a `sed 's/^/x:/'`
# that replaced every file name with the letter x; and comments read
# through `grep -rho`, so a comment quoting the old call would have
# turned it red.
D112="" ; N112=0
INVOKERS="$(find "$PHASES" "$LIBEXEC" -type f 2>/dev/null | sort)"

for f in $INVOKERS; do
    b="$(basename "$f")"
    # (a) + the path form: nobody calls a command through bin/ any more.
    # A backtick-quoted span is a CITATION (a docstring telling where the
    # code used to live), not an invocation: it is stripped first.
    HITS="$(nc "$f" 2>/dev/null | sed 's/`[^`]*`//g' | grep -oE '(\$[A-Z_]+/)?bin/aegis-[a-z-]+' | sort -u || true)"
    [[ -n "$HITS" ]] && D112="$D112 $b invokes a command through a path (${HITS//$'\n'/ }): the code lives in the product and the dispatcher is on PATH;"

    # (b) the subcommand, against the metadata of the command it belongs
    # to. Only the derived form is an invocation (check 103 already
    # forbids the literal one); a flag after the command is not a
    # subcommand.
    while IFS= read -r inv; do
        [[ -z "$inv" ]] && continue
        cmd="${inv%% *}"; sub=""
        [[ "$inv" == *" "* ]] && sub="${inv#* }"
        N112=$((N112+1))
        target="$LIBEXEC/aegis-$cmd"
        if [[ ! -f "$target" ]]; then
            D112="$D112 $b invokes '$cmd', and libexec/aegis-$cmd does not exist;"
            continue
        fi
        SUBS="$(sed -n '1,20{s/^# aegis-subcommands:[[:space:]]*//p}' "$target" | head -1)"
        [[ -z "$SUBS" || -z "$sub" ]] && continue
        grep -qw -- "$sub" <<<"$SUBS" \
            || D112="$D112 $b invokes '$cmd $sub' and aegis-$cmd only declares: $SUBS;"
    done <<< "$(nc "$f" 2>/dev/null \
                | grep -oE '\$\{AEGIS_CMD:-aegis\}[[:space:]]+[a-z][a-z-]*([[:space:]]+[a-z][a-z-]*)?' \
                | sed 's/${AEGIS_CMD:-aegis}[[:space:]]*//' | sort -u)"
done

printf '    %s invocations checked against libexec/ and its metadata\n' "$N112"
if [[ -n "$D112" ]]; then fail "an invoked command or subcommand does not exist:$D112"
else pass "every command a phase or another command invokes exists, its subcommand is declared, and none is reached through a path"; fi
}
