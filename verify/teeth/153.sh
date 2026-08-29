# teeth for check 153 (the road out of the machine)
# generated on 2026-08-29 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
DATA="libexec/aegis-data"
TF="seed/platform/tofu/modules/r2-bucket/main.tf"
PROTO="seed/platform/docs/protocols/backups.md"

_py() {   # _py <file> <old-heredoc> <new-heredoc>  (exact, once)
    python3 - "$AEGIS_ROOT/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(p).read()
assert t.count(old) == 1, f"the anchor appears {t.count(old)} times"
open(p, "w").write(t.replace(old, new, 1))
PY
}

# THE REAL REGRESSION. The one door out of the machine stops checking
# WHAT it is handed. Wire it to the staging directory the capture builds
# before encrypting and the tenants' data leaves in the clear over a
# wire this platform does not own — and the upload succeeds, so nothing
# turns red.
red_1() {
    _py "$DATA" '    with open(bundle, "rb") as f:
        head = f.read(len(AGE_MAGIC))
    if head != AGE_MAGIC:
        die(f"{os.path.basename(bundle)} is NOT an age-encrypted file (its "
            f"first bytes are not age'"'"'s header) and NOTHING was uploaded. "
            f"Only ciphertext leaves this machine: what goes to a third "
            f"party'"'"'s disk is protected by the instance'"'"'s key or it does "
            f"not go")
' ''
}

# The same guard kept but run AFTER the bytes are already on somebody
# else'"'"'s disk. It looks like a check and it protects nothing.
red_2() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
guard = '    with open(bundle, "rb") as f:\n        if f.read(len(AGE_MAGIC)) != AGE_MAGIC:\n            die(f"{os.path.basename(bundle)} is NOT an age-encrypted file and "\n                f"NOTHING was uploaded: only ciphertext leaves this machine")\n'
put = '    st, body, _ = remote_s3("PUT", key, body=data, timeout=600, cfg=cfg, pair=pair)\n    if st not in (200, 201):\n        die(f"{key} did NOT leave the machine: HTTP {st} ({body[:160]!r})")\n'
put_late = '    st, body, _ = remote_s3("PUT", key, body=data, timeout=600, cfg=cfg, pair=pair)\n    if st not in (200, 201):\n        die(f"{key} did NOT leave the machine: HTTP {st} ({body[:160]!r})")\n    with open(bundle, "rb") as f:\n        if f.read(len(AGE_MAGIC)) != AGE_MAGIC:\n            die("not an age file")\n'
assert t.count(guard) == 1 and t.count(put) == 1
t = t.replace(guard, "", 1)
open(p, "w").write(t.replace(put, put_late, 1))
PY
}

# What comes down gets written first and checked afterwards. A cut
# transfer is not rare over a household connection, and a truncated .age
# reads as «the key is wrong» on the worst possible day.
red_3() {
    _py "$DATA" '    got = hashlib.sha256(data).hexdigest()
    if len(data) != man.get("bytes") or got != man.get("sha256"):' '    with open(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as early:
        early.write(data)
    got = hashlib.sha256(data).hexdigest()
    if len(data) != man.get("bytes") or got != man.get("sha256"):'
}

# The sidecar starts copying what is INSIDE the bundle. It travels in
# the clear beside the ciphertext, so this publishes the index of the
# safe next to the safe.
red_4() {
    _py "$DATA" '        "subido": datetime.datetime.now(datetime.timezone.utc)' '        "piezas": "postgres+bucket",
        "subido": datetime.datetime.now(datetime.timezone.utc)'
}

# The credential goes back to travelling in argv, which /proc publishes
# to every process on this machine. Same class as check 075 and 154.
red_5() {
    _py "$DATA" 'def remote_adopt(credentials_file):' 'def remote_adopt(key_id_value):'
}

# The pair is stored without asking the destination whether it opens.
# A credential nobody proved is an off-site copy that exists on paper.
red_6() {
    _py "$DATA" '    cfg = remote_config()
    st, body, _ = remote_s3("GET", "", query={"list-type": "2", "max-keys": "1"},
                            cfg=cfg, pair=(key_id, key_secret))' '    cfg = remote_config()
    store_write(REMOTE_ID_NAME, key_id.encode())
    store_write(REMOTE_KEY_NAME, key_secret.encode())
    st, body, _ = remote_s3("GET", "", query={"list-type": "2", "max-keys": "1"},
                            cfg=cfg, pair=(key_id, key_secret))'
}

# The bucket of backups is made public. There is no `public = false` to
# turn off: attaching a domain IS the switch, and every bundle this
# platform ever wrote goes up for offline cracking.
red_7() {
    cat >> "$AEGIS_ROOT/$TF" <<'EOF'

resource "cloudflare_r2_custom_domain" "publico" {
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.this.name
  domain      = "respaldos.example.invalid"
  enabled     = true
  zone_id     = "0000"
}
EOF
}

# The retention disappears: the shelf grows for ever, and the far side
# stops accepting bundles at exactly the moment nobody is looking.
red_8() {
    _py "$TF" '    delete_objects_transition = {' '    borrado_desactivado = {'
}

# A second SigV4 signer. Two implementations are two ways to get a
# canonical request subtly wrong, and the symptom is a 403 that does not
# say which of the two is at fault.
red_9() {
    _py "$DATA" 'def s3_credential(ns):' 'def s3_remoto(method, host, path, ak, sk):
    """a second signer, for the far side"""
    sts = f"AWS4-HMAC-SHA256\n{path}"
    return hmac.new(sk.encode(), sts.encode(), hashlib.sha256).hexdigest()


def s3_credential(ns):'
}

# The protocol stops saying to export the variable the wrapper does not
# inject. Check 019 does not walk this env (no phase names it), so the
# operator meets an interactive tofu prompt in the middle of a recovery.
red_10() {
    _py "$PROTO" 'export TF_VAR_backups_bucket="$(aegis data remote bucket)"' 'echo "type the bucket name when tofu asks"'
}

# control: narrating the hole is not reopening it. A docstring that
# describes the plaintext leak this guards against must stay green.
control_1() {
    _py "$DATA" 'def remote_sidecar(bundle, org):
    """The fingerprint of the CIPHERTEXT, and nothing else.' 'def remote_sidecar(bundle, org):
    """The fingerprint of the CIPHERTEXT, and nothing else.

    Before this existed the piezas of the internal MANIFIESTO.json were
    copied out here in the clear, which published the index of the safe.'
}

# control: a suffix check ADDED BESIDE the header check is belt and
# braces, not a regression. The check must not confuse the two.
control_2() {
    _py "$DATA" '    cfg = remote_config()
    pair = remote_credential()
    data = open(bundle, "rb").read()
    key = remote_key(org, bundle)' '    if not bundle.endswith(".age"):
        die("the name does not end in .age either")
    cfg = remote_config()
    pair = remote_credential()
    data = open(bundle, "rb").read()
    key = remote_key(org, bundle)'
}
