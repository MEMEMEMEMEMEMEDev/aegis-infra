# teeth of check 266 — a command that edits the platform repo first takes in the remote.
W266="$AEGIS_ROOT/lib/aegis/window.py"
I266="$AEGIS_ROOT/libexec/aegis-image"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# update as it was: the refusals look at the clone and never at the remote
red_1() { _sub "$W266" '    if not out:
        try:
            catch_up(root)' '    if False:
        try:
            catch_up(root)'; }

# the catch-up asks the remote-tracking ref without fetching: it answers what the clone already knew
red_2() { _sub "$W266" '    git(root, "fetch", "--quiet")
' ''; }

# image request edits the list on whatever the clone holds
red_3() { _sub "$I266" '        platform_repo_sync
    fi
}' '        :
    fi
}'; }

# ── controls ──
control_1() { _sub "$W266" '"git -C {root} pull --ff-only, and look at what it says"' '"git -C {root} pull --ff-only, and read what it answers"'; }
