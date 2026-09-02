# teeth of check 175 — a FROM pinned by another installation is
# repointed by a verb, and by the registry that will serve it.

# THE STATE THE ARTIFACT WAS IN until 2026-09-02: nothing repointed
# anything. This is that state expressed in one line — the verb is
# there, it walks the repos, it reads the Containerfiles, and it hands
# every one of them back untouched. The operator is exactly where they
# were: four repos, four hand edits, and a from-guard refusing the
# build in the meantime.
red_1() {
    sed -i 's|^    return "".join(out), changes$|    return text, []|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}

# the digest out of a table of its own instead of out of `aegis image
# from`. It looks like it works —the reference has the right shape— and
# it is the exact failure the verb exists to end: a digest written down
# in the product is a second place for the truth to live, and nobody
# asked whether that image is SIGNED. Kyverno finds out at admission.
red_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-app" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = 'cache[(name, tag)] = _from_reference(f"{name}:{_current_tag(name, tag)}")'
new = ('cache[(name, tag)] = (f"{_internal_registry()}/{name}:{_current_tag(name, tag)}"\n'
       '                                  "@sha256:394ed28f6b1c0a5d3e2f47a90b18c6d5"\n'
       '                                  "4e7a3b90c1d2e3f405162738495a6b7c")')
assert old in s
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

# the dry mode taken away. This verb edits repositories that are not
# the platform's; without --check the only way to learn what it would
# rewrite is to let it rewrite.
red_3() {
    python3 - "$AEGIS_ROOT/libexec/aegis-app" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
i = s.index('    s.add_argument("--check", action="store_true",\n'
            '                   help="shows what it would rewrite')
j = s.index('on the way out)")\n', i) + len('on the way out)")\n')
open(p, "w", encoding="utf-8").write(s[:i] + s[j:])
PY
}

# the verb that the dispatcher cannot see. The menu, the help and check
# 112's validation of every invocation all read that one header line;
# out of it, the subcommand does not exist for the product.
red_4() {
    sed -i 's|^# aegis-subcommands: new apply rebase$|# aegis-subcommands: new apply|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}

# it pushes. Pinning an image and putting it in production are two
# decisions (images.md §2), and a verb that takes both leaves the
# operator finding out about a deploy from an alert.
red_5() {
    python3 - "$AEGIS_ROOT/libexec/aegis-app" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '                open(f, "w", encoding="utf-8").write(new)\n'
new = old + '                _git(d, "push")\n'
assert old in s
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

# the tag KEPT instead of derived. This is half of yesterday's bug and
# the half that is easiest to miss: the digest gets refreshed, the tag
# stays at 3.22-000001, and the reference names a tag this installation
# never built.
red_6() {
    sed -i 's|^    declared = _declared_tag(name)$|    return old\n    declared = _declared_tag(name)|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}

# parsed and never run: the subcommand exists, answers --help, and does
# nothing at all.
red_7() {
    sed -i 's|^        rebase(a.organization, not a.check, tot)$|        pass|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}

# the scanner broken: a scan that dies must take the check down with
# it, never wave it through. The lesson check 166 paid for, and the
# reason this check refuses any exit code it did not define.
red_8() {
    printf '\nraise SystemExit("the scanner is broken")\n' \
        >> "$AEGIS_ROOT/verify/checks/175.py"
}

# control: THE PROSE that explains the defect, in the same words, with
# a digest in it, with `git push` in it, and with a line that looks
# exactly like the subcommands header. This repo documents every
# decision beside the code, so the file that carries the defect carries
# the paragraph too — eight checks were accused by their own
# documentation in one day. If this turns the check red, it is reading
# prose as code.
control_1() {
    cat >> "$AEGIS_ROOT/libexec/aegis-app" <<'EOF'

# NOTE, kept beside the code on purpose:
# aegis-subcommands: new apply
# The bug of 2026-09-01 was a repo pinned to another installation:
#     FROM <internal>/aegis-base-nginx:3.22-000001@sha256:394ed28f6b1c0a5d3e2f47a90b18c6d54e7a3b90c1d2e3f405162738495a6b7c
# The wrong fix would have been a table of digests here and a
# `git push` at the end of the rewrite. Neither is done: the digest is
# asked of `aegis image from`, and the push is the operator's.
EOF
}

# control: rewording a message the command prints changes nothing that
# this check measures — if it goes red, the check is comparing text
# instead of exercising the verb.
control_2() {
    sed -i 's|there is no Containerfile to rebase|there is nothing here to rebase|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}

# control: another flag on the same subparser. The subparser's options
# are read in line order, and a check that guessed which parser an
# option belongs to by counting would break on this one.
control_3() {
    python3 - "$AEGIS_ROOT/libexec/aegis-app" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = 'on the way out)")\n'
new = old + '    s.add_argument("--quiet", action="store_true", help="fewer lines")\n'
assert old in s
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
