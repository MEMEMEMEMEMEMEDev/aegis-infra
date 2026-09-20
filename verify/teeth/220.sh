# teeth for 220 — each red brings back the morning of 2026-09-20: a
# page up, and nothing anywhere saying so.
W220="$AEGIS_ROOT/lib/aegis/window.py"
U220="$AEGIS_ROOT/libexec/aegis-update"
R220="$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml"

# a hook that FAILED to take the page down counts as having taken it
# down: the one case where the page is most certainly still up
red_1() { python3 - "$W220" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            if e.get("kind") != "maintenance" or e.get("rc") != 0:
                continue'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            if e.get("kind") != "maintenance":
                continue''', 1))
P
}

# the journal stops being able to answer at all
red_2() { python3 - "$W220" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            if e.get("hook") == "on":\n                up = True'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '            if e.get("hook") == "arriba":\n                up = True', 1))
P
}

# `status` stops saying it on the one window that matters: the killed
# one, which never wrote a report
red_3() { python3 - "$U220" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        _page_still_up(steps, j, narrate)
        steps.not_evaluable(f"window:{wid}"'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        steps.not_evaluable(f"window:{wid}"''', 1))
P
}

# it is reported as a note instead of a failure: the sites are behind a
# page and the command exits 0
red_4() { python3 - "$U220" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    steps.wrong("window:page-left-up", **{'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    steps.already("window:page-left-up", **{', 1))
P
}

# the metrics stop carrying it: the only way anybody learns is by
# reading a terminal
red_5() { python3 - "$U220" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    emit("aegis_update_page_raised", 1 if (j and j.page_is_up()) else 0, None,'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    emit("aegis_update_page_raised", 0, None,', 1))
P
}

# ── controls ──
# a window that raised the page twice —a rollback does that— and took it
# down each time is not one that left it up
control_1() { python3 - "$W220" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            elif e.get("hook") == "off":\n                up = False'
assert s.count(old) == 1
p.write_text(s.replace(old, '            elif e.get("hook") in ("off", "down"):\n                up = False', 1))
P
}
# the sentence the operator reads changes; what is measured does not
control_2() { sed -i 's/Your public sites may be behind it right now/Your public sites could be behind it at this moment/' "$U220"; }
# a comment naming the series is not the series
control_3() { printf '\n# note: aegis_update_page_raised is what reaches the phone.\n' >> "$W220"; }
