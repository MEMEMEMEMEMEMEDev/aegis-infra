# title: only ciphertext leaves the machine, and what comes back is checked before it is used
# origin: new in v3 — the off-site destination, 2026-08-29
check() {
# Until 2026-08-29 the bundles never left the house. The command said so
# at the end of every run —«the bundle stays on the SAME machine you
# want to survive»— and the newest bundle on the live instance was three
# days old and made by hand. Opening a road out of the machine closes
# that hole and opens four others, and all four are silent:
#
#   1. WHAT GOES OUT. The one door out is a PUT to somebody else's disk.
#      Wire it to the staging directory the capture builds before
#      encrypting —or to a `.tgz`, or to the dump of one database— and
#      the tenants' data leaves in the clear over a wire this platform
#      does not own. Nothing turns red: the upload succeeds. So the
#      guard is on the CONTENT, age's own header read from the first
#      bytes, and not on the file's name.
#
#   2. WHAT COMES BACK. A cut download does not fail loudly: `age -d`
#      says the file is corrupt, which on the day of a catastrophe reads
#      like «the key is wrong». What comes down is compared against its
#      manifest BEFORE it is handed to anybody, which is the same order
#      the restore of a bucket already follows with the pieces inside a
#      bundle.
#
#   3. WHAT THE MANIFEST SAYS. It travels in the clear beside the
#      ciphertext. The bundle's INTERNAL manifest knows database names,
#      table names and row counts; copying it out there would publish
#      the index of the safe next to the safe. The sidecar's keys are
#      therefore a closed set, measured here one by one.
#
#   4. THE CREDENTIAL. `/proc/PID/cmdline` is world-readable, so a key
#      that arrives as an argument is a key handed to every process on
#      the machine. Same class as check 075 (curl) and 154 (the ALTER
#      ROLE), applied to the third party this one talks to.
#
# And a fifth that belongs to the tofu: the destination bucket is
# private by ABSENCE — R2 serves nothing publicly until a custom domain
# or the managed r2.dev subdomain is attached, and neither resource is
# declared. There is no `public = false` to read, so the only way to
# watch that property is to watch for the two resource types that would
# break it.
#
# It reads the python with `ast` and not with grep, for the same reason
# check 154 does: a comment or a docstring may NARRATE the hole that was
# closed — that narration is worth more than the code — while the code
# may not reopen it.
D153=""
ROOT="$AEGIS_ROOT" python3 - <<'PY' || D153=" (the detail is above);"
import ast, os, pathlib, re, sys

root = pathlib.Path(os.environ["ROOT"])
target = root / "libexec" / "aegis-data"
src = target.read_text(errors="replace")
tree = ast.parse(src)
funcs = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
bad, measured = [], 0


def code_of(name):
    """The function WITHOUT its docstring: what it does, not what it tells."""
    fn = funcs.get(name)
    if fn is None:
        return ""
    body = fn.body[1:] if ast.get_docstring(fn) else fn.body
    return "\n".join(ast.unparse(x) for x in body)


def called_by(name):
    fn = funcs.get(name)
    if fn is None:
        return set()
    return {c.func.id for c in ast.walk(fn)
            if isinstance(c, ast.Call) and isinstance(c.func, ast.Name)}


def want(condition, complaint):
    global measured
    measured += 1
    if not condition:
        bad.append(f"    {complaint}")


# ── 1. only ciphertext goes out, and the guard is BEFORE the write ──
UP = [f for f in ("remote_push", "remote_push_bundle") if f in funcs]
want(UP, "there is no function that sends a bundle out: the road out of "
         "the machine disappeared, and with it everything below")
for fn in UP:
    body = funcs[fn]
    stmts = body.body[1:] if ast.get_docstring(body) else body.body
    guard = magic = put = None
    for i, st in enumerate(stmts):
        text = ast.unparse(st)
        if magic is None and "AGE_MAGIC" in text:
            magic = i
        if put is None and re.search(r"""['"]PUT['"]""", text):
            put = i
    want(magic is not None,
         f"{fn}() does not check age's header: it would send out whatever "
         f"it is handed, and a plaintext dump uploaded successfully is the "
         f"one failure here that nothing turns red")
    want(magic is not None and put is not None and magic < put,
         f"{fn}() checks age's header AFTER the first PUT (or not at all): "
         f"a guard that runs once the bytes are on somebody else's disk "
         f"guards nothing")
# And the guard reads the FILE, not its name. `.age` is a convention and
# conventions are renamed; the header is what the format guarantees.
want("AGE_MAGIC" in src and re.search(r'AGE_MAGIC\s*=\s*b"age-encryption', src),
     "AGE_MAGIC is not age's real header: the guard would be comparing "
     "against something that is not the format's own mark")
for fn in UP:
    want(".endswith" not in code_of(fn) or "AGE_MAGIC" in code_of(fn),
         f"{fn}() decides by the file's NAME: a suffix is a convention and "
         f"the header is the format")

# ── 2. what comes down is verified before it is written ─────────────
want("remote_fetch" in funcs,
     "there is no function that brings a bundle back from the destination")
fetch = funcs.get("remote_fetch")
if fetch is not None:
    stmts = fetch.body[1:] if ast.get_docstring(fetch) else fetch.body
    cmp_at = write_at = None
    for i, st in enumerate(stmts):
        text = ast.unparse(st)
        if cmp_at is None and "sha256" in text and ("man" in text or "Compare" in text):
            cmp_at = i
        if write_at is None and "O_CREAT" in text:
            write_at = i
    want(cmp_at is not None,
         "remote_fetch() does not compare what came down against its "
         "manifest: a cut transfer is not a rare event over a household "
         "connection, and a truncated bundle reads as «the key is wrong»")
    want(write_at is None or (cmp_at is not None and cmp_at < write_at),
         "remote_fetch() writes the file BEFORE checking it against the "
         "manifest: the same order the restore of a bucket was fixed for "
         "on 2026-08-29, reintroduced one layer up")
    want("manifiesto" in ast.unparse(fetch),
         "remote_fetch() does not fetch the sidecar: with nothing to "
         "compare against, «verified» would mean «it downloaded»")
# and the restore path goes through it, instead of decrypting whatever arrived
main_src = code_of("main")
want("remote_fetch" in main_src,
     "no path of the command brings a bundle down through remote_fetch(): "
     "restoring from the destination would hand `age -d` an unchecked file")

# ── 3. the sidecar publishes the ciphertext's fingerprint and nothing else
SIDECAR_ALLOWED = {"version", "archivo", "organizacion", "bytes", "sha256", "subido"}
side = funcs.get("remote_sidecar")
want(side is not None, "there is no sidecar: a bundle at the destination "
                       "that cannot be checked before restoring is a bundle "
                       "nobody can trust on the day it is needed")
if side is not None:
    keys = set()
    for n in ast.walk(side):
        if isinstance(n, ast.Dict):
            keys |= {k.value for k in n.keys
                     if isinstance(k, ast.Constant) and isinstance(k.value, str)}
    extra = sorted(keys - SIDECAR_ALLOWED)
    want(not extra,
         f"the sidecar carries {extra}, which is not the ciphertext's "
         f"fingerprint: it travels IN THE CLEAR beside the bundle, and the "
         f"internal manifest knows database names, table names and row "
         f"counts — publishing that is publishing the index of the safe "
         f"next to the safe")
    want("open_bundle" not in called_by("remote_sidecar")
         and "MANIFIESTO" not in code_of("remote_sidecar"),
         "the sidecar reads the bundle's INTERNAL manifest: whatever it "
         "copies from there ends up unencrypted at a third party")

# ── 4. the credential does not travel in argv, and there is ONE signer
adopt = funcs.get("remote_adopt")
want(adopt is not None, "no command adopts the destination's credential")
if adopt is not None:
    want(len(adopt.args.args) == 1
         and "file" in adopt.args.args[0].arg,
         "remote_adopt() takes the pair as a value instead of a file: argv "
         "is world-readable in /proc, so a key handed on the command line "
         "is a key handed to every process on this machine")
    want("open(" in code_of("remote_adopt"),
         "remote_adopt() does not read the pair from a file")
    # And it is PROVED against the destination before it is stored. A
    # shape check would pass a key that opens nothing.
    order = code_of("remote_adopt")
    want(order.find("remote_s3") != -1
         and order.find("remote_s3") < order.find("store_write"),
         "remote_adopt() stores the pair without asking the destination "
         "whether it opens: a credential nobody proved, sitting in the "
         "store, is an off-site copy that exists on paper and fails on "
         "the day of the catastrophe")
# ONE signer for the two S3 this platform speaks. A second one is a
# second place where a canonical request can be got subtly wrong, and
# the symptom is a 403 that does not say which of the two is at fault.
signers = [n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)
           and "AWS4-HMAC-SHA256" in ast.unparse(n)]
