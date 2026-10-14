# title: a Secret is encrypted before it enters the platform repo, and a cleartext one under an encrypted name is never committed
# origin: new in v3 — 2026-10-13 review (A-3): make_enc_secret moved the plaintext into the checkout and encrypted it in place; a sops that failed in between left a cleartext Secret under a *.enc.yaml name, one `git add -A --no-verify` away from GitHub
check() {
D283=""
[[ -f "$AEGIS_ROOT/verify/checks/283.py" ]] || { fail "check 283 has no sidecar"; return; }
OUT283="$(python3 "$AEGIS_ROOT/verify/checks/283.py" "$AEGIS_ROOT" 2>&1)"
RC283=$?
(( RC283 == 0 )) || { fail "the exercise of check 283 itself failed (rc $RC283): ${OUT283:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE283="${hit#SCOPE: }" ;;
        *)       D283="$D283 $hit;" ;;
    esac
done <<< "$OUT283"
printf '    %s\n' "${SCOPE283:-the scope was not reported}"
if [[ -n "$D283" ]]; then
    fail "a plaintext secret can reach the platform repo, or a cleartext one can be committed:$D283"
else
    pass "secrets are encrypted in tmpfs under the destination's rule and moved in as ciphertext, phase 15 does the same with the tokens, and git_commit_if_changes refuses a staged *.enc.yaml/*.enc.json with no sops metadata (${SCOPE283})"
fi
}
