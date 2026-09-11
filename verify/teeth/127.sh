# teeth for check 127 (no reading is drawn without its age)
#
# Both reds are a tidy-up. Neither breaks a page, neither changes a
# state, and both turn a console that measured once into one that looks
# like it is measuring continuously.

R127="$AEGIS_ROOT/lib/aegis/console.py"

# «the timestamp is clutter» — and every number on the page starts
# looking like it was taken just now
red_1() { python3 - "$R127" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace("f'{_age(reading)}{\"\".join(body)}</section>'", "f'{\"\".join(body)}</section>'")
s = s.replace("f'{_age(reading)}</section>')", "f'</section>')")
p.write_text(s)
P
}

# the attribute goes, the visible line stays: a machine reading this
# page can no longer tell fresh from stale
red_2() { sed -i "s|return f' data-measured-at=\"{_e(w)}\"' if w else ' data-measured-at=\"unknown\"'|return ''|" "$R127"; }

# ── controls: real changes that must NOT move the verdict ────────────

# the wording of the age changes: it is for people, and people's words
# are allowed to change
control_1() { sed -i "s|measured {_e(w)}|read at {_e(w)}|" "$R127"; }

# a source with NO date renders saying so, which is the honest answer
# and has to stay green
control_2() { python3 - "$AEGIS_ROOT/console/cases/contract-invalid/case.yaml" <<'P'
import sys, pathlib, yaml
p = pathlib.Path(sys.argv[1]); c = yaml.safe_load(p.read_text(encoding="utf-8"))
c.pop("medido_en", None)
p.write_text(yaml.safe_dump(c, sort_keys=False, allow_unicode=True), encoding="utf-8")
P
}
