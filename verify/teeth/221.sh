# teeth for 221 — each red brings back one of the three ways a window
# blamed itself for a world it had not made.
U221="$AEGIS_ROOT/libexec/aegis-update"
W221="$AEGIS_ROOT/lib/aegis/window.py"

# the acceptance goes back to comparing against the PHOTO: with the
# page up, the page doing its job reads as damage
red_1() { python3 - "$U221" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        cmp_ = win.compare(baseline, after_doc)'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '        cmp_ = win.compare(before["round"]["doc"], after_doc)', 1))
P
}

# the layers are judged against the photo too
red_2() { python3 - "$U221" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        last_doc = baseline'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '        last_doc = before["round"]["doc"]', 1))
P
}

# the layer that syncs stops waiting: it judges a cluster still rolling
red_3() { python3 - "$U221" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    settled = win.argo_all_settled(narrate=ctx.narrate)'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    settled = {"asentado": True, "apps": 0}', 1))
P
}

# the global acceptance goes back to naming a rollback it never did
red_4() { python3 - "$U221" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            outcome = _undo(ctx, steps, j, detail, narrate, "the global acceptance")'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '            outcome = "rolled-back"', 1))
P
}

# the way back stops waiting for the cluster: it reports the tree came
# back while ArgoCD is still rolling
red_5() { python3 - "$U221" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        settled = win.argo_all_settled(narrate=narrate)
        j.note("rollback-settled", **settled)'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '        j.note("rollback-settled", asentado=True)', 1))
P
}

# a wait that ran out is reported as settled
red_6() { python3 - "$W221" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    return {"asentado": False, "apps": len(last), "segundos": round(time.time() - t0),'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    return {"asentado": True, "apps": len(last), "segundos": round(time.time() - t0),''', 1))
P
}

# a kubectl that cannot answer is read as «not ready» instead of
# «nobody could look»
red_7() { python3 - "$W221" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            return {"asentado": None, "por_que": "the Applications could not be read: "'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            return {"asentado": False, "por_que": "the Applications could not be read: "''', 1))
P
}

# ── controls ──
# the sentence the baseline is noted with is prose
control_1() { sed -i 's/taken with the page up and nothing else changed yet/taken while the page was up, before any layer/' "$U221"; }
# one more second between polls is still a wait
control_2() { sed -i 's/def argo_all_settled(timeout=900, poll=15,/def argo_all_settled(timeout=900, poll=16,/' "$W221"; }
# a comment naming the three mistakes is not the three mistakes
control_3() { printf '\n# note: the page lives at the edge, and a sync is a request.\n' >> "$W221"; }
