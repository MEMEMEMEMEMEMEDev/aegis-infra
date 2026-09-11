# title: the skin dresses every state of the screen, and the fourth one is not told by colour alone
# origin: new in v3 — 2026-09-11, SERENO (plan/15 §C4): the last step where a measurement can be lost
check() {
# THE LAST PLACE A STATE CAN DISAPPEAR.
#
# The CLI keeps four outcomes apart with 190-odd checks. The renderer
# keeps them apart and check 122 holds it to that. And then the skin
# paints them, and a missing rule or a badly chosen colour undoes all of
# it in the one layer nobody reviews — because a stylesheet looks like
# taste.
#
# Two things are asked, and both are guarantees rather than taste:
#
#   1. every state the screen can show has a rule. One without a rule
#      renders unstyled, and on a page of coloured surfaces that reads
#      as nothing being there.
#
#   2. «could not look» is not told by colour alone. It carries a
#      hatch, a shape or an edge — something that survives a grayscale
#      print, a bad screen and an eye that does not see red. Every
#      other state may be a colour and nothing else; this one may not,
#      because confusing it with «it is fine» is the exact failure the
#      product was built to eliminate.
#
# WHICH states exist, and WHICH one means «could not look», are read
# from lib/aegis/console.py — from the vocabulary and from its LOOKED_AT
# table. A check carrying its own copy of either would be one more place
# for the contract to drift.
D124=""
[[ -f "$AEGIS_ROOT/share/console/sereno.css" ]] || { skip "there is no skin yet (share/console/sereno.css): nothing paints the states"; return; }

OUT124="$(python3 "$AEGIS_ROOT/verify/checks/124.py" "$AEGIS_ROOT" 2>&1)"
RC124=$?
if (( RC124 != 0 )); then
    fail "the reader of check 124 itself failed (rc $RC124) and nothing was measured about the skin: $OUT124"
    return
fi
SCOPE124=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE124="${hit#SCOPE: }" ;;
        *)       D124="$D124 $hit;" ;;
    esac
done <<< "$OUT124"

printf '    %s\n' "${SCOPE124:-the scope was not reported}"
if [[ -n "$D124" ]]; then
    fail "the skin loses what the renderer kept apart:$D124"
else
    pass "every state of the screen has a rule in the skin, and the one that means «could not look» is told apart without colour ($SCOPE124)"
fi
}
