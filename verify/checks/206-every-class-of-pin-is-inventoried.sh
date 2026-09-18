# title: every class of pin is inventoried, derived from the tree and never listed
# origin: new in v3 — 2026-09-18, `aegis update` is the instrument that says what is behind (plan/17)
check() {
# THE FAILURE THIS FORBIDS IS A NUMBER THAT LOOKS RIGHT.
#
# aegis pins fifty-odd versions across six places, and the doctrine
# forbids a summary of them: every pin lives only where it is consumed.
# So `aegis update inventory` DERIVES them, every time, and a reader
# that silently stops matching —a regex that no longer fits a file, a
# directory that moved— does not fail: it returns fewer pins, and the
# command answers «nothing to update» about thirteen charts nobody
# looked at. That is the same disease as a green that means «I could
# not look», one level up.
#
# So the check reads the tree with its OWN greps, sharing no code with
# the command, and demands the command name every pin it finds, with
# the file and the line. Two independent readings of one artifact.
D206=""
[[ -f "$LIBEXEC/aegis-update" ]] || { skip "there is no aegis update: nothing inventories the pins"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/206.py" ]] || { fail "check 206 has no sidecar: the two readings were never compared"; return; }

OUT206="$(python3 "$AEGIS_ROOT/verify/checks/206.py" "$AEGIS_ROOT" 2>&1)"
RC206=$?
if (( RC206 != 0 )); then
    fail "the exercise of check 206 itself failed (rc $RC206) and no pin was compared: $OUT206"
    return
fi
SCOPE206=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE206="${hit#SCOPE: }" ;;
        *)       D206="$D206 $hit;" ;;
    esac
done <<< "$OUT206"

printf '    %s\n' "${SCOPE206:-the scope was not reported}"
if [[ -n "$D206" ]]; then
    fail "the inventory does not see everything this tree pins:$D206"
else
    pass "every class of pin is derived from the tree, and every pin says where its version is written ($SCOPE206)"
fi
}