want(signers == ["s3"],
     f"there is more than one SigV4 signer in this file ({signers}): the "
     f"far destination speaks the same protocol as the near one, and two "
     f"implementations is two ways to be wrong")
want("s3" in called_by("remote_s3"),
     "remote_s3() does not go through the one signer")

# ── 5. the destination bucket is private by ABSENCE ─────────────────
TF = [root / "seed/platform/tofu/envs/data-r2",
      root / "seed/platform/tofu/modules/r2-bucket"]
tf_text = ""
for d in TF:
    want(d.is_dir(), f"{d.relative_to(root)} does not exist: there is no "
                     f"declared destination for the backups")
    if d.is_dir():
        for f in sorted(d.glob("*.tf")):
            # WITHOUT comments. The first version of this check read the
            # raw text, and deleting the retention rule went green
            # because the paragraph ABOVE it still said its name — the
            # instrument was reading the explanation instead of the
            # thing explained. Its own tooth found it.
            tf_text += "\n".join(
                l for l in f.read_text(errors="replace").splitlines()
                if not l.lstrip().startswith("#"))
PUBLIC = ("cloudflare_r2_custom_domain", "cloudflare_r2_managed_domain")
for r in PUBLIC:
    hit = re.search(rf'resource\s+"{r}"', tf_text)
    want(not hit,
         f"the tofu of the destination declares {r}: that is what makes an "
         f"R2 bucket public, and a public bucket of backups is every bundle "
         f"this platform ever wrote, offered for offline cracking")
