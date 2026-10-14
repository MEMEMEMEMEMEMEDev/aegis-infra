# teeth of check 289 — a host with no kubectl is declared, never a traceback.
C289="$AEGIS_ROOT/libexec/aegis-capacity"
W289="$AEGIS_ROOT/lib/aegis/window.py"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# capacity as it was until 2026-10-14: the OSError walks out as a traceback
red_1() { _sub "$C289" '    try:
        r = subprocess.run(["kubectl", *args], capture_output=True, text=True)
    except OSError as e:
        raise RuntimeError(f"kubectl is not installed ({e.strerror or e})") from None
' '    r = subprocess.run(["kubectl", *args], capture_output=True, text=True)
'; }

# capacity declares not-evaluable but not WHY: the operator looks for a dead apiserver
red_2() { _sub "$C289" 'raise RuntimeError(f"kubectl is not installed ({e.strerror or e})") from None' 'raise RuntimeError("the cluster did not answer") from None'; }

# the window helper as it was: the metrics producer dies in the middle of its document
red_3() { _sub "$W289" '    try:
        r = subprocess.run(["kubectl", *args], capture_output=True, text=True, timeout=timeout)
    except OSError as e:
        return 127, "", f"kubectl is not installed ({e.strerror or e})"
' '    r = subprocess.run(["kubectl", *args], capture_output=True, text=True, timeout=timeout)
'; }

# ── controls ──
control_1() { _sub "$C289" '# third outcome as an apiserver that does not answer: until' '# third outcome as an apiserver that does not answer; until'; }
control_2() { _sub "$W289" 'reads a non-zero rc as «nobody could ask», and until 2026-10-14 a' 'reads a non-zero rc as «nobody could ask»; until 2026-10-14 a'; }
