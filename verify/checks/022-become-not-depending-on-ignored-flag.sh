# title: become: do NOT depend on the flag ansible ignores (bug 1)
# origin: verify-static.sh (v2) ══ 22
check() {
# Run #6, bug 1: --become-password-file was "verified against the
# source" but become IGNORED it live (sudo prompt timeout) — the
# verified-against-source≠proven class. The only proven path is
# NOPASSWD. The setup must NOT lean on that flag again, nor pass the
# password through argv; it must validate the drop-in with visudo:
BECOME_LIB="$LIBS/common.sh"
BECOME_BAD=""
# the flag IS named in the comment that explains why it is NOT used
# (documenting the debt is legitimate) — real USE is what is looked at,
# not mentions: non-comment lines. Without this the check hunts down
# its own comment (class of checks 15/18b: the textual mention is not
# the use):
nc "$BECOME_LIB" | grep -q 'become-password-file' \
    && BECOME_BAD="$BECOME_BAD --become-password-file reappears in USE (flag ignored live);"
grep -q 'visudo -cf' "$BECOME_LIB" \
    || BECOME_BAD="$BECOME_BAD visudo validation of the NOPASSWD drop-in is missing;"
# the password NEVER goes to sudo's argv (--stdin/-S yes; -p with the
# value no):
grep -qE 'sudo .*-S' "$BECOME_LIB" \
    || BECOME_BAD="$BECOME_BAD the password does not go through sudo's stdin (-S);"
if [[ -n "$BECOME_BAD" ]]; then fail "become_setup:$BECOME_BAD"
else pass "become_setup: proven NOPASSWD path (visudo + -S), without the ignored flag"; fi
}
