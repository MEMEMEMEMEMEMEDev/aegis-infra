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

# the wrapper as it was until 2026-09-30: tofu prints whatever it prints
red_1() { _sub "$W273" '    tofu "${_ARGS[@]}" 2>&1 | python3 -u -c "$_REDACT_PY"
' '    tofu "${_ARGS[@]}" 2>&1
'; }

# the IDs pass: a random_id's ID is the secret
red_2() { _sub "$W273" '    s = ident.sub(b"[id=(not shown)]", s)
' ''; }

# the exit code read is the filter's, not tofu's (plan -detailed-exitcode's 2 reads as 0)
red_3() { _sub "$W273" '    RC=${PIPESTATUS[0]}' '    RC=${PIPESTATUS[1]}'; }

# a heredoc's body passes untouched
red_4() { _sub "$W273" '        if re.search(rb"<<-?EOT\s*$", s):
            heredoc = True
' ''; }

# output -raw is filtered too: phase 25's capture of the tunnel id breaks
red_5() { _sub "$W273" '"$_SUB" =~ ^(plan|apply|destroy)$' '"$_SUB" =~ ^(plan|apply|destroy|output)$'; }

# the filter of e196ec5: tofu is not told -no-color, and a real one colours its lines
red_6() { _sub "$W273" '        if [[ $_PLACED -eq 0 && "$_a" == "$_SUB" ]]; then _ARGS+=(-no-color); _PLACED=1; fi
' ''; }

# the same filter, second half: escape codes are not stripped before the line is read
red_7() { _sub "$W273" '    s = ansi.sub(b"", raw)
' '    s = raw
'; }

# -no-color goes at the end: after a positional plan file tofu reads it as a second positional
red_8() { _sub "$W273" '    _ARGS=() ; _PLACED=0' '    _ARGS=() ; _PLACED=1; set -- "$@" -no-color'; }

# the prompt is held until the line ends, which it never does: an apply by hand waits mute
red_9() { _sub "$W273" '    if ansi.sub(b"", pending).rstrip().endswith(b"Enter a value:"):' '    if False:'; }

# ── controls ──
control_1() { _sub "$W273" '# AEGIS_TOFU_SHOW_VALUES=1 — explicit, never a default.' '# AEGIS_TOFU_SHOW_VALUES=1, explicit and never a default.'; }
