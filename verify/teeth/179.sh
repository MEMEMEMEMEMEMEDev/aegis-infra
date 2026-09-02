# teeth of check 179 — no runtime message tells the operator that a
# verb this product dispatches does not exist.

# THE STATE THE ARTIFACT WAS IN until 2026-09-02: the sentence was
# true when written and the artifact outgrew it. `gc` was built, and
# the refusal kept sending the operator away from it — at the exact
# moment the disk was full and that verb was the answer.
red_1() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
viejo = ("The registry keeps every image ever built and nothing prunes it on its own, so an "
         "old build of this same engine is usually the biggest thing on the disk: "
         "\\`aegis image gc\\` lists what it would remove and removes nothing until you add --yes.")
nuevo = ("\\`aegis image gc\\` does not exist yet: the registry keeps every image ever built, "
         "and an old one of this engine is usually the biggest thing there.")
assert s.count(viejo) == 1, s.count(viejo)
open(p, "w", encoding="utf-8").write(s.replace(viejo, nuevo, 1))
PYEOF
}

# The same decay in Spanish, and about another verb: the operator is
# told to restore by hand what the product restores.
red_2() {
    python3 - "$AEGIS_ROOT/init/phases/80-supply-chain.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s += '\nlog_warn "`aegis data restore` no existe: hay que devolver el respaldo a mano"\n'
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# And with a subcommand that IS declared: naming the verb correctly and
# denying it is the most convincing version of the defect.
red_3() {
    printf '\nlog_info "note: `aegis image request` is not implemented, paste the FROM by hand"\n' \
        >> "$AEGIS_ROOT/init/phases/87-ai.sh"
}

# control: the PROSE that explains this very defect, in the words the
# defect is made of, in a runtime file. Explaining is not asserting,
# and a scan that cannot tell them apart accuses every fix it reads.
control_1() {
    cat >> "$AEGIS_ROOT/init/phases/87-ai.sh" <<'EOF'

# note: this refusal used to say `aegis image gc` does not exist yet.
# It did not exist when the sentence was written; it does now, and a
# message that says a verb no existe when it does sends the operator
# away from the answer.
EOF
}

# control: a TRUE claim of absence. `aegis seed update` is named in the
# README's own list of what the product cannot do yet, and nothing in
# libexec dispatches it. Saying so is honest, and a check that forbade
# it would forbid the artifact from declaring its own gaps.
control_2() {
    printf '\nlog_warn "`aegis seed update` does not exist: bring the fix over by hand"\n' \
        >> "$AEGIS_ROOT/init/phases/87-ai.sh"
}
