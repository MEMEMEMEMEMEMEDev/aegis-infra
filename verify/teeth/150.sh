# teeth for check 150 (the image command's edit reaches the branch the
# mirror job builds from). Written on 2026-08-29 with the fix for the
# adversarial review's blocking finding.
#
# The mutations are the BUG ITSELF in its four disguises, not cosmetic
# edits: the push taken out, the result of the push not verified, a
# second commit written outside the door, and a writer left without its
# commit.
IMG="libexec/aegis-image"

# THE BUG, exactly as it was found: commit_list commits and the job is
# fired over a remote that does not carry the commit. Every writing path
# breaks, and the --bump one breaks GREEN.
red_1() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
lines = [l for l in t.split("\n") if not l.strip().startswith("git_push_verified")]
assert len(lines) == len(t.split("\n")) - 1
open(p, "w").write("\n".join(lines))
PY
}

# the push stays and its RESULT stops being verified. A repo with no
# upstream, or one whose branch is not the one the Job DSL clones,
# pushes fine and satisfies nothing.
red_2() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
a = t.index('    up="$(git -C "$LIST_ROOT" rev-parse \'@{upstream}\' 2>/dev/null || true)"')
b = t.index('    log_info "the edit is on the remote branch')
head = t[:a]
head = head.replace('''    git -C "$LIST_ROOT" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1 \\
        || could_not "$LIST_ROOT has no upstream branch: the mirror job clones the platform repo from its remote, and a commit with nowhere to go is an edit the job never sees"\n''', "")
open(p, "w").write(head + t[b:])
PY
}

# a second door: a subcommand commits on its own, and that one has no
# push. It is how the bug comes back after being fixed once.
red_3() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "do_list() {\n    need_list\n"
assert t.count(old) == 1
new = "do_list() {\n    need_list\n    git_commit_if_changes \"$LIST_ROOT\" \"chore(mirror): tidy up\" \"$IMAGES_REL\"\n"
open(p, "w").write(t.replace(old, new, 1))
PY
}

# a writer without its commit: the file on disk carries the exception
# and the job builds a list that does not.
red_4() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '        commit_list "fix(mirror): dated exception for $ALLOW on $dst" "$IGNORE_REL"\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "", 1))
PY
}

# control: a comment inside commit_list explaining the push changes
# nothing about what runs.
control_1() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    git_push_verified "$LIST_ROOT"\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "    # git_commit_if_changes staged it; this is what the job will clone\n" + old, 1))
PY
}

# control: the wording of the log line is prose, not the property.
control_2() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'log_info "the edit is on the remote branch the mirror job builds from ($head)"'
assert t.count(old) == 1
new = 'log_info "pushed: the remote branch the mirror job clones is at $head"'
open(p, "w").write(t.replace(old, new, 1))
PY
}

# ── the read path ────────────────────────────────────────────────────
# `curl -f` comes back. It is the original bug in one character: a 404
# and a refused connection exit the same, and the caller reports «not
# mirrored» for a registry that is merely unreachable.
red_5() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "    retry_net 3 curl -sS --max-time 30 \\\n"
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "    retry_net 3 curl -fsS --max-time 30 \\\n", 1))
PY
}

# the 404 stops being its own answer: every non-200 becomes «it is not
# there». The registry answering 503 would then be reported as an image
# nobody mirrored, and the remedy printed would fire a build for it.
red_6() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = """    case "$code" in
        200) ;;
        404) return 1 ;;
        *)   log_warn "the internal registry answered HTTP $code for $1:$2 — a code is not a verdict about the image"; return 2 ;;
    esac
"""
assert t.count(old) == 1
new = """    case "$code" in
        200) ;;
        *)   return 1 ;;
    esac
"""
open(p, "w").write(t.replace(old, new, 1))
PY
}

# the swallow comes back to `from`, which is the contract the generators
# consume: an unanswered read becomes an empty value and the empty value
# becomes «it is not in the internal registry», rc 1.
red_7() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '''    d="$(reg_digest "$name" "$tag")" || rc=$?
    (( rc != 2 )) || could_not "the internal registry did not answer about $name:$tag — nothing is said about whether it is mirrored"
'''
assert t.count(old) == 1
new = '''    d="$(reg_digest "$name" "$tag" || true)"
    [[ -z "$d" ]] && rc=1
'''
open(p, "w").write(t.replace(old, new, 1))
PY
}

