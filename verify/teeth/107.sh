# teeth for check 107 (the error path cannot blow up)
#
# The defect this check prevents: the operator asks for help and
# instead of the reason receives a traceback about the very line that
# was going to give it to them.

# the exact defect `aegis dev seed` had until 2026-08-24
red_1() {
    python3 - "$AEGIS_ROOT/libexec/dev/seed" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
p.write_text(s.replace('morir(f"no existe {CONF}: sin los valores de esta "',
                       'morir(f"no existe {CONF.relative_to(RAIZ)}: sin los valores de esta "'), encoding="utf-8")
PY
}

# and in a raise, which is the other way of leaving through the bad door
red_2() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
i = s.index("\ndef ", s.index("\n"))
s = s[:i] + '\ndef _tooth_107(x, root):\n    raise Error(f"{x.relative_to(root)} is no good")\n' + s[i:]
p.write_text(s, encoding="utf-8")
PY
}

# control: a relative_to OUTSIDE the error path is legitimate (that is
# how the product's paths are shown) and cannot turn it red.
control_1() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
i = s.index("\ndef ", s.index("\n"))
s = s[:i] + '\ndef _tooth_107(x, root):\n    return str(x.relative_to(root))\n' + s[i:]
p.write_text(s, encoding="utf-8")
PY
}
