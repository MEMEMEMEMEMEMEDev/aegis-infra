# teeth of check 277 — the edge's plaintext state does not outlive a wrapper call.
W277="$AEGIS_ROOT/seed/platform/tofu/tofu-apply.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the wrapper as it was until 2026-10-10: the plaintext stays after the call
red_1() { _sub "$W277" '        shred -u "$PLAIN"
' ''; }

# tofu's .backup (the previous state, in the clear) stays
red_2() { _sub "$W277" '        [[ -f "$PLAIN.backup" ]] && shred -u "$PLAIN.backup"
' ''; }

# the numbered backups `state rm` leaves stay
red_3() { _sub "$W277" "        find \"\$(dirname \"\$PLAIN\")\" -maxdepth 1 -name 'terraform.tfstate.*.backup' -exec shred -u {} +
" ''; }

# shredded without proving the encrypted copy
red_4() { _sub "$W277" '    if [[ -f "$ENCRYPTED" ]] && sops -d --output-type json "$ENCRYPTED" 2>/dev/null \
         | python3 -c '"'"'import json,sys; sys.exit(0 if json.load(sys.stdin) == json.load(open(sys.argv[1])) else 1)'"'"' \
             "$PLAIN" 2>/dev/null; then' '    if [[ -f "$ENCRYPTED" ]]; then'; }

# a plaintext with no encrypted twin is only encrypted when the call changed it
red_5() { _sub "$W277" '      && ( ! -f "$ENCRYPTED" || "$(fingerprint "$PLAIN")" != "$FINGERPRINT_BEFORE" ) ]]; then' '      && "$(fingerprint "$PLAIN")" != "$FINGERPRINT_BEFORE" ]]; then'; }

# aegis destroy asks only for the plaintext
red_6() { _sub "$AEGIS_ROOT/libexec/aegis-destroy" 'if [[ -f "$TUNNEL_ENV/terraform.tfstate.enc.json" || -f "$TUNNEL_ENV/terraform.tfstate" ]]; then' 'if [[ -f "$TUNNEL_ENV/terraform.tfstate" ]]; then'; }

# the state bundle collects only the plaintext
red_7() { _sub "$AEGIS_ROOT/libexec/state/backup" 'collect tfstate       "$TUNNEL_ENV/terraform.tfstate.enc.json" "$TUNNEL_ENV/terraform.tfstate"' 'collect tfstate       "$TUNNEL_ENV/terraform.tfstate"'; }

# restore refuses the edge state just for existing
red_8() { _sub "$AEGIS_ROOT/libexec/state/restore" '    cmp -s "$f" "$TUNNEL_ENV/$(basename "$f")" || clash="$clash $(basename "$f")"' '    clash="$clash $(basename "$f")"'; }

# rotate dates the tunnel token by the plaintext
red_9() { _sub "$AEGIS_ROOT/libexec/aegis-rotate" '        f="$PLATFORM_DIR/tofu/envs/cloudflare-tunnel/terraform.tfstate.enc.json"' '        f="$PLATFORM_DIR/tofu/envs/cloudflare-tunnel/terraform.tfstate"'; }

# ── controls ──
control_1() { _sub "$W277" 'plaintext state shredded — the encrypted copy holds the same state' 'plaintext state shredded; the encrypted copy holds the same state'; }
