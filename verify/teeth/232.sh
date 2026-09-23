# teeth of check 232 — the encrypted state, cleaned with the cloud.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
PH232="$AEGIS_ROOT/init/phases/25-edge-tofu.sh"
GI232="$AEGIS_ROOT/seed/platform/.gitignore"

# the phase as it was on 2026-09-23: only the plaintext purged
red_1() { python3 - "$PH232" <<'PYT'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index('        if [[ -f "$TUNNEL_ENV/terraform.tfstate.enc.json" ]]; then')
j = s.index("        fi\n", i) + len("        fi\n")
p.write_text(s[:i] + s[j:])
PYT
}

# the whole state dropped, Access included: the apply would then try to
# recreate applications that exist and 409
red_2() { _sub "$PH232" "state list 2>/dev/null | awk '/^module\\.tunnel\\./'" "state list 2>/dev/null | awk '/^module\\./'"; }

# the plaintext copies left on disk
red_3() { _sub "$PH232" "            find \"\$TUNNEL_ENV\" -maxdepth 1 -name 'terraform.tfstate.*.backup' -exec shred -u {} +" "            :"; }

# git no longer ignores the copies `state rm` leaves behind
red_4() { _sub "$GI232" "*.tfstate.*.backup
" ""; }

# the encrypted state ignored too: nothing would ever be versioned
red_5() { _sub "$GI232" "*.tfstate.*.backup
" "*.tfstate.*.backup
*.tfstate.enc.json
"; }

# control: the same pattern, explained on its own comment line
control_1() { _sub "$GI232" "# the plaintext copies \`tofu state rm\` leaves behind (2026-09-23)" "# plaintext copies that \`tofu state rm\` writes beside the state; they carry the tunnel secret"; }
