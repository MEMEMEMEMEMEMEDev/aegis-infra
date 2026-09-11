# title: a command that declares --json reads it — the flag is a promise, not decoration
# origin: new in v3 — 2026-09-11, aegis-edge declared --json and discarded parse_args() on the next line
check() {
# THE BUG THIS COMES FROM, and why it survived so long.
#
#   libexec/aegis-edge, until 2026-09-11:
#       ap.add_argument("--json", action="store_true", dest="json_mode", ...)
#       ap.parse_args()          # ← the result, thrown away on the spot
#
# The flag parsed. `aegis edge --json` was accepted, exited 0, and
# printed the very same coloured prose as always. NOTHING FAILED. A
# consumer that trusted the declaration got ANSI escapes where it
# expected a document, and would report «could not evaluate» — a
# sentence about the shape of the OUTPUT when the fault was that the
# input was never read.
#
# That is the shape of the whole disease: a DECLARED CAPABILITY THAT
# DOES NOT EXIST, announced by nothing. It cannot fail loudly, because
# the only thing that would notice is a consumer that does not exist
# yet. Check 185 asks a different question — whether a delegate accepts
# the flag WHERE run_json puts it — and by construction its universe is
# the commands somebody already calls, so a command with no caller yet
# is unwatched by it. This one watches the declaration itself.
#
# WHY IT IS STATIC AND NOT BEHAVIOURAL. The behavioural version would
# have to run each command and compare its output, and a command that
# reaches Cloudflare or GitHub answers differently on a quiet machine
# than on a busy one. The defect, on the other hand, is visible in the
# source with no ambiguity: a `parse_args()` whose result goes nowhere.
D118=""; N118=0

# THE UNIVERSE IS DERIVED, and it is narrower than «the file mentions
# --json»: `cli.py` appends the flag for others and `aegis-preflight`
# CONSUMES a document that somebody else emits. Neither declares an
# argument, and demanding that they read one would be a false red. What
# makes a file a subject is having declared the flag ON A PARSER.
SUBJECTS118="$(grep -rl 'add_argument("--json"' "$LIBEXEC" "$LIBS/aegis" 2>/dev/null | sort)"
# Bash declares it as a branch of its argument loop instead.
SUBJECTS118="$SUBJECTS118 $(grep -rlE '^[[:space:]]*--json\)' "$LIBEXEC" 2>/dev/null | sort)"

if [[ -z "${SUBJECTS118// /}" ]]; then
    skip "no command declares --json on a parser: this check has no subject"
    return
fi

for f in $SUBJECTS118; do
    b="$(basename "$f")"
    code="$(nc "$f" 2>/dev/null)"
    N118=$((N118 + 1))

    # 1 · THE RESULT OF parse_args() IS KEPT. This is the bug itself. A
    #     bare call on its own line parses, validates, and drops
    #     everything on the floor.
    if grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\.parse_args\(\)[[:space:]]*$' <<<"$code"; then
        D118="$D118 $b declares --json and calls parse_args() without keeping the result: the flag is parsed and discarded on the same line, so the command accepts it, exits 0, and does exactly what it did before;"
    fi

    # 2 · AND THE VALUE IS READ SOMEWHERE. Keeping the namespace is not
    #     enough: a command can assign it and still never look at the
    #     flag, which is the same lie one step later. The name to look
    #     for is DERIVED from the declaration — whatever `dest=` says,
    #     or `json` when argparse derives it from the flag itself.
    dests="$(grep -oE 'add_argument\("--json"[^)]*dest="[a-z_]+"' <<<"$code" \
             | sed -E 's/.*dest="([a-z_]+)"/\1/' | sort -u)"
    [[ -n "$dests" ]] || dests="json"
    # PROSE IS NOT CODE, and here that is not a nicety — it is the
    # house rule, learned six times over. The dest argparse derives
    # from this flag is `json`, and aegis-host's own docstrings say
    # «the facts live in $AEGIS_HOME/host.json» four separate times.
    # Every one of those looks exactly like a use of the flag. A
    # paragraph would have vouched for a value nobody reads.
    #
    # So three layers come off before asking: whole-line comments (nc,
    # already), then docstring blocks, then what is left inside quotes.
    code_bare="$(awk '
        BEGIN { d = 0 }
        {
            n = gsub(/"""/, "")
            if (d)            { if (n >= 1) d = 0; next }   # closing, or still inside
            if (n >= 2)       { next }                      # a docstring on one line
            if (n == 1)       { d = 1; next }               # opening
            print
        }' <<<"$code" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')"
    for d in $dests; do
        uses="$(grep -cE "\b[A-Za-z_][A-Za-z0-9_]*\.${d}\b" <<<"$code_bare" || true)"
        if [[ "${uses:-0}" -eq 0 ]]; then
            D118="$D118 $b declares --json as \`$d\` and never reads \`$d\`: the flag is kept and then ignored, which is the same promise broken one line later;"
        fi
    done
done

printf '    %s command(s) declare --json on a parser\n' "$N118"
if [[ -n "$D118" ]]; then
    fail "a declared --json is not honoured:$D118"
else
    pass "every command that declares --json keeps what parse_args() returned and reads it"
fi
}
