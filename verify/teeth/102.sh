# teeth for check 102 (every bash command resolves alike)
#
# Phase 05 installs /usr/local/bin/aegis as a SYMLINK to the product.
# Without readlink -f, AEGIS_ROOT would be /usr/local and the command
# would find neither its phases nor its libs — and the error would talk
# about a missing file, not about the resolution.
red_1() {
    grep -v 'readlink -f' "$AEGIS_ROOT/libexec/state/backup" > "$AEGIS_ROOT/libexec/state/backup.d" \
        && mv "$AEGIS_ROOT/libexec/state/backup.d" "$AEGIS_ROOT/libexec/state/backup"
}
# the instance is not invented: that belongs to lib/paths.sh
red_2() { printf '\nAEGIS_HOME="$HOME/aegis"\n' >> "$AEGIS_ROOT/libexec/aegis-destroy"; }
# and the resolver has to be ONE
red_3() { printf '\naegis_home() { echo /somewhere/else; }\n' >> "$AEGIS_ROOT/lib/common.sh"; }
# a second root, the v2 fossil: the round's contracts hung off the product again
red_4() { python3 - "$AEGIS_ROOT/libexec/aegis-check" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('mapfile -t ORGS < <(python3 - "$PLATFORM_DIR/orgs"',
              'ROOT_P="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n    mapfile -t ORGS < <(python3 - "$ROOT_P/orgs"', 1)
p.write_text(s)
P
}
control_1() { printf '\n# legitimate comment\n' >> "$AEGIS_ROOT/lib/access.sh"; }
# prose that names the fossil next to the fix must not bite
control_2() { printf '\n# history: ROOT_P="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" was the v2 shape\n' >> "$AEGIS_ROOT/libexec/aegis-check"; }
