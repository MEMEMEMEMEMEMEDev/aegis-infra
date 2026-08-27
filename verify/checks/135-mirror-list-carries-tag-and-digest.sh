# title: every mirrored image carries repo, tag AND digest — two fields, no more
# origin: new in v3 — 2026-08-27, the day image-watch learnt to ask whether upstream moved
check() {
# mirror-images/images.txt is the list of THIRD-PARTY images the platform
# pulls, scans and signs. Until 2026-08-27 the source column was
# `<repo>@sha256:…` and the tag lived in a comment: fine for a job that
# only pulls (a digest is all a pull needs), useless for a job that has
# to ASK a question — image-watch wants to know, every morning, whether
# the tag moved upstream and whether what it moved to is any cleaner.
# A machine cannot read a comment, so the tag went INTO the reference:
# `name:tag@digest`, which every registry client accepts (the tag is
# kept as text, the digest is what gets pulled).
#
# The three failure modes, each one silent in its own way:
#   · the tag missing: the pull still works, and image-watch reports the
#     image as «upstream did not move» forever — a green that measured
#     nothing;
#   · the digest missing: the pull follows a MUTABLE pointer, which is
#     the exact thing the digest pin exists to forbid;
#   · a third column: the parser of every instance alive reads two
#     fields (`read src dst`) and the third one lands INSIDE dst.
# The destination has to be `name:tag` too: an unqualified one would be
# pushed to whatever registry the client defaults to.
F="$P/mirror-images/images.txt"
[[ -f "$F" ]] || { fail "$F does not exist: there is no list of third-party images to mirror"; return; }
D135=""
n=0
while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    n=$((n+1))
    read -r -a f <<< "$line"
    if [[ ${#f[@]} -ne 2 ]]; then
        D135="$D135 line ${n} has ${#f[@]} fields instead of 2 (${f[0]:-?}…): the instances' parser reads exactly two;"
        continue
    fi
    [[ "${f[0]}" =~ ^[^[:space:]@]+:[^[:space:]@/]+@sha256:[0-9a-f]{64}$ ]] \
        || D135="$D135 source ${f[0]} is not <repo>:<tag>@sha256:<64 hex> (without the tag image-watch cannot ask whether upstream moved; without the digest the pull follows a mutable pointer);"
    [[ "${f[1]}" =~ ^[^[:space:]:/]+:[^[:space:]]+$ ]] \
        || D135="$D135 destination ${f[1]} is not <name>:<tag> (an unqualified destination goes to whatever registry the client defaults to);"
done < "$F"
(( n > 0 )) || D135="$D135 the list has no entries — the seed mirrors at least the bases the platform itself stands on;"
if [[ -n "$D135" ]]; then fail "images.txt:$D135"
else pass "$n mirrored images, every one <repo>:<tag>@sha256:<digest> → <name>:<tag>, two fields each"; fi
}
