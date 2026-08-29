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
