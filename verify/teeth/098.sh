# teeth for check 098 (the console refuses what it cannot attribute)
#
# Every red opens one of the two doors. None of them breaks the console:
# it keeps serving the operator exactly as before, and the only
# difference is who else it serves.

G098="$AEGIS_ROOT/lib/aegis/guard.py"
S098="$AEGIS_ROOT/libexec/aegis-console"

# THE ONE. The Host header stops being checked, and a page whose name
# resolves to 127.0.0.1 reads every hostname, every organization and
# every finding of the round.
red_1() { python3 - "$G098" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    if host.lower() not in allowed_hosts(port):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    if False:', 1))
P
}

# the loopback address is matched as a PREFIX, which reads as generous
# and accepts `127.0.0.1.evil.test`
red_2() { python3 - "$G098" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    if host.lower() not in allowed_hosts(port):'
assert s.count(old) == 1
p.write_text(s.replace(old, '    if not any(host.lower().startswith(n) for n in LOOPBACK_NAMES):', 1))
P
}

# the token stops being compared: any page on the internet can post here
red_3() { python3 - "$G098" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    if not sent or not hmac.compare_digest(str(sent), str(token)):'
assert s.count(old) == 1
p.write_text(s.replace(old, '    if False:', 1))
P
}

# a POST with no Origin is waved through — which is every request that
# did not come from this console's page
red_4() { python3 - "$G098" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if not origin:'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''    if False:''', 1))
P
}

# the rules stay perfect and the server stops asking: the module is
# right, the check that only read the module would stay green, and the
# door is open.
#
# BOTH HANDLERS ASK, so both stop asking: this anchored on a single
# occurrence and went quiet the day `do_POST` was written, which is the
# same way four teeth of check 099 broke. A tooth that cannot be applied
# does not bite and does not say so.
red_5() { python3 - "$S098" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "            why = guard.why_not_read(self.headers, port)"
n = s.count(old)
assert n >= 1, "re-aim this tooth"
p.write_text(s.replace(old, "            why = None"))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the sentence the refusal carries changes: it is for a person reading a
# 403, and no rule is decided by it
control_1() { sed -i 's/a loopback console cannot tell/a console on loopback cannot tell/' "$G098"; }

# a loopback spelling is added to the list: widening the set of names
# that mean THIS machine is not widening who may call
control_2() { python3 - "$G098" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'LOOPBACK_NAMES = ("127.0.0.1", "localhost", "[::1]", "::1")'
assert s.count(old) == 1
p.write_text(s.replace(old, 'LOOPBACK_NAMES = ("127.0.0.1", "localhost", "[::1]", "::1", "127.0.0.1.")', 1).replace("127.0.0.1.\")", "ip6-localhost\")"))
P
}

# a comment recording the attack the Host check exists for
control_3() { printf '\n# note: same-origin policy is not violated by DNS rebinding — the page\n# keeps its own origin. The Host header is the only thing that differs.\n' >> "$G098"; }
