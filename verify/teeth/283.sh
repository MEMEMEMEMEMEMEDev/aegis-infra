# teeth of check 283 — a Secret is encrypted before it enters the platform repo.
S283="$AEGIS_ROOT/lib/secrets.sh"
C283="$AEGIS_ROOT/lib/common.sh"
P283="$AEGIS_ROOT/init/phases/15-third-parties.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the regression itself (the helper as it was until 2026-10-14): the
# plaintext is moved into the checkout first and encrypted in place
red_1() { _sub "$S283" '    sops_encrypt_repo "$tmp_yaml" "$dest"
    mv "$tmp_yaml" "$dest"
' '    mv "$tmp_yaml" "$dest"
    sops_encrypt_repo "$dest"
'; }

# the helper forgets the destination's rule: a file in tmpfs cannot be
# encrypted at all («no matching creation rules»)
red_2() { _sub "$S283" '--filename-override "${2:-$1}" -e --in-place "$1"' '-e --in-place "$1"'; }

# phase 15 moves the tokens in before encrypting them
red_3() { _sub "$P283" '    sops_encrypt_repo "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"
    mv "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"
' '    mv "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"
    sops_encrypt_repo "$TOKENS_DIR/tokens.enc.yaml"
'; }

# the commit helper takes whatever is staged (as it was until 2026-10-14)
red_4() { python3 - "$C283" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
m = re.search(r'    local staged\n.*?    done < <\(git -C "\$dir" diff --cached --name-only --diff-filter=AM\)\n', s, re.S)
assert m, "re-aim this tooth: the fence is not where it was"
p.write_text(s[:m.start()] + s[m.end():])
PY
}

# the fence only knows YAML: a tofu state in the clear under .enc.json walks through
red_5() { _sub "$C283" '[[ "$staged" == *.enc.yaml || "$staged" == *.enc.json ]] || continue' '[[ "$staged" == *.enc.yaml ]] || continue'; }

# ── controls ──
control_1() { _sub "$S283" 'only the ciphertext is moved into the repo. Until then the' 'only the ciphertext is moved into the repo; until then the'; }
control_2() { _sub "$C283" 'a CLEARTEXT secret was about to be committed. Encrypt it' 'a CLEARTEXT secret was about to be committed — encrypt it'; }
