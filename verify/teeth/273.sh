# teeth of check 273 — tofu never prints a value of the state.
W273="$AEGIS_ROOT/seed/platform/tofu/tofu-apply.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the wrapper as it was: tofu prints whatever it prints
red_1() { _sub "$W273" '    tofu "$@" 2>&1 | _redact
' '    tofu "$@" 2>&1
'; }

# the IDs pass: a random_id's ID is the secret
red_2() { _sub "$W273" '            gsub(/\[id=[^]]*\]/, "[id=(not shown)]")
' ''; }

# the exit code read is the filter's, not tofu's (plan -detailed-exitcode's 2 reads as 0)
red_3() { _sub "$W273" '    RC=${PIPESTATUS[0]}' '    RC=${PIPESTATUS[1]}'; }

# a heredoc's body passes untouched
red_4() { _sub "$W273" '                if ($0 ~ /<<-?EOT[[:space:]]*$/) inheredoc = 1
' ''; }

# output -raw is filtered too: phase 25's capture of the tunnel id breaks
red_5() { _sub "$W273" '"$_SUB" =~ ^(plan|apply|destroy)$' '"$_SUB" =~ ^(plan|apply|destroy|output)$'; }

# ── controls ──
control_1() { _sub "$W273" '# AEGIS_TOFU_SHOW_VALUES=1 — explicit, never a default.' '# AEGIS_TOFU_SHOW_VALUES=1, explicit and never a default.'; }
