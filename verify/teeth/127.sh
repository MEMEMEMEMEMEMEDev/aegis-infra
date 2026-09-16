# teeth for check 127 (no reading is drawn without its age)
#
# Both reds are a tidy-up. Neither breaks a page, neither changes a
# state, and both turn a console that measured once into one that looks
# like it is measuring continuously.

R127="$AEGIS_ROOT/lib/aegis/console.py"
# The age is drawn by the screens; the attribute by the atom in console.py.
A127="$AEGIS_ROOT/lib/aegis/screens.py"

# «the timestamp is clutter» — and every number on the page starts
# THE AGE STOPS BEING DRAWN, wherever it is drawn from. This named the
# two call sites `_source` had and went quiet on 2026-09-14, when the
# panel started emitting the age from the indicator's summary line and
# from the projects section instead — the check was right to stay green,
# because the age was still on the page, and the tooth was measuring a
# call site rather than the promise.
#
# The promise is that a measurement reaches the screen WITH ITS AGE. So
# the function that draws it is made to draw nothing, which is the only
# mutation that means exactly that wherever it is called from.
red_1() { python3 - "$A127" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
start = s.index("def _age(reading):")
body = s.index("\n\n\n", start)
head = s.index('"""', s.index('"""', start) + 3) + 3
assert start < head < body, "re-aim this tooth"
p.write_text(s[:head] + '\n    return ""\n' + s[body:])
P
}

# the attribute goes, the visible line stays: a machine reading this
# page can no longer tell fresh from stale
red_2() { sed -i "s|return f' data-measured-at=\"{_e(w)}\"' if w else ' data-measured-at=\"unknown\"'|return ''|" "$R127"; }

# ── controls: real changes that must NOT move the verdict ────────────

# the wording of the age changes: it is for people, and people's words
# are allowed to change
control_1() { sed -i "s|read {_e(_time(w))}|read at {_e(_time(w))}|" "$A127"; }

# a source with NO date renders saying so, which is the honest answer
# and has to stay green
control_2() { python3 - "$AEGIS_ROOT/console/cases/contract-invalid/case.yaml" <<'P'
import sys, pathlib, yaml
p = pathlib.Path(sys.argv[1]); c = yaml.safe_load(p.read_text(encoding="utf-8"))
c.pop("medido_en", None)
p.write_text(yaml.safe_dump(c, sort_keys=False, allow_unicode=True), encoding="utf-8")
P
}
