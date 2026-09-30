# teeth of check 258 — an exception is scoped to what the scan named; an accepted risk says it was not measured.
I258="$AEGIS_ROOT/libexec/aegis-image"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the scope as Rob met it on 2026-09-28: the table's header, «Node.js (node-pkg)»
red_1() { _sub "$I258" '    if len(f) == 9 and f[0] == cve:
        hits.append(f[6] if f[6] else re.sub(r"^\S+\.tar ", "*.tar ", f[8]))' '    pass'; }

# an accepted risk is written in the words of a measurement
red_2() { _sub "$I258" '    statement = f"Risk accepted, not measured: {reason.rstrip(chr(46))}. Accepted {today}."' '    statement = f"{reason.rstrip(chr(46))}. Measured {today}."'; }

# the policy's ceiling on an unmeasured acceptance is not read
red_3() { _sub "$I258" '    if (end - today).days > most:' '    if False:'; }

# a CVE exploited in the wild is accepted like any other
red_4() { _sub "$I258" '    if cve in kev:' '    if False:'; }

# --accept silently replaces an --allow given before it
red_5() { _sub "$I258" '            --accept)  [[ $# -ge 2 ]] || bad_usage "--accept needs a CVE identifier"
                       [[ -z "$ALLOW" ]] || bad_usage "--allow and --accept are two kinds of exception: one CVE is either measured or accepted"' '            --accept)  [[ $# -ge 2 ]] || bad_usage "--accept needs a CVE identifier"'; }

# the report as it was on 2026-09-30: the table, «3 blocking findings» and «Node.js (node-pkg)»
red_6() { _sub "$I258" 'if verdicts:
    block = [f for f in verdicts if f[0] == "block"]' 'if False:
    block = [f for f in verdicts if f[0] == "block"]'; }

# a list is let through without checking each member
red_7() { _sub "$I258" '^CVE-[0-9]{4}-[0-9]{4,}(,CVE-[0-9]{4}-[0-9]{4,})*$' '^CVE-[0-9]{4}-[0-9]{4,}(,.*)*$'; }

# ── controls ──
control_1() { _sub "$I258" '    head = [f"  # {cve} — RISK ACCEPTED by the operator on {today} while asking for",' '    head = [f"  # {cve} — risk ACCEPTED by the operator on {today} while asking for",'; }
