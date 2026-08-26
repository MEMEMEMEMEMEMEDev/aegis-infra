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
