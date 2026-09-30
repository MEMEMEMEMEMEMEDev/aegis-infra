# verdict.sh — what each known vulnerability of a scan costs: stop, or debt
# with a date. ONE implementation, read by every job that scans (policy.yaml
# says why the platform stopped having one answer).
#
# POSIX sh + awk ON PURPOSE: it runs in the trivy container of each agent
# pod, which is busybox with no jq, no YAML parser and a `date` that does not
# read ISO dates. Dates are pure day arithmetic in awk. Invoked with `sh`
# (check 134: nothing in the seed is executable).
#
#   sh verdict.sh <findings>               a NEW admission: nothing runs yet
#   sh verdict.sh <findings> <reference>   a CHANGE: <reference> is the scan of
#                                          what runs today (empty file = clean)
#   sh verdict.sh --template                the trivy template the callers use
#   sh verdict.sh --diff-ids < config.json  an image config's layers, one per line
#
# <findings> and <reference> hold one finding per line, as trivy's template
# prints them (the template is TEMPLATE below, so callers do not retype it):
#
#   CVE|SEVERITY|PKG|INSTALLED|FIXED|PUBLISHED|PKGPATH|DIFFID|TARGET
#
# Env: POLICY (default: policy.yaml beside this file), KEV (default: kev.txt
# beside it), TODAY (default: today, UTC, YYYY-MM-DD — a parameter so the
# check can run it on any date).
#
# stdout, one line per finding:  VERDICT|CVE|SEVERITY|PKG|PKGPATH|PUBLISHED|DUE|WHY
#   block      the build/admission stops on it
#   debt       it passes; DUE is the day its window closes
#   overdue    inherited and past DUE: it passes (the change does not make it
#              worse) and the alerts say so every day
#   exploited  inherited and on the KEV list: it passes for the same reason,
#              and it is a critical alert from this moment
# stderr: the same in words, for the console of the build.
# rc 0 nothing stops · 1 something stops · 3 the verdict could not be given
# (no policy, a malformed line): an rc 3 is never read as clean.
#
# THE CHANGE IS JUDGED, NOT THE WORLD. A finding is the change's when it is
# not in <reference> (same CVE, same package, same path; the installed
# version may move and still be the same exposure). What is the change's
# stops, whatever its window. What was already running passes as debt: a
# build that does not make the running image worse cannot make it safer by
# failing, and failing it would block the urgent fix.
#
# A NEW ADMISSION has nothing to compare with, so the clock decides: inside
# its window it enters as debt; past it, or with no publication date, or on
# the KEV list, or with a KEV list too old to trust, it stops.
set -eu

HERE="$(dirname "$0")"
POLICY="${POLICY:-$HERE/policy.yaml}"
KEV="${KEV:-$HERE/kev.txt}"
TODAY="${TODAY:-$(date -u +%Y-%m-%d)}"
# shellcheck disable=SC2034  # read by the callers, which source nothing: they copy it with `sed -n`
TEMPLATE='{{range .}}{{$t := .Target}}{{range .Vulnerabilities}}{{.VulnerabilityID}}|{{.Severity}}|{{.PkgName}}|{{.InstalledVersion}}|{{.FixedVersion}}|{{if .PublishedDate}}{{.PublishedDate.Format "2006-01-02"}}{{end}}|{{.PkgPath}}|{{.Layer.DiffID}}|{{$t}}{{"\n"}}{{end}}{{end}}'

[ "${1:-}" = "--template" ] && { printf '%s\n' "$TEMPLATE"; exit 0; }
# --diff-ids: an image CONFIG on stdin (what `crane config` prints) → its
# layers' diff_ids, one per line. The config may come compact or pretty:
# distroless ships it indented over many lines, and a one-line reading
# found no layer at all on alpha-arch (2026-09-30), so every base finding
# was judged as the app's. Whitespace goes first; then the one array.
if [ "${1:-}" = "--diff-ids" ]; then
    tr -d ' \t\r\n' | sed -n 's/.*"diff_ids":\[\([^]]*\)\].*/\1/p' | tr ',' '\n' | tr -d '"' | grep '^sha256:' || true
    exit 0
fi
FINDINGS="${1:?usage: sh verdict.sh <findings> [<reference>] | --template}"
REFERENCE="${2:-}"
MODE=admit
[ -n "$REFERENCE" ] && MODE=change

[ -r "$POLICY" ] || { echo "verdict: no policy at $POLICY — no verdict can be given" >&2; exit 3; }
[ -r "$FINDINGS" ] || { echo "verdict: no findings file at $FINDINGS" >&2; exit 3; }
if [ "$MODE" = change ] && [ ! -r "$REFERENCE" ]; then
    echo "verdict: the reference $REFERENCE does not exist — a change with no reading of what runs is judged as a new admission by the CALLER, never here" >&2
    exit 3
