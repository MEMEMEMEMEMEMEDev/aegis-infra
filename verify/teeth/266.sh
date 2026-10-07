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
            took = catch_up(root)' '    if False:
        try:
            took = catch_up(root)'; }

# the catch-up asks the remote-tracking ref without fetching: it answers what the clone already knew
red_2() { _sub "$W266" '    git(root, "fetch", "--quiet")
' ''; }

# image request edits the list on whatever the clone holds
red_3() { _sub "$I266" 'do_request() {
    need_list
    sync_before_writing
' 'do_request() {
    need_list
'; }

# image gc decides its prune on pins that moved
red_4() { _sub "$I266" '    sync_before_writing
    secrets_workdir
    reg_ready
    gc_registry_target' '    secrets_workdir
    reg_ready
    gc_registry_target'; }

# the sync is back in the list loader: `image list` and `image check` fetch, merge and die offline
red_5() { _sub "$I266" '    IMAGES="$LIST_ROOT/$IMAGES_REL"
    IGNORE="$LIST_ROOT/$IGNORE_REL"
}' '    IMAGES="$LIST_ROOT/$IMAGES_REL"
    IGNORE="$LIST_ROOT/$IGNORE_REL"
    dry || platform_repo_sync
}'; }

# a dry run takes in the remote too
red_6() { _sub "$I266" '    dry && return 0
' ''; }

# the clone is fast-forwarded and nobody is told
red_7() { _sub "$W266" '            if took and notes is not None:' '            if False:'; }

# a git that does not answer ends in a traceback (TimeoutExpired), not a refusal
red_8() { _sub "$W266" '    except subprocess.TimeoutExpired:
        raise GitTrouble(' '    except ZeroDivisionError:
        raise GitTrouble('; }

# a remote that asks for credentials waits on a prompt nobody sees
red_9() { _sub "$W266" 'env={**os.environ, "GIT_TERMINAL_PROMPT": "0"}' 'env=dict(os.environ)'; }

# ── controls ──
control_1() { _sub "$W266" '"git -C {root} pull --ff-only, and look at what it says"' '"git -C {root} pull --ff-only, and read what it answers"'; }
