# teeth of check 243 — the running kernel keeps its modules after the upgrade the product runs.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}

# phase 05 as it was on 2026-09-24: the upgrade runs and nobody looks
red_1() { _sub "$AEGIS_ROOT/init/phases/05-host.sh" \
    'gate "modulos-del-kernel-en-marcha" host_running_kernel_has_modules
' ''; }

# the gate asked BEFORE the upgrade that removes the tree: always green
red_2() { _sub "$AEGIS_ROOT/init/phases/05-host.sh" \
    'gate "modulos-del-kernel-en-marcha" host_running_kernel_has_modules
' '' && _sub "$AEGIS_ROOT/init/phases/05-host.sh" \
    'run_cmd retry_net 3 pkg_update
' 'gate "modulos-del-kernel-en-marcha" host_running_kernel_has_modules
run_cmd retry_net 3 pkg_update
'; }

# the preflight lets it through as a warning: the summary says «Machine ready»
red_3() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    '|| bad "the running kernel $(host_kernel_release) has no modules on disk' \
    '|| warn "the running kernel $(host_kernel_release) has no modules on disk'; }

# the measure that measures nothing
red_4() { _sub "$AEGIS_ROOT/lib/host.sh" \
    '    [[ -d "$dir" ]] && return 0' \
    '    return 0'; }

# the preflight no longer asks
red_5() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    'host_running_kernel_has_modules 2>/dev/null && ok "the running kernel' \
    'true && ok "the running kernel'; }

# control: a comment that names the gate is prose, not the gate
control_1() { _sub "$AEGIS_ROOT/init/phases/05-host.sh" \
    '# find no vxlan. Asked here, right after the action, so the init stops' \
    '# (it used to be: nothing — no gate "x" host_running_kernel_has_modules)
# find no vxlan. Asked here, right after the action, so the init stops'; }

# control: the gate under another name is the same gate
control_2() { _sub "$AEGIS_ROOT/init/phases/05-host.sh" \
    'gate "modulos-del-kernel-en-marcha" host_running_kernel_has_modules' \
    'gate "kernel-modules-present" host_running_kernel_has_modules'; }
