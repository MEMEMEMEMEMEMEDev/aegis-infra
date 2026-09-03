# teeth of check 182 — a task that cannot fit its own prompt is refused
# where the contract is written.

# THE STATE THE ARTIFACT WAS IN until 2026-09-02: nothing multiplied a
# prompt against the ceiling meant to hold it, and a task shipped that
# could not answer one character.
red_1() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r'\n            _texto = prompts\.get.*?in front of a visitor\."\)\n',
              s, re.S)
assert m, "the guard could not be located"
open(p, "w", encoding="utf-8").write(s.replace(m.group(0), "\n", 1))
PYEOF
}

# present but toothless: an estimate ten times too generous accepts a
# prompt that fills the window on its own.
# The mutation targets the DIVISOR and nothing else. Naming the whole
# expression made this tooth inert the moment the arithmetic was
# corrected, on the same day it was written.
red_2() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
nuevo, n = re.subn(r'(^\s*_piso = .*?) // 4\b', r'\1 // 40', s, count=1, flags=re.M)
assert n == 1, "the divisor of the floor could not be located"
open(p, "w", encoding="utf-8").write(nuevo)
PYEOF
}

# it refuses, and does not say what to change. The operator is left with
# a wall and no door.
red_3() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
viejo = ('f"  {e[\'max_context_tokens\']}. Raise max_context_tokens for this task in\\n"\n'
         '                        f"  ai/tasks.yaml under `tareas:`, or shorten the prompt. Leaving it\\n"\n')
nuevo = 'f"  {e[\'max_context_tokens\']}. Leaving it\\n"\n'
assert s.count(viejo) == 1, s.count(viejo)
open(p, "w", encoding="utf-8").write(s.replace(viejo, nuevo, 1))
PYEOF
}

# the escape hatch the message names does not work: the guard compares
# against the CLASS default and ignores the per-task override, so
# raising the number changes nothing and the advice is a lie.
red_4() {
    sed -i 's|{e\[.max_context_tokens.\]}. Raise max_context_tokens|{classes[cls]["max_context_tokens"]}. Raise max_context_tokens|; s|if _piso >= e\["max_context_tokens"\]:|if _piso >= classes[cls]["max_context_tokens"]:|' \
        "$AEGIS_ROOT/lib/aegis/org.py"
}

# control: the PROSE that argues the rule, in the same file and in the
# same words as the rule. Explaining is not enforcing, and this check
# calls the generator instead of reading it precisely so the paragraph
# cannot stand in for the arithmetic.
control_1() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "    tasks = {}\n"
nota = ("    # note: a task has to fit inside itself — its prompt plus what it\n"
        "    # may answer, against its max_context_tokens — or it cannot answer\n"
        "    # a single character and fails as a 400 in front of a visitor.\n")
assert s.count(anchor) >= 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, nota + anchor, 1))
PYEOF
}

# control: a task with a GENEROUS ceiling in the seed's own defaults.
# Room to spare is the rule working, not a defect, and a check that
# turned red on it would forbid raising a limit.
control_2() {
    python3 - "$AEGIS_ROOT/seed/platform/ai/tasks.yaml" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "  interactive:\n"
assert s.count(anchor) == 1
bloque = ("  interactive_amplia:\n"
          "    max_output_tokens: 220\n"
          "    max_context_tokens: 8000\n"
          "    max_input_chars: 2600\n"
          "    temperature: 0.6\n"
          "    peso: 1\n")
open(p, "w", encoding="utf-8").write(s.replace(anchor, bloque + anchor, 1))
PYEOF
}
