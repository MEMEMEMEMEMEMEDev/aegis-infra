# title: loss of key material and credentials (P2 audit)
# origin: verify-static.sh (v2) ══ 65
check() {
D65=""
PS65="$(body_of persist_secret "$LIBS/secrets.sh")"
echo "$PS65" | grep -q '\.enc\.tmp' \
    || D65="$D65 persist_secret truncates the .enc BEFORE sops (a failure = the previous ciphertext left at 0 bytes);"
echo "$PS65" | grep -q 'mv .*\.enc\.tmp' \
    || D65="$D65 persist_secret without an atomic mv after the roundtrip;"
GK65="$(body_of gen_or_restore_keypair "$LIBS/secrets.sh")"
echo "$GK65" | grep -q 'ssh-keygen -y' \
    || D65="$D65 a missing .pub ⇒ it would regenerate the WHOLE PAIR (desynchronising the live deploy key);"
CB65="$(body_of ceremony_backup "$LIBS/secrets.sh")"
# W-01/EV-01 (2026-07-21): the ceremony does NOT print the key to the
# pane in interactive mode. tmux pipe-pane, script(1) and agent
# transcripts all record the pane, and [[ -t 1 ]] does not detect that
# class (under tmux stdout IS STILL a TTY). The value goes to tmpfs and
# is read from ANOTHER terminal.
echo "$CB65" | nc | grep -Eq 'cat +"\$file"' \
    && D65="$D65 the ceremony prints the age key to the pane (a cat of the file) — it gets recorded by tmux/script/transcript;"
echo "$CB65" | grep -q '/dev/shm/aegis-resguardo' \
    || D65="$D65 the interactive ceremony does not use the tmpfs path (backup read from another terminal);"
nc "$PHASES/15-third-parties.sh" | grep -q 'x-oauth-scopes' \
    || D65="$D65 the gh token is baked in as a CI credential with no gate on its real scopes;"
grep -q 'ya existe — skip' "$PHASES/30-argocd.sh" \
    && D65="$D65 phase 30 still does skip-if-exists (rotated material goes stale in the cluster);"
nc "$PHASES/30-argocd.sh" | grep -q 'gen_or_restore redis_auth' \
    || D65="$D65 the redis password does not come from the store (a convergent apply would rotate it every run);"
PF65="$(body_of _jenkins_pass_file "$LIBS/jenkins.sh")"
echo "$PF65" | grep -q 'umask 077' \
    || D65="$D65 jenkins' password file is born 644 (a window before the chmod);"
if [[ -n "$D65" ]]; then fail "key material:$D65"
else pass "atomic store, derived .pub (not regenerated), ceremony over tmpfs (does not print to the pane), gated scopes, convergent bootstrap"; fi
}
