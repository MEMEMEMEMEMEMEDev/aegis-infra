# teeth of check 157 — the wizard offers no answer the artifact cannot
# honour. Every red below was applied over a copy of the tree and the
# check went red.

# THE FOUNDING REGRESSION, run backwards: take phase 87 away and `gpu`
# and `cpu` go back to being answers nobody serves. This is the state
# the artifact was actually in until 2026-08-29, and the check has to
# be able to see it — otherwise it was written to fit today's tree.
# THE WIZARD GOES ON OFFERING A VALUE AND NOBODY CARRIES IT OUT, which
# is the defect this check exists for and the shape `AI=gpu` had before
# phase 87 was written.
#
# It used to delete four files, on the assumption that they were the
# only ones serving those values. The product grew and the assumption
# stopped holding —the GPU runtime is set up in phase 20, the CI carries
# it, the host measures it— so deleting those four changed nothing and
# the tooth went quiet. Now the VALUE is taken out of every consumer and
# left in the validator, which is the defect itself rather than a guess
# about where it would come from.
red_1() { python3 - "$AEGIS_ROOT" <<'P'
import sys, pathlib, re
root = pathlib.Path(sys.argv[1])
keep = root / "lib" / "config.sh"          # the wizard goes on offering it
word = re.compile(r"(?<![A-Za-z0-9_])gpu(?![A-Za-z0-9_])")
touched = 0
for d in ("init", "libexec", "lib", "seed"):
    base = root / d
    if not base.is_dir():
        continue
    for f in base.rglob("*"):
        if not f.is_file() or f == keep:
            continue
        try:
            text = f.read_text(errors="replace")
        except Exception:
            continue
        if word.search(text):
            f.write_text(word.sub("xpu", text))
            touched += 1
assert touched, "re-aim this tooth: nothing names `gpu` outside the validator"
P
}

# a value ADDED to the validator and served by nobody: the same defect
# arriving by the other door, which is the one a new question opens.
red_2() {
    sed -i 's/_v_ai()      { \[\[ "$1" == no || "$1" == cpu || "$1" == gpu \]\]; }/_v_ai()      { [[ "$1" == no || "$1" == cpu || "$1" == gpu || "$1" == tpu ]]; }/' \
        "$AEGIS_ROOT/lib/config.sh"
}

# a default the wizard's own validator rejects: pressing Enter would be
# refused by the question that offered it.
red_3() { sed -i 's/ask AI "no" _v_ai/ask AI "none" _v_ai/' "$AEGIS_ROOT/lib/config.sh"; }

# the same, on the other question, so the check is not reading one
# variable by name.
red_4() { sed -i 's/ask EDGE "cloudflare" _v_edge/ask EDGE "cloudfare" _v_edge/' "$AEGIS_ROOT/lib/config.sh"; }

# and the check's own subject taken away: with no ask() bound to an
# enumerating validator, finding nothing must NOT be reported as
# nothing wrong. This is the shape of the bug found in check 004 on
# 2026-08-29.
red_5() { sed -i 's/^    ask AI /    #ask AI /; s/^    ask EDGE /    #ask EDGE /' "$AEGIS_ROOT/lib/config.sh"; }

# control: another value, served, cannot turn it red.
control_1() {
    sed -i 's/_v_ai()      { \[\[ "$1" == no || "$1" == cpu || "$1" == gpu \]\]; }/_v_ai()      { [[ "$1" == no || "$1" == cpu || "$1" == gpu || "$1" == local ]]; }/' \
        "$AEGIS_ROOT/lib/config.sh"
}

# control: prose about a value that is served changes nothing.
control_2() { printf '\n# note: gpu needs the container toolkit.\n' >> "$AEGIS_ROOT/lib/config.sh"; }
