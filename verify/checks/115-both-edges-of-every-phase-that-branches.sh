# title: every phase that branches on EDGE serves BOTH edges, and no gate vanishes
# origin: new in v3 — T-04a (2026-08-26), the local edge
check() {
# The seed is identical on both edges ON PURPOSE, so the whole
# difference between EDGE=cloudflare and EDGE=local lives in the
# phases. That makes the phases the only place where the local edge can
# be half-built, and nothing else in this verifier looks at them from
# that angle: check 017 sees the files a phase names, 103 the commands
# it names, 054 how it records a gate — none of them asks whether the
# phase still does its job on the OTHER edge.
#
# Three ways it breaks, and the first is the one that already happened.
#
# (1) THE MISSING DEFAULT. Every phase runs in its own subshell
#     (`( source "$p" )` in aegis-init), so the `EDGE="${EDGE:-cloudflare}"`
#     that config_validate applies dies with phase 00. On an instance
#     whose conf was written before EDGE existed the variable is simply
#     absent, and under `set -euo pipefail` a bare "$EDGE" does not fall
#     back to anything: it kills the phase with «unbound variable».
#     Measured on 2026-08-26: phases 15 and 85 carried sixteen of these
#     between them, so every instance created before that day would have
#     died at phase 15 on its next run.
#
# (2) A BRANCH THAT DOES NOTHING. An `if EDGE==local` with no body, or
#     with a body that only logs, is a phase that silently does not do
#     its job on that edge — and silence is the one thing this whole
#     project treats as red.
#
# (3) A GATE THAT VANISHES. If the cloudflare branch emits a gate and
#     the local one emits nothing in its place, that gate does not fail:
#     it disappears from gates.jsonl, and three months later a missing
#     line reads exactly like a green one. Saying so is what
#     gate_no_subject is for, and this is what makes anyone use it.
D115="" ; N115=0

if python3 - "$PHASES" <<'EOF'
import pathlib, re, sys

PH = pathlib.Path(sys.argv[1])
bad, n_branching = [], 0

# A gate emitted for real vs one declared to have no subject here.
# gate_red is NOT in this list and it is not an oversight: its first
# argument is the WHY shown to the operator, not a gate name — including
# it made this check accuse a confirmation prompt of being a vanished
# gate.
EMIT = re.compile(r'^\s*(?:gate|gate_diag)\s+"([^"]+)"', re.M)
NOSUB = re.compile(r'^\s*gate_no_subject\s+"([^"]+)"', re.M)
RECORD = re.compile(r'^\s*_gate_record\s+"([^"]+)"', re.M)
# an EDGE comparison, guarded or not
COND = re.compile(r'\[\[\s*"(\$EDGE|\$\{EDGE:-cloudflare\})"\s*==\s*(local|cloudflare)\b')

for f in sorted(PH.glob("[0-9][0-9]-*.sh")):
    raw = f.read_text()
    # comments tell the story and may say anything: only code counts
    code = "\n".join(l for l in raw.splitlines() if not l.lstrip().startswith("#"))
    conds = COND.findall(code)
    if not conds:
        continue
    n_branching += 1

    # (1) the default
    for var, _edge in conds:
        if var == "$EDGE":
            bad.append(f"{f.name}: compares a bare \"$EDGE\" — with a conf written before "
                       "EDGE existed the variable is absent and `set -u` kills the phase "
                       'with «unbound variable»; it has to be "${EDGE:-cloudflare}"')
            break

    # (2) a branch with a body
    for m in re.finditer(r'if\s+\[\[\s*"[^"]*EDGE[^"]*"\s*==\s*(local|cloudflare)\b[^\n]*\n(.*?)^(?:\s*)(?:else|elif|fi)\b',
                         code, re.M | re.S):
        edge, body = m.group(1), m.group(2)
        meaningful = [l for l in body.splitlines()
                      if l.strip() and not re.match(r'^\s*(:|true)\s*$', l)]
        if not meaningful:
            bad.append(f"{f.name}: the {edge} branch has an EMPTY body — a phase that does "
                       "nothing on an edge and says nothing about it is the silence this "
                       "verifier exists to make impossible")

    # (3) no gate that cloudflare has DISAPPEARS on local
    #
    # The asymmetry is deliberate. cloudflare is the established edge:
    # a gate it emits and local does not is something that STOPPED being
    # measured, and that has to be said out loud with gate_no_subject.
    # The other direction is a gain — `edge-name-resolves` or
    # `edge-bridge-listens-only-on-bind-ip` measure mechanisms cloudflare
    # does not have, and demanding a declaration for them would be
    # demanding that the local edge apologise for existing.
    #
    # The region of a branch is found BY INDENTATION and not by counting
    # if/fi: the first version tracked depth, missed single-line `if …;
    # fi` and `case/esac`, never came back to zero, and scanned the rest
    # of the file — so it accused seven gates of phase 00 that have
    # nothing to do with the edge. The tree is formatted consistently,
    # and the closing `else`/`fi` of a branch sits at the same column as
    # its `if`.
    lines = code.splitlines()

    def region(i):
        """the body of the branch that opens at line i, up to its else/fi"""
        indent = len(lines[i]) - len(lines[i].lstrip())
        out = []
        for j in range(i + 1, len(lines)):
            s = lines[j]
            if s.strip() and (len(s) - len(s.lstrip())) == indent \
               and re.match(r'^(else|elif|fi)\b', s.strip()):
                break
            out.append(s)
        return "\n".join(out)

    per_edge = {"cloudflare": set(), "local": set()}
    for i, line in enumerate(lines):
        mm = COND.search(line)
        if not mm or not line.lstrip().startswith(("if", "elif")):
            continue
        edge = mm.group(2)
        body = region(i)
        per_edge[edge] |= set(EMIT.findall(body))
        # the `else` of an `if EDGE == X` belongs to the OTHER edge
        other = "local" if edge == "cloudflare" else "cloudflare"
        indent = len(line) - len(line.lstrip())
        for j in range(i + 1, len(lines)):
            s = lines[j]
            if s.strip() and (len(s) - len(s.lstrip())) == indent \
               and re.match(r'^(else|elif|fi)\b', s.strip()):
                if s.strip().startswith("else"):
                    per_edge[other] |= set(EMIT.findall(region(j)))
                break

    declared = set(NOSUB.findall(code)) | set(RECORD.findall(code))
    lost = per_edge["cloudflare"] - per_edge["local"] - declared
    for g in sorted(lost):
        bad.append(f"{f.name}: the gate '{g}' is emitted under cloudflare and NOT under "
                   "local, and it is never declared with gate_no_subject — on that edge it "
                   "does not fail, it DISAPPEARS from gates.jsonl, and a missing line reads "
                   "the same as a green one")

print(f"    {n_branching} phases branch on EDGE")
for b in bad:
    print(f"    {b}")
sys.exit(1 if bad else 0)
EOF
then :; else D115="$D115 (see the detail above);"; fi

if [[ -n "$D115" ]]; then fail "a phase does not serve both edges:$D115"
else pass "every phase that branches on EDGE defaults to cloudflare, gives both branches a body, and declares the gates the other edge cannot measure"; fi
}
