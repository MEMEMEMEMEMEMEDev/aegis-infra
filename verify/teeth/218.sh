# teeth for 218 — each red is one of the four ways this was wrong, or a
# neighbour of them. The page is judged by asking the sites.
W218="$AEGIS_ROOT/lib/aegis/window.py"

# ask first, wait afterwards: the edge has not picked it up yet
red_1() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        sleep(interval)
        after = look()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        after = look()''', 1))
P
}

# one look and give up
red_2() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'def effect_of_page(before_codes, look, interval=5, tries=6, sleep=time.sleep):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'def effect_of_page(before_codes, look, interval=5, tries=1, sleep=time.sleep):', 1))
P
}

# a site that stops answering ALTOGETHER stops counting as a change:
# `None` is treated as «nothing to compare» instead of «nobody answered»
red_3() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        changed = {u: (before_codes.get(u), c) for u, c in after.items()
                   if before_codes.get(u) != c}'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        changed = {u: (before_codes.get(u), c) for u, c in after.items()
                   if c is not None and before_codes.get(u) != c}''', 1))
P
}

# an instance with no public site is reported as «the page did nothing»
red_4() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if not before_codes:
        return {"efecto": None, "sitios": 0,'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    if not before_codes:
        return {"efecto": False, "sitios": 0,''', 1))
P
}

# the URLs stop coming from the contracts
red_5() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '                m = re.match(r"^dominio:\\s*(\\S+)", line)'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '                m = re.match(r"^domain:\\s*(\\S+)", line)', 1))
P
}

# the photo stops recording what the sites answered: the page gets
# compared against a world measured AFTER the hook ran
red_6() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    doc["sitios"] = reach(public_urls(root))'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    doc["los_sitios"] = reach(public_urls(root))', 1))
P
}

# ── controls ──
# one more second of margin between looks
control_1() { sed -i 's/def effect_of_page(before_codes, look, interval=5,/def effect_of_page(before_codes, look, interval=6,/' "$W218"; }
# the sentence that travels with «no effect» is prose
control_2() { sed -i 's/still answers exactly what it answered before/still answers precisely what it answered before/' "$W218"; }
# a comment about the round being the wrong instrument is not the instrument
control_3() { printf '\n# note: the round measures the origin; the page lives at the edge.\n' >> "$W218"; }
