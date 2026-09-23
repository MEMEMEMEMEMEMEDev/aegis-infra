# teeth of check 240 — every package goes through lib/pkg.sh.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}

# the preflight as it was: apt-get by name, Ubuntu's names
red_1() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    'pkg_install tmux python3-yaml jq >/dev/null 2>&1' \
    'sudo apt-get install -y -qq tmux python3-yaml jq >/dev/null 2>&1'; }

# Ubuntu's name written for Arch: «target not found» on the first Arch run
red_2() { _sub "$AEGIS_ROOT/lib/pkg.sh" \
    'python3-yaml)     deb=python3-yaml  arch=python-yaml ;;' \
    'python3-yaml)     deb=python3-yaml  arch=python3-yaml ;;'; }

# an unknown name skipped instead of stopping: a half-installed host
red_3() { _sub "$AEGIS_ROOT/lib/pkg.sh" \
    '        n="$(pkg_name "$c")" || return 1
        [[ -n "$n" ]] && names+=("$n")' \
    '        n="$(pkg_name "$c")" || continue
        [[ -n "$n" ]] && names+=("$n")'; }

# apt that no longer waits for the dpkg lock (bug run #10)
red_4() { _sub "$AEGIS_ROOT/lib/pkg.sh" \
    'apt-get -o DPkg::Lock::Timeout=600 install -y -qq "${names[@]}"' \
    'apt-get install -y -qq "${names[@]}"'; }

# a new package installed with no row: nobody measured its name
red_5() { _sub "$AEGIS_ROOT/init/phases/05-host.sh" \
    'run_cmd retry_net 3 pkg_install htpasswd python3-yaml python3-venv rsync' \
    'run_cmd retry_net 3 pkg_install htpasswd python3-yaml python3-venv rsync conntrack'; }

# control: a comment that names apt-get is prose
control_1() { _sub "$AEGIS_ROOT/init/phases/05-host.sh" \
    'run_cmd retry_net 3 pkg_update' \
    '# (was: sudo apt-get update -qq)
run_cmd retry_net 3 pkg_update'; }

# control: a message that names the manager does not call it
control_2() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    'pkg_install tmux python3-yaml jq >/dev/null 2>&1' \
    'pkg_install tmux python3-yaml jq >/dev/null 2>&1
info "on debian this is apt-get; on arch, pacman"'; }
