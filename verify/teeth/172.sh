# teeth of check 172 — every secret an organization's generator declares
# has somebody in the artifact that makes it.

# THE STATE THE ARTIFACT WAS IN until 2026-09-02: `create` looked for a
# recipe, found none for the regcred, printed «no recipe» and returned
# 0. The derivation goes away and the organization is back to a
# kustomize build that dies on a file nobody wrote.
red_1() {
    sed -i 's/copy_source_for(name, path)/None/' "$AEGIS_ROOT/libexec/aegis-secret"
}

# The call is still there and the search finds nothing: the same hole,
# one floor down. A derivation that always answers «no origin» is a
# derivation that is not there.
red_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-secret" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "def copy_source_for(name, target):\n"
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, old + "    return None\n", 1))
PY
}

# The origin is looked for ONLY among the organizations. The platform's
# namespaces are where the init actually derives the credential, so a
# search that skips them finds nothing on a fresh instance — and finds
# the canary's copy on the house machine, which is how this would have
# looked healthy right up to the first clean install.
red_3() {
    sed -i 's|os.path.join(k8s, "base", "\*", filename)|os.path.join(k8s, "base", "*", "__none__", filename)|; s|os.path.join(k8s, "base", "\*", "\*", filename)|os.path.join(k8s, "base", "*", "*", "__none__", filename)|' \
        "$AEGIS_ROOT/libexec/aegis-secret"
}

# A generator that grows an entry nobody can make. The subject is
# DERIVED from the generators, so a new line has to be seen without
# anybody adding it to a list here.
red_4() {
    printf '  - secret-registry-mirror-token.enc.yaml\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/secret-generator.yaml"
}

# The other half of the derivation: `org.secrets_of` is what RENDERS
# every organization's generator, so a secret it learns to emit has to
# be a secret the command learns to make, in the same commit.
red_5() {
    sed -i 's|    s = \["secret-regcred-internal.enc.yaml"\]|    s = ["secret-regcred-internal.enc.yaml", "secret-tenant-mesh-identity.enc.yaml"]|' \
        "$AEGIS_ROOT/lib/aegis/org.py"
}

# The scanner broken: a scan that dies must take the check with it,
# never wave it through (the lesson check 166 paid for).
red_6() {
    printf '\nraise SystemExit("the scanner is broken")\n' >> "$AEGIS_ROOT/verify/checks/172.py"
}

# control: THE PROSE names the file. libexec/aegis-secret explains the
# regcred in a paragraph that spells `secret-regcred-internal.enc.yaml`
# with the same words the defect would, and eight checks had to be
# corrected in one day for reading exactly that. This check runs the
# command instead of reading it, so a comment cannot reach it.
control_1() {
    printf '\n# note: secret-regcred-internal.enc.yaml is never invented here.\n' \
        >> "$AEGIS_ROOT/libexec/aegis-secret"
}

# control: the same trap in the generator. A YAML comment naming a file
# that nothing makes is documentation, not a declaration — only the
# `files:` list declares.
control_2() {
    printf '  # note: secret-registry-mirror-token.enc.yaml is NOT declared here.\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/secret-generator.yaml"
}

# control: a real new entry, of a kind the command already knows how to
# invent. Growing the generator is legitimate when the maker grows with
# it, and this check must not stand in the way of that.
control_3() {
    printf '  - secret-queue-credenciales.enc.yaml\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/secret-generator.yaml"
}

# THE GUARD THAT REFUSES TO ROTATE A COPIED CREDENTIAL, REMOVED.
#
# Without it control falls straight through to the copy: the same old
# material is written again and the command returns 0. `aegis secret
# rotate regcred-internal` then reports a rotation that did not happen
# — and the real one, at the registry's password, never happened
# either. A false success is the one outcome reading the output cannot
# catch, which is why it is worth a mutation of its own.
red_7() {
    python3 - "$AEGIS_ROOT/libexec/aegis-secret" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'\n[ ]{12}if rotate:\n[ ]{16}raise Error\((?:[^\n]*\n)+?[^\n]*remade from there\."\)\n',
           "\n", s, count=1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# control: the PROSE that argues the refusal. The reason a copied
# credential is rotated at its origin is explained right beside the
# code that enforces it, and explaining is not enforcing — this check
# exercises the command, so the paragraph must not satisfy it.
control_4() {
    python3 - "$AEGIS_ROOT/libexec/aegis-secret" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "        source = copy_source_for(name, path)\n"
note = ("        # note: a copied credential is rotated where it is derived —\n"
        "        # the registry's password — and the copies are remade from there.\n")
s = s.replace(anchor, note + anchor, 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}
