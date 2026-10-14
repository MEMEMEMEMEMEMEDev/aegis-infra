# teeth of check 256 — an assignment that reads with grep says why when grep finds nothing.
I256="$AEGIS_ROOT/libexec/aegis-image"
T256="$AEGIS_ROOT/init/phases/25-edge-tofu.sh"
O256="$AEGIS_ROOT/init/phases/85-observability.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# aegis image request as a user ran it on 2026-09-28: the only culprit, and --allow died mute
red_1() { _sub "$I256" "<<< \"\$culprits\" | tr '\\n' ' ' || true)\"" "<<< \"\$culprits\" | tr '\\n' ' ')\""; }

# phase 25: no tunnel_name in main.tf, and the gate that says so never runs
red_2() { _sub "$T256" '"$TUNNEL_ENV/main.tf" || true)"' '"$TUNNEL_ENV/main.tf")"'; }

# the same, on the multi-line one: the check has to follow $( ) to its close
red_3() { _sub "$T256" "| tr -d '\" ' | tr ',' ' ' || true)\"" "| tr -d '\" ' | tr ',' ' ')\""; }

# aegis image gc: a registry with no config in its args, and could_not never speaks
red_4() { _sub "$I256" "| grep -E '\\.ya?ml\$' | head -1 || true)\"" "| grep -E '\\.ya?ml\$' | head -1)\""; }

# ── controls ──
# `|| :` is the same way out as `|| true`
control_1() { _sub "$O256" '| head -1 || true)"' '| head -1 || :)"'; }
# the old line kept as a COMMENT is not code
control_2() { _sub "$I256" '        others="$(grep -vxF' '        # was: others="$(grep -vxF "$dst" <<< "$culprits")"
        others="$(grep -vxF'; }