want("cloudflare_r2_bucket" in tf_text,
     "the tofu of the destination creates no bucket")
want("delete_objects_transition" in tf_text,
     "the destination has no retention rule: the bundles accumulate for "
     "ever on a shelf that is 10 GB, and the far side stops accepting "
     "them at exactly the moment nobody is looking")
want("abort_multipart_uploads_transition" in tf_text,
     "the retention does not abort interrupted uploads: their parts COUNT "
     "towards the stored bytes and no listing shows them, which is the "
     "shape of a free tier exhausted by something invisible")

# ── 6. the env no phase names still has its variables answered ──────
#
# Check 019 crosses the tofu variables with no default against the
# wrapper's TF_VARs — but it only walks the envs a PHASE names, and this
# one is applied by hand on purpose (the bucket has to exist before the
# credential that writes into it is worth anything, and phase 15 runs
# long before there is data). So the same hole is closed from the other
# side: every variable of this env that the wrapper does not inject has
# to be exported by the protocol, in writing, or the operator meets an
# interactive tofu prompt on the day they are recovering a machine.
proto = root / "seed/platform/docs/protocols/backups.md"
want(proto.is_file(), "there is no backups protocol: the off-site copy is "
                      "the half of the recovery that is not code")
if proto.is_file() and tf_text:
    wrapper = (root / "seed/platform/tofu/tofu-apply.sh").read_text()
    injected = set(re.findall(r"^\s*export TF_VAR_([a-z0-9_]+)=", wrapper, re.M))
    text = proto.read_text(errors="replace")
    env_tf = ""
    for f in sorted((root / "seed/platform/tofu/envs/data-r2").glob("*.tf")):
        env_tf += f.read_text(errors="replace")
    for m in re.finditer(r'variable\s+"([a-z0-9_]+)"\s*\{(.*?)\n\}', env_tf, re.S):
        name, body = m.group(1), m.group(2)
        if re.search(r"^\s*default\s*=", body, re.M) or name in injected:
            continue
        want(f"TF_VAR_{name}" in text,
             f"envs/data-r2 declares '{name}' with no default, the wrapper "
             f"does not inject it, and the protocol never says to export "
             f"TF_VAR_{name}: tofu would stop asking for it interactively, "
             f"in the middle of a recovery")

print(f"    {measured} properties measured over the road out of the machine",
      file=sys.stderr)
for m in bad:
    print(m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D153" ]]; then fail "the road out of the machine:$D153"
else pass "only age ciphertext leaves, the guard runs before the first PUT, what comes back is compared against its manifest before it is written, the sidecar carries the fingerprint and nothing from inside, the credential never touches argv and is proved before it is stored, and the destination bucket has no resource that would make it public"; fi
}
