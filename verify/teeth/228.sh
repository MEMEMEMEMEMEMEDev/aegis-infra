# teeth of check 228 — a server image is not a desktop.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}

# the rule as it was on 2026-09-22: graphical.target alone means shared
red_1() { _sub "$AEGIS_ROOT/libexec/aegis-host" "            if verdict:
                dm = subprocess.run(" "            if False:
                dm = subprocess.run("; }

# the display manager asked, and a missing one IGNORED
red_2() { _sub "$AEGIS_ROOT/libexec/aegis-host" '                if load == "not-found":' '                if load == "never":'; }

# not being able to ask read as «nobody there»: the timid default lost
red_3() { _sub "$AEGIS_ROOT/libexec/aegis-host" '                    evidence.append("and whether a display manager is installed "
                                    "could not be read: counted as shared")' '                    evidence.append("display manager unreadable")
                    verdict = False'; }

# control: the evidence is worded differently; the verdicts do not move
control_1() { _sub "$AEGIS_ROOT/libexec/aegis-host" '"and a display manager is installed"' '"and a display manager (gdm, sddm, lightdm…) is installed"'; }
