# title: generators KSOPS ↔ producers (A7 static)
# origin: verify-static.sh (v2) ══ 4
check() {
# THREE PRODUCERS, not one (fixed 2026-08-05, #48).
#
# This check was born assuming that the only producer of secrets are
# the init phases. That stopped being true when #39/#41 brought
# `platform/aegis secret`, which creates the secrets DERIVED FROM THE
# CONTRACTS. Under the old model, six perfectly produced files came out
# as "with no producer" — and a check that shouts about six healthy
# things is a check that stops being read, which means the ones that
# really are broken get lost in the noise.
#
#   1. init phases           make_enc_secret, literal mention
#   2. aegis secret     derived from orgs/*.yaml (mechanized: the
#                            material never goes through anybody's
#                            terminal)
#   3. MANUAL protocol       declared below, one by one, WITH the
#                            document that explains it — and the
#                            document is checked to exist, so that the
#                            category is not a rug
#
# Anything outside the three is a secret that nobody creates: on a new
# instance it stays encrypted with an age key that no longer exists,
# KSOPS cannot decrypt it and its App never syncs.
if python3 - "$AEGIS_ROOT" <<'EOF'
import os, re, sys, pathlib, yaml
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
# entries declared in the generators:
entries = {}   # basename -> dir of the generator
dup_failure = False
for g in P.rglob("secret-generator.yaml"):
    doc = yaml.safe_load(g.open())
    files = doc.get("files", [])
    # A DUPLICATE entry is not harmless: kustomize dies with «already
    # registered id» and the App does not generate. It happened on the
    # first firing of phase 85 (2026-08-20): the phase's guard did not
    # see an entry with a trailing comment and inserted it again. The
    # dict below collapsed the duplicate silently — that is why this
    # check did not see it coming and now hunts it down.
    for f in sorted({x for x in files if files.count(x) > 1}):
        print(f"FAIL DUPLICATE entry in generator: {g.parent.relative_to(P)}/{f}")
        dup_failure = True
    for f in files:
        entries[f] = str(g.parent.relative_to(P))
if dup_failure:
    sys.exit(1)
# producers: EVERY literal mention of a *.enc.yaml in the phases
# (covers make_enc_secret directly AND the ones that arrive through a
# loop/list — the extractor by exact signature lost those of phase 40):
phases = (root/"init"/"phases")
produced = {}  # basename -> phases that mention it
txt80 = (phases/"80-supply-chain.sh").read_text()
for ph in sorted(phases.glob("*.sh")):
    for m in re.finditer(r'([A-Za-z0-9_./$-]+\.enc\.yaml)', ph.read_text()):
        produced.setdefault(pathlib.Path(m.group(1)).name, []).append(ph.name)

# ── producer 2: the path derived from the contracts ───────────────
# The generator is ASKED instead of repeating its list here. The names
# are built (`secret-<base>-credenciales`, `secret-garage-<org>`), so a
# hand-written list would get out of sync as soon as somebody adds a
# type of secret — and it would fail on the side that does not warn:
# taking for good what does not exist.
by_contract = {}   # basename -> why
# WHERE THE GENERATOR LIVES — fixed on 2026-08-24.
#
# This block looked for `bin/aegis-org` INSIDE the seed and, if it was
# not there, skipped itself entirely with a reassuring message («seed
# with no organizations»). In v2 that made sense: the code travelled in
# the artifact. In v3 the code lives in the PRODUCT (02 §1) and the
# seed carries not one executable —check 134 demands it—, so the
# condition was impossible to satisfy and the SECOND CATEGORY OF
# PRODUCER had been dead since the move. Every secret derived from
# contracts would have come out «with no producer», and every secret
# that really had no producer would have been lost in that noise.
#
# It is the class that ordered the whole of v3 —a check measuring the
# wrong tree— hidden inside the `if` that made the error look like a
# legitimate absence. Now the generator is asked where it actually is,
# pointing it at the seed as if it were its instance: PLATFORM_DIR is
# set BEFORE the import because `org.py` resolves its root at load
# time.
gen = None
try:
    # An instrument leaves no trace on the subject. Importing the
    # generator writes __pycache__/ inside the tree this very verifier
    # is measuring, and on 2026-08-24 that turned check 105 RED: it saw
    # the banner «GENERADO POR aegis org» inside a .pyc and reported it
    # as a hand-written copy. The runner cleans the __pycache__ at
    # START-UP, not between checks — so whoever creates one halfway
    # through the run leaves it there for the next one.
    sys.dont_write_bytecode = True
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    os.environ["PLATFORM_DIR"] = str(P)
    sys.path.insert(0, str(root/"lib"))
    from aegis import org as gen
except Exception as e:
    print(f"  (could not load the product's generator: {e})")
try:
    if gen is None:
        raise StopIteration
    for c_path in sorted((P/"orgs").glob("*.y*ml")):
        c = yaml.safe_load(c_path.open()) or {}
        for s in gen.secrets_of(c):
            by_contract[s] = f"aegis-secret --todos orgs/{c_path.name}"
        # The deploy key with which ArgoCD reads the organization's
        # repo. It lives in the ArgoCD namespace but it belongs to THE
        # ORGANIZATION: it comes out of its `repo:`. The same --todos
        # pass creates it (#48).
        for app_name in gen.repos_of(c).values():
            by_contract[f"secret-{app_name}-repo.enc.yaml"] = \
                f"aegis-secret --todos orgs/{c_path.name}"
    for org in gen.orgs_with_bucket():
        by_contract[f"secret-garage-{org}.enc.yaml"] = "aegis-secret --reubicar"
    # platform-wide, with its own recipe in aegis-secret:
    by_contract["secret-garage-credentials.enc.yaml"] = "aegis-secret (platform recipe)"
except StopIteration:
    pass
except Exception as e:
    print(f"FAIL could not query the contract generator: {e}")
    sys.exit(1)

# ── producer 3: MANUAL protocols, declared one by one ─────────────
# A secret is accepted as hand-created ONLY if there is a document
# saying how. Without that demand this would be a list of exceptions,
# which is how a problem gets filed away instead of solved.
MANUAL = {
    # File SHARED between organizations: the tenant -> key map the
    # gateway consumes. Editing it automatically would mean that a
    # mistyped sign-up overwrites another organization's entry.
    "secret-ai-keys.enc.yaml": "docs/protocols/ai-tenant-key.md",
}
ok = True
# The document is demanded ONLY if the file is actually listed by some
# generator. The seed has no ai-system —nor any subsystem that grows
# later—, so demanding its protocol would be asking for documentation
# of something that does not exist yet.
for filename, doc in MANUAL.items():
    if filename in entries and not (P/doc).is_file():
        print(f"FAIL {filename} is declared manual but {doc} does not exist"); ok = False

for e, d in sorted(entries.items()):
    if e in produced or e in by_contract or e in MANUAL:
        continue
    print(f"FAIL entry with no producer: {d}/{e}"); ok = False
if by_contract:
    used = sorted(set(by_contract) & set(entries))
    print(f"  (derived from contracts: {len(used)} — {', '.join(used)})")
# entries added AT RUNTIME by their producing phase (same-commit
# pattern, temporal rule — check 18): the phase that produces the
# .enc.yaml MUST also add the line to the generator:
RUNTIME_ENTRY = {
    "secret-cosign-signing-key.enc.yaml":   "80-supply-chain.sh",
}
SPECIAL = set(RUNTIME_ENTRY) | {
    "tokens.enc.yaml",                     # consumer = tofu wrapper, not KSOPS
}
for p, phs in produced.items():
    if p not in entries and p not in SPECIAL:
        print(f"FAIL producer with no generator entry: {p} ({phs})"); ok = False
for e, phname in RUNTIME_ENTRY.items():
    t = (phases/phname).read_text()
    if e not in t or "secret-generator.yaml" not in t:
        print(f"FAIL {phname} does not add the runtime entry {e}"); ok = False
print(f"generators: {len(entries)} entries, {len(produced)} .enc.yaml referenced")
sys.exit(0 if ok else 1)
EOF
then pass "generators ↔ producers aligned"
else fail "generator/producer misaligned"; fi
}
