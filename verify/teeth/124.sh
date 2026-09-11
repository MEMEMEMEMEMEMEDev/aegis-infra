# teeth for check 124 (the skin dresses every state)
#
# Every red is a stylesheet edit somebody makes in good faith while
# tidying, and every one of them undoes, in the last layer, what the
# CLI and the renderer spent 190 checks keeping apart. None of them
# breaks a page: the HTML is identical and the console looks calmer.

S124="$AEGIS_ROOT/share/console/sereno.css"

# THE ONE. «Grey with a hatch is fussy» — and the fourth outcome becomes
# a paler shade of the others, indistinguishable on a printed page or to
# an eye that does not see red.
red_1() { python3 - "$S124" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = re.sub(r'\.chip\[data-state="unseen"\]::before \{[^}]*\}', '', s)
s = s.replace('.chip[data-state="unseen"] { box-shadow:none; }', '')
p.write_text(s)
P
}

# a state loses its rule entirely: it renders unstyled, which on this
# page reads as nothing being there
red_2() { sed -i '/^\[data-state="busy"\]/d' "$S124"; }

# the same, for the one that asks a person for a decision
red_3() { sed -i '/^\[data-state="attention"\]/d' "$S124"; }

# ── controls: real changes that must NOT move the verdict ────────────

# the palette is repainted whole: every colour changes and not one
# guarantee does. The skin is allowed to be a matter of taste; what it
# may not do is lose a state.
control_1() { python3 - "$S124" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
p.write_text(re.sub(r"#[0-9A-Fa-f]{6}", "#123456", s))
P
}

# a state gains a second way of being told apart: more distinction is
# never a regression
control_2() { printf '\n[data-state="wrong"] { border-left:3px solid currentColor; }\n' >> "$S124"; }

# prose that names the defect right next to the rule that prevents it
control_3() { printf '\n/* history: «unseen» was almost just a grey. It is not: a grey is a\n * shade of the others, and this state is a different KIND of answer. */\n' >> "$S124"; }
