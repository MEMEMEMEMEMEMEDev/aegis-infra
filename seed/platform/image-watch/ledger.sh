# image-watch/ledger.sh — the ledger: every known vulnerability of what the
# platform serves, with the day it falls due and who fixes it.
#
# WHY A LEDGER. Until plan/21 the watch published COUNTS: «aegis-base-node:
# 2 HIGH». A count cannot say since when, until when, or whose move it is,
# and every reader (the round, the console, the alerts) had to ask the
# metrics the same question in its own words. Once the door started letting
# findings in as DEBT (verdict.sh), somebody had to keep the books: this
# file writes them, the watch commits them to the platform repo when they
# change, and `aegis vulns`, `aegis check`, the console and the alerts read
# the same lines.
#
#   sh ledger.sh <inventory> [<previous-ledger>]   writes the ledger
#   sh ledger.sh --metrics <ledger>                  its series, for vmsingle
#
# <inventory>, one image per line:  IMAGE|KIND|DIGEST|FIXER|FINDINGS
#   KIND      mirror · base · app
#   FIXER     who moves when it is due, in words (the base loop, upstream,
#             an app's repo)
#   FINDINGS  a file of verdict.sh's template lines for that image, or
#             EMPTY when the watch could not measure it
# <previous-ledger>  yesterday's ledger: it keeps the day a finding with no
#             publication date was first seen (its clock), so the window
#             does not restart every morning.
#
# Env: VP (the vuln-policy directory: verdict.sh, policy.yaml, kev.txt),
# TODAY (YYYY-MM-DD, default today UTC), IGNOREFILE (the mirror's
# trivyignore.yaml, optional: its exceptions in force are listed too).
#
# stdout: the ledger. Two comment lines, then one line per finding, sorted
# (so that the file only changes when the books do):
#
#   STATE|IMAGE|KIND|DIGEST|CVE|SEVERITY|PKG|INSTALLED|FIXED|PKGPATH|SINCE|CLOCK|DUE|FIXER
#
#   clean       the image was scanned this morning and carries nothing:
#               one line per image, so «looked at and clean» is never the
#               same as «not in the books»
#   debt        inside its window; DUE is the day it closes
#   overdue     past DUE: nothing stops, the alerts say it every day
#   exploited   on CISA's exploited-in-the-wild list: a critical alert now
#   unmeasured  the image (or the exploited list) could not be looked at:
#               NEVER read as clean. CVE..FIXED are empty, PKGPATH says why
#   excused     an exception in force (trivyignore.yaml); CLOCK says which
#               class (measured · accepted), DUE the day it lapses
#
# --metrics prints, for each image the ledger names:
#   aegis_vuln_findings{image,kind,state}  debt · due_soon · overdue ·
#       exploited, explicit zeros included (due_soon is the debt in the last
#       third of its window, carved out of debt)
#   aegis_vuln_unmeasured{image,kind}      1 when it could not be looked at
# and aegis_vuln_excused{class} for the exceptions in force.
#
# SINCE is the CVE's publication day (CLOCK=published) or, when the
# database has none, the day the watch first saw it (CLOCK=first-seen).
#
# POSIX sh + awk: it runs in the trivy container (busybox), next to
# verdict.sh. Invoked with `sh` (nothing in the seed is executable).
# rc 0 the ledger was written · 3 it could not be (no verdict.sh, no policy,
# an unreadable inventory): rc 3 leaves NO ledger, never a partial one.
set -eu

# Days from 1970-01-01 of a YYYY-MM-DD (proleptic Gregorian), -1 if it is not
# one. The same arithmetic as verdict.sh: busybox's date does not read ISO.
DFC='function dfc(s,   y, m, d, era, yoe, doy) {
    if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1
    y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    if (m <= 2) y--
    era = int(y / 400); yoe = y - era * 400
    doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
    return era * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy - 719468
}'

