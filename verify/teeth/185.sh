# teeth of check 185 — a command another command delegates to accepts
# --json where the caller actually puts it.

# THE STATE THE ARTIFACT WAS IN until 2026-09-03: --json was declared
# only before the verb, run_json always puts it after, and `aegis app
# apply` could not register a single webhook on a fresh installation.
red_1() {
    python3 - "$AEGIS_ROOT/libexec/aegis-webhook" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r'\n    flags = argparse\.ArgumentParser\(add_help=False\)\n.*?\n    sub = p\.add_subparsers\(dest="verb"\)\n'
              r'    sub\.add_parser\("check", parents=\[flags\],\n[^\n]*\n'
              r'    sub\.add_parser\("apply", parents=\[flags\],\n[^\n]*\n', s, re.S)
assert m, "the shared flags block could not be located"
viejo = ('\n    sub = p.add_subparsers(dest="verb")\n'
         '    sub.add_parser("check", help="measures: do all the repos with a job have a webhook?")\n'
         '    sub.add_parser("apply", help="creates the missing ones and re-syncs the HMAC")\n')
open(p, "w", encoding="utf-8").write(s.replace(m.group(0), viejo, 1))
PYEOF
}

# The subparser declares it but writes its own default over a --json
# that came BEFORE the verb. This is the trap the fix was built around:
# without SUPPRESS, repairing one order breaks the other, and the check
# has to see it because run_json is not the only caller.
red_2() {
    sed -i 's|                       default=argparse.SUPPRESS,|                       default=False,|' \
        "$AEGIS_ROOT/libexec/aegis-webhook"
}

# control: the PROSE that explains the contract, in the file that
# implements it and in the same words. The check RUNS the parser
# instead of reading it precisely so a paragraph cannot stand in.
control_1() {
    python3 - "$AEGIS_ROOT/libexec/aegis-webhook" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "    flags = argparse.ArgumentParser(add_help=False)\n"
nota = ("    # note: cli.run_json appends --json at the END, so `webhook apply\n"
        "    # --json` is the shape a delegating command really uses.\n")
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, nota + anchor, 1))
PYEOF
}

# control: one more verb sharing the same flags. Growing the surface
# correctly is not a defect; the guarantee is about the position.
control_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-webhook" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '    sub.add_parser("apply", parents=[flags],\n'
assert s.count(anchor) == 1
extra = ('    sub.add_parser("list", parents=[flags],\n'
         '                   help="prints the webhooks that exist")\n')
i = s.index(anchor)
j = s.index("\n", s.index("help=", i)) + 1
open(p, "w", encoding="utf-8").write(s[:j] + extra + s[j:])
PYEOF
}
