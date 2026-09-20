# teeth for 218 — each red brings back the bug of 2026-09-20 or one of
# its neighbours: an answer given before the world could show it.
W218="$AEGIS_ROOT/lib/aegis/window.py"
U218="$AEGIS_ROOT/libexec/aegis-update"

# the bug itself: ask first, wait afterwards
red_1() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        sleep(interval + 5)
        try:
            after = read()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        try:
            after = read()''', 1))
P
}

# it asks once and gives up: one missed probe cycle becomes «the page
# does nothing», which is the answer that stops a window
red_2() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'def effect_of_page(before_doc, read, interval=30, tries=4, sleep=time.sleep):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'def effect_of_page(before_doc, read, interval=30, tries=1, sleep=time.sleep):', 1))
P
}

# it waits, but less than one turn of the probes
red_3() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        sleep(interval + 5)'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '        sleep(1)', 1))
P
}

# the interval stops being derived: the day somebody moves the scrape
# interval, this keeps waiting the old one
red_4() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    m = re.search(r"^\\s*scrape_interval:\\s*(\\d+)\\s*([smh])\\s*$",
                  f.read_text(encoding="utf-8"), re.M)
    if not m:
        return None
    return int(m.group(1)) * {"s": 1, "m": 60, "h": 3600}[m.group(2)]'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    return 30', 1))
P
}

# a round nobody could take becomes «the page did nothing»
red_5() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            return {"efecto": None, "intentos": n,
                    "por_que": f"the round could not be taken again: {e}"}'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            return {"efecto": False, "intentos": n,
                    "por_que": f"the round could not be taken again: {e}"}''', 1))
P
}

# the window guesses the interval in silence
red_6() { python3 - "$W218" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    return fallback, (f"the probes\' interval could not be read from the platform: "'
assert s.count(old) == 1, "re-aim this tooth"
i = s.index(old); j = s.index('out loud rather than made quietly")', i) + len('out loud rather than made quietly")')
p.write_text(s[:i] + '    return fallback, None' + s[j:])
P
}

# ── controls ──
# one more second of margin is still a wait longer than the interval
control_1() { sed -i 's/        sleep(interval + 5)/        sleep(interval + 6)/' "$W218"; }
# the sentence that travels with «no effect» is prose
control_2() { sed -i 's/nothing that was fine had stopped being fine/nothing that used to be fine had stopped being fine/' "$W218"; }
# a comment about the thirty seconds is not the thirty seconds
control_3() { printf '\n# note: the probes run every 30s on this instance; the wait is derived.\n' >> "$W218"; }
