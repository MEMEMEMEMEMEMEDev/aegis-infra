# title: every typeface the console carries is the one that was pinned, and it travels with its licence
# origin: new in v3 — 2026-09-11, the console is the first thing in the product to vendor a third-party binary
check() {
# THE CONSOLE IS THE FIRST PART OF THIS PRODUCT TO CARRY SOMEBODY
# ELSE'S BYTES. Until now every third party arrived as a container
# image, and there is a whole protocol for those: mirror-images pulls
# it ONCE, pinned by digest, scans it, signs it, and images.txt records
# where it came from. A font is the same kind of thing wearing a
# different extension, and it gets the same treatment rather than a new
# one.
#
# WHY NOT JUST LINK A CDN, which is what every other console does:
# nothing in this product fetches anything from the internet. A page
# served on loopback that phones a font host would do it on every load,
# from a machine whose whole point is that it is sovereign, and it
# would break the day that host does — or quietly serve different
# glyphs, which is worse. The design system's own rule said it first:
# self-hosted WOFF2 only, with the licence beside the file.
#
# Three questions, all derived from fonts/fonts.txt, none listed here:
#   · the file exists and hashes to what the manifest pins. A URL is a
#     promise somebody else can break; the content is not.
#   · every .woff2 in the tree is declared — an unpinned font is one
#     nobody measured, shipping to everybody who installs aegis.
#   · every face has its licence beside it. OFL requires it, and this
#     repository is public: it redistributes these bytes to strangers.
D126=""
FONTS126="$AEGIS_ROOT/share/console/fonts"
[[ -d "$FONTS126" ]] || { skip "the console carries no fonts ($FONTS126): nothing of a third party to pin"; return; }

OUT126="$(python3 "$AEGIS_ROOT/verify/checks/126.py" "$AEGIS_ROOT" 2>&1)"
RC126=$?
if (( RC126 != 0 )); then
    fail "the reader of check 126 itself failed (rc $RC126) and no font was compared against its pin: $OUT126"
    return
fi
SCOPE126=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE126="${hit#SCOPE: }" ;;
        *)       D126="$D126 $hit;" ;;
    esac
done <<< "$OUT126"

printf '    %s\n' "${SCOPE126:-the scope was not reported}"
if [[ -n "$D126" ]]; then
    fail "a typeface of the console is not the one that was pinned:$D126"
else
    pass "every face hashes to what fonts.txt pins, every one on disk is declared, and each travels with its licence ($SCOPE126)"
fi
}