if [ "${1:-}" = "--metrics" ]; then
    L="${2:?usage: sh ledger.sh --metrics <ledger>}"
    [ -r "$L" ] || { echo "ledger: no ledger at $L" >&2; exit 3; }
    awk -F'|' -v today="${TODAY:-$(date -u +%Y-%m-%d)}" "$DFC"'
    /^#/ || NF != 14 { next }
    $1 == "excused" { X[$12]++; next }
    {
        k = $2 "|" $3
        if (!(k in SEEN)) { SEEN[k] = 1; ORDER[++n] = k }
        if ($1 == "unmeasured") { U[k] = 1; next }
        if ($1 == "debt" && $13 != "?" && $13 != "") {
            t = dfc(today); due = dfc($13); since = dfc($11)
            if (since >= 0 && due >= 0 && t >= due - int((due - since) / 3)) { C[k "|due_soon"]++; next }
        }
        if ($1 != "clean") C[k "|" $1]++
    }
    END {
        split("debt due_soon overdue exploited", st, " ")
        for (i = 1; i <= n; i++) {
            split(ORDER[i], a, "|")
            lab = "image=\"" a[1] "\",kind=\"" a[2] "\""
            printf "aegis_vuln_unmeasured{%s} %d\n", lab, (ORDER[i] in U) ? 1 : 0
            if (ORDER[i] in U) continue
            for (j = 1; j <= 4; j++) printf "aegis_vuln_findings{%s,state=\"%s\"} %d\n", lab, st[j], C[ORDER[i] "|" st[j]] + 0
        }
        printf "aegis_vuln_excused{class=\"measured\"} %d\n", X["measured"] + 0
        printf "aegis_vuln_excused{class=\"accepted\"} %d\n", X["accepted"] + 0
    }' "$L"
    exit 0
fi

INV="${1:?usage: sh ledger.sh <inventory> [<previous-ledger>]}"
PREV="${2:-}"
VP="${VP:?VP must name the vuln-policy directory}"
TODAY="${TODAY:-$(date -u +%Y-%m-%d)}"
IGNOREFILE="${IGNOREFILE:-}"
export TODAY

[ -r "$INV" ] || { echo "ledger: no inventory at $INV" >&2; exit 3; }
[ -r "$VP/verdict.sh" ] || { echo "ledger: no verdict.sh in $VP" >&2; exit 3; }
[ -r "$VP/policy.yaml" ] || { echo "ledger: no policy.yaml in $VP" >&2; exit 3; }
[ -n "$PREV" ] && [ ! -r "$PREV" ] && PREV=""

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/body"

# The first-seen clocks of yesterday, keyed IMAGE|CVE|PKG|PKGPATH.
: > "$WORK/firstseen"
if [ -n "$PREV" ]; then
    awk -F'|' '!/^#/ && NF == 14 && $12 == "first-seen" { print $2 "|" $5 "|" $7 "|" $10 "|" $11 }' "$PREV" > "$WORK/firstseen"
fi

n=0
while IFS= read -r entry || [ -n "$entry" ]; do
    case "$entry" in ''|'#'*) continue ;; esac
    n=$((n + 1))
    img="$(printf '%s' "$entry" | cut -d'|' -f1)"
    kind="$(printf '%s' "$entry" | cut -d'|' -f2)"
    dig="$(printf '%s' "$entry" | cut -d'|' -f3)"
    fixer="$(printf '%s' "$entry" | cut -d'|' -f4)"
    file="$(printf '%s' "$entry" | cut -d'|' -f5-)"
    if [ -z "$img" ] || [ -z "$kind" ]; then
        echo "ledger: malformed inventory line: $entry" >&2; exit 3
    fi
    if [ -z "$file" ] || [ ! -r "$file" ]; then
        printf 'unmeasured|%s|%s|%s||||||the watch could not scan it this morning||||%s\n' \
            "$img" "$kind" "$dig" "$fixer" >> "$WORK/body"
        continue
    fi
    # The clock of a finding with no publication date: the day it was first
    # seen, carried from yesterday's ledger, or today. Marked so the line
    # says which clock it runs on.
    awk -F'|' -v OFS='|' -v img="$img" -v today="$TODAY" -v fs="$WORK/firstseen" '
        BEGIN { while ((getline l < fs) > 0) { split(l, a, "|"); F[a[1] "|" a[2] "|" a[3] "|" a[4]] = a[5] } }
        $0 == "" { next }
        {
            clock = "published"
            if ($6 == "") { k = img "|" $1 "|" $3 "|" $7; $6 = (k in F) ? F[k] : today; clock = "first-seen" }
            print > "/dev/stdout"; print clock > "/dev/stderr"
        }' "$file" > "$WORK/f.$n" 2> "$WORK/c.$n"
    if [ ! -s "$WORK/f.$n" ]; then
        printf 'clean|%s|%s|%s||||||||||%s\n' "$img" "$kind" "$dig" "$fixer" >> "$WORK/body"
        continue
    fi
    # Everything here is ALREADY RUNNING: the file is its own reference, so
    # the verdict gives each one its window, never a stop.
    rc=0
    sh "$VP/verdict.sh" "$WORK/f.$n" "$WORK/f.$n" > "$WORK/v.$n" 2> "$WORK/e.$n" || rc=$?
    if [ "$rc" -ne 0 ]; then
        why="$(tail -1 "$WORK/e.$n" | tr '|' '/' | cut -c1-160)"
        printf 'unmeasured|%s|%s|%s||||||its findings could not be judged: %s||||%s\n' \
            "$img" "$kind" "$dig" "$why" "$fixer" >> "$WORK/body"
        continue
    fi
    # verdict.sh prints one line per finding, in order: the three files are
    # read side by side.
    awk -F'|' -v OFS='|' -v img="$img" -v kind="$kind" -v dig="$dig" -v fixer="$fixer" \
        -v vf="$WORK/v.$n" -v cf="$WORK/c.$n" '
        {
            if ((getline v < vf) <= 0 || (getline c < cf) <= 0) { print "ledger: the verdict is shorter than the findings" > "/dev/stderr"; exit 3 }
            split(v, V, "|")
            print V[1], img, kind, dig, $1, $2, $3, $4, $5, $7, $6, c, V[7], fixer
        }' "$WORK/f.$n" >> "$WORK/body" || exit 3
