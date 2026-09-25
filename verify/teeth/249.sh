# teeth of check 249 — a service's own secrets, and put.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
SEC249="$AEGIS_ROOT/libexec/aegis-secret"
ORG249="$AEGIS_ROOT/lib/aegis/org.py"

# the value through stringData, as create does for invented material
red_1() { _sub "$SEC249" '        "data": {k: base64.b64encode(v).decode("ascii") for k, v in keys.items()},' '        "stringData": {k: v.decode() for k, v in keys.items()},'; }

# any file under an organization is accepted
red_2() { _sub "$SEC249" '    if os.path.abspath(path) not in declared:' '    if False:'; }

# the generator forgets the service's secrets
red_3() { _sub "$ORG249" '            s.append(f"secret-{x['"'"'nombre'"'"']}-{nm}.enc.yaml")' '            pass'; }

# an empty file is a credential
red_4() { _sub "$SEC249" '        if not raw:' '        if raw is None:'; }

# the idempotence lost: every put re-encrypts over the existing one
red_5() { _sub "$SEC249" '    if os.path.exists(path) and not replace:' '    if False:'; }

# `credenciales` allowed as a name: two secrets fight over one file
red_6() { _sub "$ORG249" '            if nm == "credenciales":' '            if nm == "never":'; }

# the shape line prints the value instead of its length
red_7() { _sub "$SEC249" '    shape = ", ".join(f"{k} ({len(v)} bytes)" for k, v in keys.items())' '    shape = ", ".join(f"{k} ({v.decode()})" for k, v in keys.items())'; }

# control: the help text reworded
control_1() { _sub "$SEC249" 'help="change the material of a file that already exists")' 'help="replace the material of a file that already exists")'; }
