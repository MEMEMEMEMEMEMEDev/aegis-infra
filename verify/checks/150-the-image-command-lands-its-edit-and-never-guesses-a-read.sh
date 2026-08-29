# title: the image command's edit reaches the branch the job builds from
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

if [[ -n "$D150" ]]; then fail "the image command's edit does not reach the job:$D150"
else pass "aegis image commits, pushes and verifies the remote branch before firing the job that reads it"; fi
}