done < "$INV"

[ "$n" -gt 0 ] || { echo "ledger: the inventory names no image" >&2; exit 3; }

# The exploited-in-the-wild list itself: a list too old to trust cannot say
# «not exploited», and the ledger says so in a line of its own.
awk -v today="$TODAY" -v pol="$VP/policy.yaml" -v kev="$VP/kev.txt" "$DFC"'
BEGIN {
    max = -1
    while ((getline l < pol) > 0) if (l ~ /^kev_max_age_days:/) { sub(/^[^:]*:[ \t]*/, "", l); max = l + 0 }
    rel = ""
    while ((getline l < kev) > 0) if (l ~ /dateReleased=/) { rel = l; sub(/.*dateReleased=/, "", rel); rel = substr(rel, 1, 10) }
    why = ""
    if (rel == "" || dfc(rel) < 0) why = "the exploited-in-the-wild list is missing or has no date"
    else if (max >= 0 && dfc(today) - dfc(rel) > max) why = "the exploited-in-the-wild list is " (dfc(today) - dfc(rel)) " days old"
    if (why != "") print "unmeasured|exploited-list|kev||||||" why "||||the watch refreshes it every morning"
}' >> "$WORK/body"

# The exceptions in force: each `- id:` of trivyignore.yaml with its paths,
# its lapse date and its class (an accepted risk says so in its statement).
if [ -n "$IGNOREFILE" ] && [ -r "$IGNOREFILE" ]; then
    awk -v today="$TODAY" '
        function flush() {
            if (id != "" && (lapse == "" || lapse >= today))
                print "excused|*|exception||" id "|||||" paths "||" cls "|" (lapse == "" ? "never" : lapse) "|trivyignore.yaml"
            id = ""; paths = ""; lapse = ""; cls = "measured"
        }
        /^[a-z_]+:/ { flush(); sec = $1; sub(/:.*/, "", sec); next }
        sec != "vulnerabilities" { next }
        /^[[:space:]]*-[[:space:]]*id:/ { flush(); id = $0; sub(/.*id:[[:space:]]*/, "", id); sub(/[[:space:]#].*/, "", id); gsub(/"/, "", id); next }
        /^[[:space:]]*paths:/ { paths = $0; sub(/.*paths:[[:space:]]*/, "", paths); gsub(/[][" \t]/, "", paths); gsub(/\|/, "/", paths); next }
        /^[[:space:]]*statement:/ { if ($0 ~ /Risk accepted/) cls = "accepted"; next }
        /^[[:space:]]*expired_at:/ { lapse = $0; sub(/.*expired_at:[[:space:]]*/, "", lapse); sub(/[[:space:]].*/, "", lapse); gsub(/"/, "", lapse); next }
        END { flush() }
    ' "$IGNOREFILE" >> "$WORK/body"
fi

echo "# aegis vulnerability ledger — written by image-watch (image-watch/ledger.sh); read by aegis vulns, aegis check and the console."
echo "# STATE|IMAGE|KIND|DIGEST|CVE|SEVERITY|PKG|INSTALLED|FIXED|PKGPATH|SINCE|CLOCK|DUE|FIXER"
LC_ALL=C sort -u "$WORK/body"
