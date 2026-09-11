# teeth for check 125 (a case pins a vocabulary the product still speaks)
#
# Each red is the corpus and the contract drifting apart, and none of
# them breaks anything visible: every document stays valid JSON, every
# case still parses, and the screens would render the same until the day
# a real document arrives with the new word.

C125="$AEGIS_ROOT/console/cases"

# THE RENAME. Somebody tidies the fourth outcome's word in the one place
# that defines it. Every case that pinned it is now describing a
# contract that no longer exists.
red_1() { sed -i 's/^NOT_EVALUABLE = "not-evaluable"/NOT_EVALUABLE = "unmeasured"/' \
              "$AEGIS_ROOT/lib/aegis/outcomes.py"; }

# the round stops filing the fourth outcome under its own name: its
# vocabulary shrinks and the corpus keeps pinning the old one
red_2() { sed -i 's/_rec not-evaluated/_rec notice/g' "$AEGIS_ROOT/libexec/aegis-check"; }

# the round's document loses a counter: a key the corpus pinned is
# written by nobody
red_3() { sed -i 's/"failures": failures, "notices": notices, "rc": rc/"rc": rc/' \
              "$AEGIS_ROOT/libexec/aegis-check"; }

# and the other direction: a case pins a word that was never a word.
# This is the corpus drifting on its own — a case hand-edited into a
# vocabulary nobody emits.
red_4() { python3 - "$C125/round-with-findings/case.yaml" <<'P'
import sys, pathlib, yaml
p = pathlib.Path(sys.argv[1]); c = yaml.safe_load(p.read_text(encoding="utf-8"))
c["forma"]["check.json"]["estados"].append("degraded")
p.write_text(yaml.safe_dump(c, sort_keys=False, allow_unicode=True), encoding="utf-8")
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the producers gain a word the corpus has not seen yet: a vocabulary
# that GROWS is not drift, and a case that pins a subset stays true
control_1() { sed -i 's/^WRONG = "wrong"/WRONG = "wrong"\nPARTIAL = "partial"/' \
                  "$AEGIS_ROOT/lib/aegis/outcomes.py"; }

# prose that names the old word right next to the code: the mistake this
# repo made eight times in one day
control_2() { printf '\n# history: the fourth outcome was almost called "unmeasured"; the word\n# that shipped is not-evaluable, and every case pins that one.\n' \
                  >> "$AEGIS_ROOT/lib/aegis/outcomes.py"; }

# one more case pinning the vocabulary that already exists
control_3() { mkdir -p "$C125/probe-125/documents" \
    && printf '{"steps":[{"step":"x","state":"not-evaluable"}],"rc":2}\n' > "$C125/probe-125/documents/edge.json" \
    && printf 'version: 1\ncaso: probe-125\nque: un borde sin zona\nprocedencia: sintetico\npor_que: esta instancia no corre el perfil local\nforma:\n  edge.json:\n    claves: [rc, steps]\n    estados: [not-evaluable]\n' > "$C125/probe-125/case.yaml"; }
