# title: the image command lands its edit where the job reads it, and never guesses a read
# origin: new in v3 — 2026-08-29, adversarial review of `aegis image`: it committed the list and never pushed it
check() {
# `aegis image request` is the only command in the product that EDITS
# the platform repo and then asks a Jenkins job to act on the edit. That
# makes it the one place where the difference between «written here» and
# «readable there» decides whether the command tells the truth.
#
# THE BUG THIS WAS BORN FROM. `mirror-images` is a pipeline-from-SCM:
# the Job DSL in k8s/base/platform/jenkins/values.yaml points it at the
# platform repo's REMOTE, branch main, and its `parse list` stage does
# readFile('mirror-images/images.txt') over that checkout. The command
# committed the line locally and fired the job. The job re-mirrored the
# PREVIOUS list, ended SUCCESS, and every one of the four writing paths
# broke in a different disguise — the worst of them green: a `--bump`
# re-mirrored the OLD digest, the registry served it, and the FROM
# printed carried a digest the list on disk no longer declared.
#
# It is the class lib/common.sh names on git_push_verified («a failed
# push that carries on leaves a local commit unpushed → ArgoCD does not
# see the file → broken ONE PHASE later»), arriving here through a
# different door: not a push that failed, a push nobody wrote.
D150=""
IMG="$LIBEXEC/aegis-image"
[[ -f "$IMG" ]] || { fail "libexec/aegis-image does not exist: this check has no subject"; return; }

CL="$(body_nc commit_list "$IMG")"
DR="$(body_nc do_request "$IMG")"
[[ -n "$CL" ]] || D150="$D150 aegis-image has no commit_list function: the single door every edit to the list goes through is gone;"
[[ -n "$DR" ]] || D150="$D150 aegis-image has no do_request function;"

# ── the write path: committed is not the same as readable by the job ──
grep -q 'git_push_verified' <<< "$CL" \
    || D150="$D150 commit_list commits and does not push: the mirror job clones the platform repo from its remote, so it would mirror the list as it was BEFORE the edit and still end SUCCESS;"
# The push's exit code is not the property. What has to be true is that
# the remote branch NOW CONTAINS the commit, which is what the job will
# clone — and a repo with no upstream, or pushed onto another branch,
# exits 0 and satisfies nothing.
grep -q '@{upstream}' <<< "$CL" \
    || D150="$D150 commit_list does not contrast HEAD against the remote branch after pushing: «push exited 0» is not «the job will read this commit»;"
# ONE DOOR. A second commit written straight into a subcommand is a
# second path that has to remember to push, and the one that forgets is
# the one nobody notices.
N_ALL="$(nc "$IMG" | grep -c 'git_commit_if_changes' || true)"
N_CL="$(grep -c 'git_commit_if_changes' <<< "$CL" || true)"
(( N_ALL == N_CL && N_CL >= 1 )) \
    || D150="$D150 aegis-image commits outside commit_list ($N_ALL calls to git_commit_if_changes, $N_CL of them inside commit_list): every edit has to leave through the door that pushes;"
# Every writer is followed by its commit. The three that mutate the
# instance's files are write_entry, bump_entry and write_exception; if
# one of them ever lands without a commit_list beside it, the job builds
# a list that does not contain it.
N_W="$(grep -cE '(^|[^_[:alnum:]])(write_entry|bump_entry|write_exception) ' <<< "$DR" || true)"
N_C="$(grep -cE '(^|[^_[:alnum:]])commit_list ' <<< "$DR" || true)"
(( N_W >= 3 && N_C == N_W )) \
    || D150="$D150 do_request calls $N_W writer(s) of the list and $N_C commit_list(s): a write with no commit beside it is a file the job never reads (three writers expected: write_entry, bump_entry, write_exception);"

# ── the read path: a socket that did not answer is not a verdict ─────
# The header of libexec/aegis-image promises the house's third exit
# code for «no registry answer», and it was not being paid. `curl -f`
# returns the same failed exit for a 404 and for a refused connection,
# and the caller read that as «the image is not mirrored». MEASURED with
# REGISTRY_CLUSTER_IP=127.0.0.1: `image check` reported the seven
# declared images as «declared and NOT mirrored», each line offering to
# fire a mirror build; `image from` —the contract the generators
# consume— answered rc 1, «is not in the internal registry», to a
# question it had never managed to ask.
# joined, because the curl of reg_head is split over five lines and a
# flag on a continuation is still a flag.
RH="$(body_nc reg_head "$IMG" | sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}')"
[[ -n "$RH" ]] || D150="$D150 aegis-image has no reg_head: the single place where a read of the internal registry becomes an HTTP code is gone;"
grep -qE '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)|--fail' <<< "$RH" \
    && D150="$D150 reg_head asks curl to fail on an HTTP error (-f/--fail): a 404 and a refused connection then come back as the same exit, and «the registry does not have it» stops being distinguishable from «the registry did not answer»;"
grep -q '%{http_code}' <<< "$RH" \
    || D150="$D150 reg_head does not read the HTTP code: without it there is nothing to tell the two failures apart with;"
for fn in reg_digest reg_signed; do
    B="$(body_nc "$fn" "$IMG")"
    grep -qE '^[[:space:]]*404\)' <<< "$B" \
        || D150="$D150 $fn does not treat 404 as its own answer: the registry saying «I do not have it» is the only failure that is a VERDICT about the image;"
    grep -qE 'return 2' <<< "$B" \
        || D150="$D150 $fn never returns 2: a read that did not happen would come back as a measurement;"
done

# Every subcommand that reads the registry has to ASK whether the read
# happened. A caller that only looks at the value cannot tell an empty
# answer from no answer at all.
for fn in do_request do_list do_from do_check; do
    B="$(body_nc "$fn" "$IMG")"
    grep -qE 'reg_digest|reg_signed' <<< "$B" || continue
    grep -qE '\(\([[:space:]]*(rc|sg)[[:space:]]*[!=]=[[:space:]]*2[[:space:]]*\)\)' <<< "$B" \
        || D150="$D150 $fn reads the internal registry and never asks whether the read happened: an unanswered socket comes out of it as a verdict about the image;"
done
# The swallow, by name. `|| true` over a read is the idiom that turns
# «it did not answer» into «it is empty», which is the bug itself.
SWALLOW="$(nc "$IMG" | grep -nE 'reg_(digest|signed)[^|]*\|\|[[:space:]]*true' | tr '\n' ' ' || true)"
[[ -n "$SWALLOW" ]] \
    && D150="$D150 a read of the registry is swallowed with || true ($SWALLOW): the failure of the read becomes an empty value, and the empty value becomes a verdict;"
# The counter that was declared and never incremented: dead code that
# made `list` promise a verdict it could not give.
LB="$(body_nc do_list "$IMG")"
if grep -q 'unread=0' <<< "$LB"; then
    grep -q 'unread=$((unread+1))' <<< "$LB" \
        || D150="$D150 do_list declares the unread counter and never increments it: the could_not that reads it is dead code, and an unreachable registry prints a full table of «no»;"
fi

# ── the red of the job belongs to the entry that failed ──────────────
# `mirror-images` mirrors and scans EVERY entry of images.txt on every
# run and fails at the end with the list of what broke. Attributing that
# red to whatever image was asked for today produced, verified over a
# real console: «python:3.12-slim was NOT mirrored», the CRITICAL rows
# of postgres listed under it, and `--allow <postgres CVE>` suggested
# under the python request — a dated exception filed against the wrong
# binary, carrying a measurement about another one.
for fn in failed_entries console_slice; do
    [[ -n "$(body_nc "$fn" "$IMG")" ]] \
        || D150="$D150 aegis-image has no $fn: without it the console of a build that mirrors every entry cannot be scoped to the one that was asked for;"
done
LN_ATTR="$(grep -n 'failed_entries' <<< "$DR" | head -1 | cut -d: -f1)"
LN_BLAME="$(grep -n 'was NOT mirrored' <<< "$DR" | head -1 | cut -d: -f1)"
if [[ -z "$LN_ATTR" ]]; then
    D150="$D150 do_request never asks which entries the build actually failed on: «X was NOT mirrored» is then said about whichever image was requested, true or not;"
elif [[ -n "$LN_BLAME" ]] && (( LN_ATTR > LN_BLAME )); then
    D150="$D150 do_request blames the requested image before reading who failed (line $LN_BLAME of the body, attribution at $LN_ATTR): the sentence is printed and only then checked;"
fi
grep -q 'report_scan "$slice"' <<< "$DR" \
    || D150="$D150 do_request does not scope the scan report to this entry's block of the console: the findings of every other broken image get printed under this request, and an exception's paths would be scoped to them;"
grep -q 'report_scan "$console"' <<< "$DR" \
    && D150="$D150 do_request reports the scan over the WHOLE console: that is the defect itself — the rows belong to whatever entry produced them, not to the one that was asked for;"
grep -q 'python3 - "$slice" "$ALLOW"' <<< "$DR" \
    || D150="$D150 the scan targets an exception is scoped to are read from the whole console instead of this entry's block: the paths written into trivyignore.yaml would name another image's scan;"
# The exception cannot be written under a request that did not fail.
awk '
  index($0, "grep -qxF")   { a = NR }
  index($0, "red_elsewhere=1") { b = NR }
  { L[NR] = $0 }
  END {
      if (!a || !b || a >= b) exit 1
      for (i = a; i <= b; i++) if (index(L[i], "-z \"$ALLOW\"")) exit 0
      exit 1
  }' <<< "$DR" \
    || D150="$D150 --allow is not refused when the build did not fail on the image being requested: the operator would write a dated exception, under the wrong request, whose measurement talks about another binary;"

if [[ -n "$D150" ]]; then fail "the image command's edit does not reach the job, its reads are guessed, or a red is blamed on the wrong image:$D150"
else pass "aegis image pushes what it commits before firing the job that reads it, never turns an unanswered read into a verdict, and blames a red only on the entry that produced it"; fi
}
