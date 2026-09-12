# teeth for check 129 (the organizations list hides no contract)
#
# Every red is the list becoming tidier than the instance. None of them
# fails: the command exits, the screen looks complete, and an
# organization that is serving traffic is not on it.

O129="$AEGIS_ROOT/lib/aegis/org.py"

# THE SILENT FILTER. «A contract that does not validate is not an
# organization» — and the one whose contract broke yesterday disappears
# from the screen while its pods keep answering.
red_1() { python3 - "$O129" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            steps.append({"step": f"organization:{name}", "state": "wrong",
                          "valid": False, "error": str(e)})
            rc = 1
            continue'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, "            continue", 1))
P
}

# it is listed and NOT marked: shown as one more, which is worse than
# hiding it, because now the screen is confidently wrong
red_2() { sed -i 's/"valid": False, "error": str(e)})/"valid": True})/' "$O129"; }

# the message goes: the screen says something is wrong and not what
red_3() { sed -i 's/"valid": False, "error": str(e)})/"valid": False})/' "$O129"; }

# the rc stops noticing: the document says everything is in order while
# carrying a contract that does not validate
red_4() { python3 - "$O129" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''                          "valid": False, "error": str(e)})
            rc = 1'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''                          "valid": False, "error": str(e)})''', 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the prose of the line changes: the humans' half is allowed to move
control_1() { sed -i 's/  {green}·{off} /  {green}>{off} /' "$O129"; }

# the document gains one more fact per organization: growing is not
# hiding
control_2() { sed -i 's/"cuota": c\["cuota"\],/"cuota": c["cuota"], "servicios_n": len(c.get("servicios") or []),/' "$O129"; }

# prose that names the forbidden shape next to the code that avoids it
control_3() { printf '\n# history: the worst shape of `list` would be a silent filter — a\n# contract that stopped validating vanishing from the screen while its\n# pods keep answering. It is listed, marked, and counted in the rc.\n' >> "$O129"; }
