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
# EVERY non-colour treatment of `unseen`, not just the chip's. This
# removed the chip's hatch and nothing else, and stopped biting the day
# the builds panel gave a second element one — the check was satisfied
# by a rule this tooth had never heard of. What it has to produce is a
# skin where `unseen` is told apart BY COLOUR ALONE, wherever it is
# drawn, which is the thing the check forbids.
out = []
for rule in re.split(r"(?<=\})", s):
    if "unseen" in rule and re.search(r"background-image|border-radius|box-shadow:\s*inset|border:", rule):
        rule = re.sub(r"(background-image|border-radius|box-shadow|border)\s*:[^;}]*;?", "", rule)
    out.append(rule)
after = "".join(out)
assert after != s, "re-aim this tooth: nothing dresses `unseen` beyond its colour"
p.write_text(after)
P
}

# a state loses its rule entirely: it renders unstyled, which on this
# page reads as nothing being there
red_2() { python3 - "$S124" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
# every rule that gives `busy` a surface or an ink, gone
out = []
for rule in re.split(r"(?<=\})", s):
    if '[data-state="busy"]' in rule:
        rule = re.sub(r"\b(background|background-color|color)\s*:[^;}]*;?", "", rule)
    out.append(rule)
after = "".join(out)
assert after != s, "re-aim this tooth: nothing dresses `busy`"
p.write_text(after)
P
}

# the same, for the one that asks a person for a decision
# A state loses its surface and its ink EVERYWHERE, not only in the one
# rule that used to be its only one. Deleting the base line stopped
# biting the day the panel gave `attention` a second rule of its own:
# the state was still dressed, by something this tooth had never heard
# of, and the check was right to stay green.
red_3() { python3 - "$S124" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
out = []
for rule in re.split(r"(?<=\})", s):
    if '[data-state="attention"]' in rule:
        rule = re.sub(r"\b(background|background-color|color)\s*:[^;}]*;?", "", rule)
    out.append(rule)
after = "".join(out)
assert after != s, "re-aim this tooth: nothing gives `attention` a surface"
p.write_text(after)
P
}

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
