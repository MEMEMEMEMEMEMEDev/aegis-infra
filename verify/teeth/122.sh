# teeth for check 122 (the console does not flatten)
#
# Every red is the flattening, in one of the shapes it actually takes in
# a real interface. None of them throws, none breaks a page: the HTML
# stays valid, the screen looks calmer, and a state the CLI measured
# stops existing.

R122="$AEGIS_ROOT/lib/aegis/console.py"

# THE ONE. «Not evaluated is basically fine» — the single line that
# turns four outcomes into two colours, and the reason the product
# exists at all.
red_1() { sed -i 's/^LOOKED_AT = {FINE: True, WRONG: True, ATTENTION: True, BUSY: True, UNSEEN: False}/LOOKED_AT = {FINE: True, WRONG: True, ATTENTION: True, BUSY: True, UNSEEN: True}/' "$R122"; }

# the same, one layer down: the translation itself sends «could not
# look» to «fine», so it never even reaches the screen as its own thing
red_2() { sed -i 's/"not-evaluable": UNSEEN/"not-evaluable": FINE/' "$R122"; }

# the round's word for the same thing, which is the one the daily round
# actually emits
red_3() { sed -i 's/"not-evaluated": UNSEEN/"not-evaluated": FINE/' "$R122"; }

# a producer word loses its translation: the state is not flattened,
# it is simply not shown
red_4() { sed -i '/"notice": ATTENTION,/d' "$R122"; }

# the verdict stops outranking its readings: a page where something
# could not be looked at ends up saying everything is in order
red_5() { sed -i 's/^SEVERITY = \[UNSEEN, WRONG, ATTENTION, BUSY, FINE\]/SEVERITY = [FINE, UNSEEN, WRONG, ATTENTION, BUSY]/' "$R122"; }

# the case zero stops being a state: a command with no document draws
# nothing at all, which on a screen is indistinguishable from silence
red_6() { python3 - "$R122" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('return _blind(reading), {UNSEEN}', 'return "", set()')
p.write_text(s)
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the words on the screen are for people: rewording every one of them
# must change nothing, because the contract is the attribute
control_1() { python3 - "$R122" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('"Everything is in order."', '"All good here."')
s = s.replace('"Something could not be looked at."', '"Some of this could not be measured."')
s = s.replace('"could not look"', '"not measured"')
p.write_text(s)
P
}

# a producer learns a NEW word and the console translates it: the map
# grows and stays total
control_2() { python3 - "$R122" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
p.write_text(s.replace('    "good": FINE,', '    "partial": ATTENTION,\n    "good": FINE,'))
P
}

# one more case in the corpus: the check measures a shape, not a count
control_3() { mkdir -p "$AEGIS_ROOT/console/cases/probe-122/documents" \
    && printf '{"steps":[{"step":"x","state":"not-evaluable"}],"rc":2}\n' > "$AEGIS_ROOT/console/cases/probe-122/documents/edge.json" \
    && printf 'version: 1\ncaso: probe-122\nque: un borde que no se pudo mirar\nprocedencia: sintetico\npor_que: esta instancia no corre el perfil local\nproducido_por:\n- comando: edge check\n  documento: edge.json\n  rc: 2\nforma:\n  edge.json:\n    claves: [rc, steps]\n    estados: [not-evaluable]\n' > "$AEGIS_ROOT/console/cases/probe-122/case.yaml"; }