# the counter of unread rows goes back to being dead code. It is the
# defect exactly as it was found: `local unread=0` declared, the
# could_not that reads it written, and nothing in between incrementing
# it — so an unreachable registry prints a full table of «no» and exits 0.
red_8() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '        if (( rc == 2 )); then unread=$((unread+1)); mirrored="?"; signed="?"; short="—"\n'
assert t.count(old) == 1
new = '        if (( rc == 2 )); then mirrored="?"; signed="?"; short="—"\n'
t = t.replace(old, new, 1)
old2 = '             case "$sg" in 0) signed=yes ;; 1) signed=NO ;; *) signed="?"; unread=$((unread+1)) ;; esac\n'
assert t.count(old2) == 1
t = t.replace(old2, '             case "$sg" in 0) signed=yes ;; 1) signed=NO ;; *) signed="?" ;; esac\n', 1)
open(p, "w").write(t)
PY
}

# control: reg_head grows a legitimate curl flag that has an f in it and
# is not --fail. A mention is not a use, and neither is a letter.
control_3() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "        -o /dev/null -D \"$SECRETS_TMP/reg.hdr\" -w '%{http_code}' \\\n"
assert t.count(old) == 1
new = "        --no-keepalive -o /dev/null -D \"$SECRETS_TMP/reg.hdr\" -w '%{http_code}' \\\n"
open(p, "w").write(t.replace(old, new, 1))
PY
}

# control: a fourth HTTP code gets its own message. Telling 503 from 401
# is more detail, not less discipline.
control_4() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '        404) return 1 ;;\n        *)   log_warn "the internal registry answered HTTP $code for the signature of $1@$2"; return 2 ;;\n'
assert t.count(old) == 1
new = '        404) return 1 ;;\n        401) log_warn "the internal registry refused the credential"; return 2 ;;\n        *)   log_warn "the internal registry answered HTTP $code for the signature of $1@$2"; return 2 ;;\n'
open(p, "w").write(t.replace(old, new, 1))
PY
}

# ── whose red is it ──────────────────────────────────────────────────
# the scan report goes back to reading the WHOLE console. It is the
# defect as it was verified over a real console shape: asking for
# python:3.12-slim the day postgres:17.10-alpine grows a CRITICAL prints
# postgres's rows under the python request, and the `paths:` of the
# exception the command then suggests name postgres's scan target.
red_9() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '        report_scan "$slice" "$dst"\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, '        report_scan "$console" "$dst"\n', 1))
PY
}

# the attribution disappears: every red of the job is blamed on whatever
# image was asked for. «$dst was NOT mirrored» becomes a sentence the
# command has not measured and, when the entry that failed was another,
# a false one.
red_10() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
a = t.index('        # WHOSE RED IS IT')
b = t.index('        slice="$SECRETS_TMP/mirror-console-entry.txt"')
open(p, "w").write(t[:a] + '        local slice\n' + t[b:])
PY
}

# the --allow guard goes: the build failed on another entry and the
# command still writes the exception, scoped to that entry's scan
# targets, with the operator's measurement under a binary they never
# looked at.
red_11() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
a = t.index('            [[ -z "$ALLOW" ]] \\\n')
b = t.index('            red_elsewhere=1\n')
open(p, "w").write(t[:a] + t[b:])
PY
}

# control: the sentence that names the other failed entries is prose.
# Rewording it changes nothing about who the red is attributed to.
control_5() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'each one is its own request, with its own measurement; nothing below is about them'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, 'those are separate requests with separate measurements', 1))
PY
}

# control: the console gets read one more time, for a legitimate extra
# piece of evidence. More reading is not less discipline.
control_6() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '        report_scan "$slice" "$dst"\n'
assert t.count(old) == 1
new = old + '        log_error "  the entry\'s block of the console is $(wc -l < "$slice") lines long"\n'
open(p, "w").write(t.replace(old, new, 1))
PY
}
