# teeth of check 231 — Access being off, found in time.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
PH231="$AEGIS_ROOT/init/phases/25-edge-tofu.sh"
J231="$AEGIS_ROOT/docs/journeys/your-machine.md"

# the phase as it was on 2026-09-22: nobody asks, tofu finds out
red_1() { _sub "$PH231" '    gate "access-habilitado" _access_enabled' '    :'; }

# «not_enabled» read and let through
red_2() { _sub "$PH231" "        if grep -q 'not_enabled' <<< \"\$out\"; then" "        if grep -q 'not_enabled_never' <<< \"\$out\"; then"; }

# the refusal without the page that fixes it
red_3() { _sub "$PH231" 'log_error "  Enable it once, it is free: https://one.dash.cloudflare.com/ -> choose a team domain -> Zero Trust Free"' 'log_error "  Enable Zero Trust in the dashboard"'; }

# the journey stops telling the operator to switch Zero Trust on
red_4() { python3 - "$J231" <<'PYT'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
out = re.sub(r"(?i)zero trust", "that product", s)
assert out != s, "the journey never said it"
p.write_text(out)
PYT
}

# the auth error read as «Access is off»: a run blocked by a token's
# permissions, not by the account (measured 2026-09-22)
red_5() { python3 - "$PH231" <<'PYT'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index("        if grep -qE 'Authentication error")
j = s.index("        fi\n", i) + len("        fi\n")
p.write_text(s[:i] + s[j:])
PYT
}

# control: the same probe, with the shapes checked in the other order
control_1() { _sub "$PH231" '        if [[ -z "$out" ]]; then
            log_warn "Cloudflare did not answer about Access: NOT measured"
            return 0
        fi' '        if [[ "${out:-}" = "" ]]; then
            log_warn "Cloudflare did not answer about Access at all: NOT measured"
            return 0
        fi'; }
