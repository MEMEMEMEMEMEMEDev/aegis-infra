# teeth of check 166 — a pipeline does not name a variable after a word
# the language reserves.

# THE STATE THE ARTIFACT WAS IN on 2026-09-01: engine-gpu declared
# `def short`. Groovy reserves it, the file did not parse, and the
# four-hour GPU build died in 22 seconds having built nothing.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Jenkinsfile" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("def commit = sh(", "def short = sh(", 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# another keyword, another lane: the class is not one word.
red_2() {
    python3 - "$AEGIS_ROOT/seed/platform/ai/engine-cpu/Jenkinsfile" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("def version = sh(", "def package = sh(", 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# and in the pipeline every application derives from, which would take
# every organization's builds down with it.
red_3() {
    python3 - "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'\bdef ([A-Za-z_][A-Za-z0-9_]*) =', 'def int =', s, count=1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# THE SILENT SCANNER, and the reason this tooth exists at all: the
# first version of the check used a malformed sed, it printed nothing,
# and the check reported ALL PASS over a file that did not parse. A
# scan that dies must take the check down with it, never wave it
# through.
red_4() {
    printf '\nraise SystemExit("the scanner is broken")\n' \
        >> "$AEGIS_ROOT/verify/checks/166.py"
}

# control: PROSE naming the keyword is how the bug gets explained —
# the comment right above the fix says «def short» on purpose. A check
# that reads its own documentation as the defect is the trap corrected
# in 161, 163 and 165, and hit again here.
control_1() {
    printf '\n// note: never `def short` — Groovy reserves it. Use commit.\n' \
        >> "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Jenkinsfile"
}

# control: the `//` of a URL does not open a comment, so what follows
# it on the line stays visible to the scan.
control_2() {
    printf '\n// see https://groovy-lang.org/syntax.html for the reserved words\n' \
        >> "$AEGIS_ROOT/seed/platform/ai/engine-cpu/Jenkinsfile"
}
