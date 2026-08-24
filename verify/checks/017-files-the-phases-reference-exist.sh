# title: files the phases reference EXIST (bug class 4)
# origin: verify-static.sh (v2) ══ 17
check() {
# ansible's requirements.txt was referenced and did NOT exist — phase
# 20 died on the VM. Same class as check 5 (App paths): every static
# reference of the phases to files of the artifact is verified here
# (ansible/* relative to platform/ — phase 20 does a cd — and the
# $AEGIS_V2_ROOT/init/* paths):
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
ok = True; n = 0
for ph in sorted((root/"init"/"phases").glob("*.sh")):
    t = ph.read_text()
    for m in re.finditer(r'\bansible/[A-Za-z0-9_./-]+\.(?:yml|yaml|txt|ini|j2)\b', t):
        n += 1
        if not (P/m.group(0)).is_file():
            print(f"FAIL {ph.name}: nonexistent reference platform/{m.group(0)}")
            ok = False
    # $AEGIS_V2_ROOT was the name in v2. When the variable was renamed,
    # this expression stopped finding ANYTHING and half the check was
    # left dead in silence — green for having no subjects. Its tooth
    # revealed it: a nonexistent reference was slipped in and it did
    # not flinch. Now it also covers lib/ and libexec/, which in v2
    # lived under init/.
    for m in re.finditer(r'\$AEGIS_ROOT/((?:init|lib|libexec)/[A-Za-z0-9_./-]+\.(?:py|sh|tpl))\b', t):
        n += 1
        if not (root/m.group(1)).is_file():
            print(f"FAIL {ph.name}: nonexistent reference {m.group(1)}")
            ok = False
print(f"static references of the phases verified: {n}")
sys.exit(0 if ok else 1)
EOF
then pass "every static reference of the phases exists"
else fail "a phase references a nonexistent file"; fi
}
