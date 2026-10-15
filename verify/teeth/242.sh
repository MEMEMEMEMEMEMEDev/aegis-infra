# teeth of check 242 — the hosts the docs publish are the ones the door accepts.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}

# the README omits Arch although the default door accepts it
red_1() { _sub "$AEGIS_ROOT/README.md" \
    '**Debian 13 o superior** o **Arch Linux (rolling)**, con `sudo`. Arch y los derivados que declaren `ID_LIKE=arch` están soportados.' \
    '**Debian 13 o superior**, con `sudo`.'; }

# two minimums: the English README says 22.04
red_2() { _sub "$AEGIS_ROOT/README.en.md" \
    '**Ubuntu 24.04 or newer**' \
    '**Ubuntu 22.04 or newer**'; }

# the door opens to Debian and no document moves (Debian still «refused»)
red_3() { _sub "$AEGIS_ROOT/lib/host.sh" \
    'AEGIS_HOST_SUPPORTED_DEFAULT="ubuntu debian arch"' 'AEGIS_HOST_SUPPORTED_DEFAULT="ubuntu debian"'; }

# the journey names a floor the door does not have
red_4() { _sub "$AEGIS_ROOT/docs/journeys/your-machine.md" \
    'Ubuntu (24.04 or newer)' \
    'Ubuntu (22.04 or newer)'; }

# the refused list loses a name that IS refused: nobody drives it any more
red_5() { _sub "$AEGIS_ROOT/README.md" \
    'Otras distribuciones (Fedora, Mint, Pop!_OS) se rechazan' \
    'Otras distribuciones (Fedora, Mint, Pop!_OS, Arch) se rechazan'; }

# control: the rest of the row is prose; rewording it changes nothing
control_1() { _sub "$AEGIS_ROOT/README.md" \
    'Otras distribuciones (Fedora, Mint, Pop!_OS) se rechazan antes de tocar nada.' \
    'Otras distribuciones (Fedora, Mint, Pop!_OS) no pasan el preflight.'; }

# control: the resources row moves; the host row does not
control_2() { _sub "$AEGIS_ROOT/README.en.md" \
    '| **Resources** | 4 CPU and 16 GB of RAM is what has been run' \
    '| **Resources** | 4 CPU and 16 GB of RAM is what has been run (measured)'; }
