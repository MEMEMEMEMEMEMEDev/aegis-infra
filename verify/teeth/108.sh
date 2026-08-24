# teeth for check 108 (the python package LOADS, it does not just parse)
#
# The real regression, with a date: on 2026-08-24, renaming to English,
# `rutas.py` became `paths.py` and `cli.py` was left asking for the old
# name. The file parsed, check 001 gave it a clean bill, `aegis verify`
# came out ALL PASS, and `aegis org apply` died on the import.
# red_1 IS that regression, not one like it.
red_1() {
    sed -i 's/^from \. import paths$/from . import rutas/' "$AEGIS_ROOT/lib/aegis/cli.py"
}

# The other half, and it fails differently: here it is not the importer
# that breaks, it is the imported that moves away. The static pass has
# to see it without executing anything — a module that is not there
# cannot fail «while loading».
red_2() {
    mv "$AEGIS_ROOT/lib/aegis/markers.py" "$AEGIS_ROOT/lib/aegis/centinelas.py"
}

# And the case only the REAL load can see: impeccable syntax, dead
# internal import. `ast.parse` says yes; the interpreter says no.
red_3() {
    printf '\nimport aegis.this_module_does_not_exist\n' >> "$AEGIS_ROOT/lib/aegis/outcomes.py"
}

# control: adding a new module to the package and using it is exactly
# what people are expected to do. It cannot turn red.
control_1() {
    cat > "$AEGIS_ROOT/lib/aegis/legitimate.py" <<'PY'
"""A new, well-formed module, like the one anybody would add."""
VALUE = 1
PY
    printf '\nfrom aegis import legitimate  # noqa: E402,F401\n' \
        >> "$AEGIS_ROOT/libexec/aegis-org"
}
