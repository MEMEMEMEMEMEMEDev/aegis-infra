# teeth of check 286 — what a backup or a restore stages dies with the call, overwritten.
D286="$AEGIS_ROOT/libexec/aegis-data"
B286="$AEGIS_ROOT/libexec/state/backup"
R286="$AEGIS_ROOT/libexec/state/restore"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# aegis data as it was until 2026-10-14: the dumps staged under /tmp
red_1() { _sub "$D286" '    stage = staging_dir("aegis-resp-")
' '    stage = tempfile.mkdtemp(prefix="aegis-resp-")
'; }

# the dumps removed with rmtree: the blocks keep the plaintext
red_2() { _sub "$D286" '        shred_tree(stage)
' '        shutil.rmtree(stage, ignore_errors=True)
'; }

# shred_tree that unlinks without overwriting
red_3() { _sub "$D286" '                    with open(q, "r+b") as fh:
                        left = n
                        while left > 0:
' '                    if False:
                        left = n
                        while left > 0:
'; }

# main does not arm the signals: a TERM runs no finally
red_4() { _sub "$D286" 'def main():
    arm_signals()
' 'def main():
'; }

# arm_signals that arms nothing
red_5() { _sub "$D286" '    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, _signal_exit)
' '    pass
'; }

# state backup staged under /tmp again
red_6() { _sub "$B286" 'STAGE="$(mktemp -d "$STAGE_ROOT/aegis-state.XXXXXX")"
' 'STAGE="$(mktemp -d)"
'; }

# the cleanup removes without shredding
red_7() { _sub "$B286" '  find "$STAGE" -type f -exec shred -u {} \;
' ''; }

# no INT/TERM trap
red_8() { _sub "$B286" "trap 'stage_cleanup; exit 130' INT TERM
" ''; }

# no EXIT trap: the staging outlives a normal call
red_9() { _sub "$B286" "trap 'stage_cleanup' EXIT
" ''; }

# state restore staged under /tmp again
red_10() { _sub "$R286" 'TMP="$(mktemp -d "$STAGE_ROOT/aegis-state.XXXXXX")"
' 'TMP="$(mktemp -d)"
'; }

# tmpfs whatever the size of the payload: a long-lived instance's dossiers fill it
red_11() { _sub "$B286" '&& (( NEED * 4 < AVAIL )); then' '; then'; }

# the restore unpacks into tmpfs whatever the size of the bundle
red_12() { _sub "$R286" '&& (( NEED * 2 < AVAIL )); then' '; then'; }

# ── controls ──
control_1() { _sub "$D286" '#   · what is staged is overwritten before it is unlinked (one pass: on' '#   · what is staged is overwritten before it is unlinked (a single pass: on'; }
control_2() { _sub "$B286" '# the same cleanup takes both. Check 286.' '# one cleanup takes both. Check 286.'; }
