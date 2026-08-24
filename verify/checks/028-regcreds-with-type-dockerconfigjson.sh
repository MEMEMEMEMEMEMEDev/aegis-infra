# title: regcreds with type dockerconfigjson (run #9)
# origin: verify-static.sh (v2) ══ 28
check() {
# the kubelet IGNORES an Opaque Secret as an imagePullSecret ("no basic
# auth credentials") — EVERY make_enc_secret of a regcred must carry
# --type kubernetes.io/dockerconfigjson. Static: in phase 40, every
# invocation with .dockerconfigjson= must carry the --type:
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
ok = True; n = 0
for ph in (root/"init"/"phases").glob("*.sh"):
    # normalize line continuations (\<newline> → space) so that each
    # complete invocation is seen on one line (the previous multiline
    # regex did not capture them — the tooth revealed it):
    text = ph.read_text().replace("\\\n", " ")
    for m in re.finditer(r'make_enc_secret[^\n]*', text):
        call = m.group(0)
        if ".dockerconfigjson=" in call:
            n += 1
            if "--type kubernetes.io/dockerconfigjson" not in call:
                print(f"FAIL {ph.name}: regcred WITHOUT --type dockerconfigjson (the kubelet ignores it as a pull secret)")
                ok = False
print(f"regcred invocations verified: {n}")
sys.exit(0 if ok and n > 0 else 1)
EOF
then pass "every regcred is encrypted with type dockerconfigjson"
else fail "regcred without type dockerconfigjson (phase 60 bug, run #9)"; fi
}
