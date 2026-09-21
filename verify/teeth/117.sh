# teeth for check 117 (the product names no person)
#
# All four reds are regressions that were LIVE on 2026-08-26, the day
# the artifact was first measured as what ships to everybody.

# the worst one, and it was not a comment: the VM's admin account
# created with the name of whoever wrote the template
red_1() {
    sed -i 's/^  - name: aegis$/  - name: '"$(id -un)"'/' \
        "$AEGIS_ROOT/seed/platform/vps/clouding-lab.cloud-init.yaml.tpl"
}

# a path that exists on exactly one computer on earth
red_2() {
    printf '\nREFERENCE="/home/%s/workspace/aegis-v2"\n' "$(id -un)" \
        >> "$AEGIS_ROOT/verify/harness/org-equivalence.sh"
}

# the macOS spelling of the same thing: a check that only knew /home
# would pass an artifact written on a laptop
red_3() {
    printf '\n# the tree lived in /Users/somebody/dev/aegis while this was written\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# the identity of whoever is building it, quoted in a comment. A name in
# a comment is still a name.
red_4() {
    printf '\n# handed over by %s during the rehearsal\n' "$(id -un)" \
        >> "$AEGIS_ROOT/libexec/aegis-verify"
}

# the account this repository is published from, quoted in a comment:
# what the first CI run (2026-09-21) turned out to measure INSTEAD of a
# login, because on a CI platform the login is the platform's. Read from
# the origin of the clone, so this bites on every machine that has one.
# (The CI branch itself, where the login is declared NOT measured, is
# an environment and not a tree: it is exercised by running the check
# with GITHUB_ACTIONS=true USER=runner, and by the workflow's own run.)
red_5() {
    local owner
    owner="$(git -C "$AEGIS_ROOT" remote get-url origin 2>/dev/null \
        | sed -nE 's#^.*github\.com[:/]([^/]+)/.*$#\1#p')"
    [[ -n "$owner" ]] || return 1
    printf '\n# the repository lives under github.com/%s while this was written\n' "$owner" \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# control: the portable way of saying the same thing is exactly what
# belongs here, and the tree is full of it
control_1() {
    printf '\nBACKUPS="$HOME/aegis-backups"   # and ~/aegis-backups reads the same\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# control: a placeholder home in a document, which is how a protocol
# tells the reader to put THEIR path
control_2() {
    printf '\nexport AEGIS_BACKUPS=/home/<your user>/backups\n' \
        >> "$AEGIS_ROOT/docs/OPERATE.md"
}
