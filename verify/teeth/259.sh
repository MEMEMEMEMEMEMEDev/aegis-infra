# teeth of check 259 — aegis app new finds the templates wherever the product is installed.
A259="$AEGIS_ROOT/libexec/aegis-app"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the lookup as a user and the Arch lab VM met it: only beside the instance
red_1() { _sub "$A259" '    for d in (os.path.join(str(paths.aegis_root()), "seed", "templates"),
              os.path.join(os.path.dirname(PLATFORM_DIR), "seed", "templates")):' '    for d in (os.path.join(os.path.dirname(PLATFORM_DIR), "seed", "templates"),):'; }

# the house layout forgotten: only the product root
red_2() { _sub "$A259" '    for d in (os.path.join(str(paths.aegis_root()), "seed", "templates"),
              os.path.join(os.path.dirname(PLATFORM_DIR), "seed", "templates")):' '    for d in (os.path.join(str(paths.aegis_root()), "seed", "templates"),):'; }

# ── controls ──
control_1() { _sub "$A259" '        f"  They ship with the PRODUCT (its seed/templates/), and this command\n"' '        f"  They ship with the PRODUCT (in seed/templates/), and this command\n"'; }
