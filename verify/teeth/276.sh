# teeth of check 276 — the round reads each job inside its own block.
C276="$AEGIS_ROOT/libexec/aegis-check"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the round as it was: one regex from the job's name to the next non-empty repo
red_1() { _sub "$C276" '    block = text[pos:starts[i + 1][0] if i + 1 < len(starts) else len(text)]
    m = re.search(r"repoOwner\('"'"'([^'"'"']*)'"'"'\)\s*\n\s*repository\('"'"'([^'"'"']*)'"'"'\)", block)' '    block = text[pos:]
    m = re.search(r"repoOwner\('"'"'([^'"'"']+)'"'"'\)\s*\n\s*repository\('"'"'([^'"'"']+)'"'"'\)", block)'; }

# a job with no repo is kept and judged against nothing
red_2() { _sub "$C276" '    if not m or not m.group(1) or not m.group(2):' '    if not m:'; }

# a switched-off lane disappears without a word
red_3() { _sub "$C276" '    print(f"NOTE: {job} names no repository (a lane this instance has switched off): no push to build")' '    pass'; }

# ── controls ──
control_1() { _sub "$C276" "(a lane this instance has switched off)" "(a lane switched off on this instance)"; }
