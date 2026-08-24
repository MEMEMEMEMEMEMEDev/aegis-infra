# teeth of check 111 (the glossary's ratchet)
#
# The real risk is not that someone deliberately rewrites `paths.py` as
# `rutas.py`: it is that a NEW file is born with the old habit and
# nobody notices, because the tree is still half in Spanish and one more
# word does not stand out.
red_1() {
    printf '\nOLD_PATHS = "lib/aegis/rutas.py"\n' >> "$AEGIS_ROOT/lib/aegis/paths.py"
}

# the same thing from the artifact's side, which is where it hurts
# most: a manifest that names a file by its retired name again.
red_2() {
    printf '\n# nothing\nold: planes.yaml\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/bootstrap/appprojects.yaml"
}

# and the case that proves the list is DERIVED from the document and not
# written into the check: adding a word to the glossary has to start
# watching it immediately.
#
# The word has to be ALIVE in the code, or the tooth proves nothing. The
# first version used `gris`, and on the very day it was written another
# front translated it to `gray`: the tooth lost its subject and stopped
# biting — which the full teeth run reported, since that is exactly what
# it exists for. It now uses `organizacion`, a CONTRACT KEY and
# therefore the last thing that will move (that is the coordinated
# change still pending).
red_3() {
    # INSIDE section 3, not at the end of the file: the check reads the
    # rows between "## 3." and "## 3b.", so a row appended after §4
    # would be watched by nobody. That is how the first attempt failed;
    # the second failed too, anchoring on `|---|---|---|`, because the
    # FIRST three-column separator in the document belongs to §2's
    # outcomes table. The anchor has to be a row that exists only in §3.
    # (and the sed delimiter is # and not |, because the rows are full
    #  of pipes — the third way this same tooth managed to fail.)
    sed -i 's#^| `marcas\.py` | `markers\.py` | |$#&\n| `organizacion` | `org` | |#' \
        "$AEGIS_ROOT/docs/glossary.md"
}

# control: telling the history in a COMMENT, naming a retired word, is
# legitimate — it is what checks 108 and 001 do. If this turned red, the
# ratchet would be erasing the repo's memory.
control_1() {
    printf '\n# history: this used to be called rutas.py and planes.yaml\n' \
        >> "$AEGIS_ROOT/lib/aegis/paths.py"
}
