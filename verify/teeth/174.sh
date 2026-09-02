# teeth of check 174 — a build is skipped because the registry holds
# the image, not because a file says it was built.

# THE STATE THE ARTIFACT WAS IN until 2026-09-02: the skip read the row
# and nothing else. On a new instance every row the seed ships is
# pinned and the registry is empty, so the phase declared every AI
# image built and installed none of them.
red_1() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'^(\s*)if _ai_image_signed_here [^\n]*\n', r'\1if true; then\n', s,
           count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# verified, but with no key: cosign then accepts any signature, which
# is the same as not verifying and reads greener than not trying.
red_2() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'^\s*--key "\$PLATFORM_DIR[^\n]*\n', '', s, count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# the digest of the row is read and then NOT handed to the verification:
# something is asked about some image, and the answer is about another.
red_3() {
    sed -i 's/_ai_image_signed_here "$_img" "$_dig"/_ai_image_signed_here "$_img" "sha256:deadbeef"/' \
        "$AEGIS_ROOT/init/phases/87-ai.sh"
}

# no credentials materialised before the loop: the verification can
# never succeed, so idempotence dies and every re-run pays the builds
# again — hours, silently, and it looks like the phase being thorough.
red_4() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'^registry_creds "\$REGISTRY_HOST_INTERNAL"[^\n]*\n', '', s,
           count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# control: the PROSE that explains this very decision — same words, same
# file, right beside the code. Reading it as the implementation is the
# error this house made eight times in one day, and this control is the
# instrument that catches the ninth.
control_1() {
    cat >> "$AEGIS_ROOT/init/phases/87-ai.sh" <<'EOF'

# note: the skip must not trust the row alone. `cosign verify --key
# cosign.pub` against $REGISTRY_CLUSTER_IP is what says the image is
# really here; registry_creds puts the credentials in tmpfs first.
EOF
}

# control: another buildable image in the table is the shape working,
# not a defect — the guarantee is about the skip, not about the roster.
control_2() {
    sed -i 's/aegis-engine-cpu) _job=engine-cpu   ; _to=3600  ; _gib=10 ;;/aegis-engine-cpu) _job=engine-cpu   ; _to=3600  ; _gib=10 ;;\n        aegis-engine-xpu) _job=engine-xpu   ; _to=3600  ; _gib=9 ;;/' \
        "$AEGIS_ROOT/init/phases/87-ai.sh"
}