fi
[ -r "$KEV" ] || KEV=/dev/null

awk -F'|' -v mode="$MODE" -v today="$TODAY" -v policy="$POLICY" -v kevfile="$KEV" -v ref="$REFERENCE" '
function dfc(s,   y, m, d, era, yoe, doy) {        # days from 1970-01-01, proleptic Gregorian
    if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1
    y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    if (m < 1 || m > 12 || d < 1 || d > 31) return -1
    if (m <= 2) y--
    era = int(y / 400); yoe = y - era * 400
    doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
    return era * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy - 719468
}
function civil(z,   era, doe, yoe, y, doy, mp, d, m) {
    z += 719468; era = int(z / 146097); doe = z - era * 146097
    yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
    y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
    mp = int((5 * doy + 2) / 153); d = doy - int((153 * mp + 2) / 5) + 1
    m = (mp < 10) ? mp + 3 : mp - 9
    if (m <= 2) y++
    return sprintf("%04d-%02d-%02d", y, m, d)
}
function say(v, why) {
    print v "|" $1 "|" $2 "|" $3 "|" $7 "|" $6 "|" due "|" why
    if (v == "block") blocks++
}
BEGIN {
    t = dfc(today)
    if (t < 0) { print "verdict: TODAY is not a date: " today > "/dev/stderr"; bad = 1; exit 3 }
    while ((getline line < policy) > 0) {
        if (line ~ /^[a-z_]+:[ \t]*[0-9]+[ \t]*(#.*)?$/) {
            k = line; sub(/:.*/, "", k); v = line; sub(/^[^:]*:[ \t]*/, "", v); sub(/[^0-9].*/, "", v)
            P[k] = v + 0
        }
    }
    close(policy)
    split("critical_days high_days kev_max_age_days", need, " ")
    for (i in need) if (!(need[i] in P)) {
        print "verdict: " policy " does not say " need[i] " — no verdict can be given" > "/dev/stderr"; bad = 1; exit 3
    }
    days["CRITICAL"] = P["critical_days"]; days["HIGH"] = P["high_days"]
    # The KEV list: a header line with the day CISA released it, then one id per line.
    kevknown = 0; kevwhy = "the exploited-in-the-wild list is missing"
    while ((getline line < kevfile) > 0) {
        if (line ~ /^# .*dateReleased=/) {
            r = line; sub(/.*dateReleased=/, "", r); r = substr(r, 1, 10)
            age = t - dfc(r)
            if (dfc(r) < 0) kevwhy = "the exploited-in-the-wild list has no readable date"
            else if (age > P["kev_max_age_days"]) kevwhy = "the exploited-in-the-wild list is " age " days old"
            else kevknown = 1
        } else if (line ~ /^CVE-/) KEVID[line] = 1
    }
    close(kevfile)
    if (mode == "change") {
        while ((getline line < ref) > 0) {
            if (line == "") continue
            n = split(line, f, "|")
            if (n != 9) { print "verdict: malformed reference line: " line > "/dev/stderr"; bad = 1; exit 3 }
            RUNS[f[1] "|" f[3] "|" f[7]] = 1
        }
        close(ref)
    }
}
$0 == "" { next }
NF != 9 { print "verdict: malformed finding line (9 fields expected): " $0 > "/dev/stderr"; bad = 1; exit 3 }
{
    seen++
    pub = dfc($6); due = "?"
    if (pub >= 0 && ($2 in days)) due = civil(pub + days[$2])
    if (!($2 in days)) { due = "?"; say("block", "severity " $2 " has no window in the policy"); next }
    kev = ($1 in KEVID)
    if (mode == "change" && !(($1 "|" $3 "|" $7) in RUNS)) {
        say("block", kev ? "your change brings it, and it is exploited in the wild" : "your change brings it: it is not in what runs today")
        next
    }
    if (mode == "change") {
        if (kev) { say("exploited", "already running, and exploited in the wild"); next }
        if (pub < 0) { say("debt", "already running; no publication date, so no due date"); next }
        if (t > pub + days[$2]) { say("overdue", "already running, past its window"); next }
        say("debt", "already running"); next
    }
    # a new admission
    if (kev) { say("block", "exploited in the wild: no window"); next }
    if (!kevknown) { say("block", kevwhy ": no debt credit without it"); next }
    if (pub < 0) { say("block", "no publication date: no clock to give it a window"); next }
    if (t > pub + days[$2]) { say("block", "published " $6 ", its window closed on " due); next }
    say("debt", "inside its window")
}
END {
    if (bad) exit 3
    printf "verdict (%s, %s): %d finding(s), %d stop%s\n", mode, today, seen + 0, blocks + 0, (blocks == 1 ? "" : "s") > "/dev/stderr"
    exit (blocks > 0) ? 1 : 0
}
' "$FINDINGS"
