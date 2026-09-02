# scanner of check 174 — «already built» is a claim about a registry,
# never about a file.
#
# The subject is a shell phase, so there is no AST to lean on the way
# 175 leans on python's. What there IS, and what this file does before
# anything else, is DROP THE PROSE. This house documents every decision
# beside the code that implements it, so the file that holds a defect
# almost always holds the paragraph explaining it too, in the same
# words. A grep over the raw text accuses the fix — eight times in one
# day is what taught the house to stop, and the tooth of this check
# carries that comment as a control precisely so a regression here is
# caught by the instrument rather than by a person.
#
# The scan is structural: functions are read as blocks, the build loop
# is read as a region, and the question is one of ORDER — what the
# phase does before it decides not to work.
import re
import sys

raiz = sys.argv[1]
ruta = f"{raiz}/init/phases/87-ai.sh"

try:
    crudo = open(ruta, encoding="utf-8").read().splitlines()
except OSError as e:
    print(f"87-ai.sh could not be read ({e}): this check measured nothing")
    sys.exit(2)

# Prose out. A full-line `#` is a comment in shell and also inside the
# python heredocs this phase embeds, which is the only text that could
# be mistaken for code here. Line numbers are kept so ordering below
# talks about the real file.
codigo = [(n, l) for n, l in enumerate(crudo, 1)
          if not re.match(r"^\s*#", l)]

# ── the functions, as blocks ──────────────────────────────────────
funcs = {}
nombre = None
cuerpo = []
for _, l in codigo:
    if nombre is None:
        # The brace may carry a trailing comment naming the arguments —
        # `_f() {   # <a> <b>` is this house's own signature style.
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{\s*(#.*)?$", l)
        if m:
            nombre, cuerpo = m.group(1), []
    elif re.match(r"^\}\s*$", l):
        funcs[nombre] = "\n".join(cuerpo)
        nombre = None
    else:
        cuerpo.append(l)

# ── the build loop, as a region ───────────────────────────────────
ini = fin = None
for i, (n, l) in enumerate(codigo):
    if re.search(r"^for\s+\w+\s+in\s+\$AI_IMAGES_NEEDED\s*;\s*do", l):
        ini = i
    elif ini is not None and re.match(r"^done\s*$", l):
        fin = i
        break

malo = []
n_hechos = 0

if ini is None or fin is None:
    print("87-ai.sh no longer has a loop over $AI_IMAGES_NEEDED: the subject of this "
          "check is gone, and with it every guarantee about what gets skipped")
    print("__COUNT__ 0", file=sys.stderr)
    sys.exit(0)

region = codigo[ini:fin]
corte = next((j for j, (_, l) in enumerate(region)
              if re.search(r"^\s*continue\s*$", l)), None)
antes = region[:corte] if corte is not None else region
texto_antes = "\n".join(l for _, l in antes)

if corte is None:
    malo.append("the loop never skips anything: this check exists to constrain the skip, "
                "and with no skip it can no longer tell a guarded one from a blind one")

# 1 · somebody here asks the REGISTRY, with the key, over this instance's own
verificadoras = [f for f, c in funcs.items()
                 if re.search(r"\bcosign\s+verify\b", c)]
n_hechos += 1
if not verificadoras:
    malo.append("nothing in 87-ai.sh verifies a signature: the phase can only ask whether a "
                "row was written, and a row is a decision somebody recorded, not an image "
                "that exists")
else:
    for f in verificadoras:
        c = funcs[f]
        if "--key" not in c:
            malo.append(f"{f}() calls cosign verify with no --key: a verification with no key "
                        f"accepts any signature, which is the same as not verifying")
        if "REGISTRY_CLUSTER_IP" not in c:
            malo.append(f"{f}() does not name this installation's registry: the whole defect is "
                        f"that a pin travels between installations while the image does not, so "
                        f"asking some other registry answers the wrong question")

# 2 · and it is asked BEFORE the phase decides not to work
n_hechos += 1
llamada = [f for f in verificadoras if re.search(rf"\b{re.escape(f)}\b", texto_antes)]
if verificadoras and not llamada:
    malo.append("the skip is not guarded by the signature check: 87-ai.sh knows how to ask the "
                "registry and does not ask before deciding the image is already built — a green "
                "phase that installed nothing, and the symptom surfaces later as a pod that "
                "never pulls or an admission denial")

# 3 · the digest it verifies is the one the row pins, not one it invented
n_hechos += 1
lector = [f for f, c in funcs.items() if "kustomization.yaml" in c and "digest" in c]
m_cap = re.search(r"(\w+)=\"\$\(\s*(" + "|".join(re.escape(f) for f in lector) + r")\b",
                  texto_antes) if lector else None
if not lector:
    malo.append("no function reads the pinned digest out of the kustomization: without the "
                "digest there is nothing to verify, and «is something signed in there» is a "
                "weaker question than «is THIS signed in there»")
elif not m_cap:
    malo.append("the loop never captures the pinned digest before deciding: reading the row "
                "and asking the registry have to be the same sentence, or they are about two "
                "different images")
elif llamada:
    var = m_cap.group(1)
    linea_v = next((l for _, l in antes if re.search(rf"\b{re.escape(llamada[0])}\b", l)), "")
    if not re.search(r"\$\{?" + re.escape(var) + r"\b", linea_v):
        malo.append(f"the verification does not receive ${var}, the digest the row pins: it "
                    f"verifies something else, and the answer is about another image")

# 4 · with the credentials that make the question answerable at all
n_hechos += 1
antes_del_bucle = "\n".join(l for _, l in codigo[:ini])
if verificadoras and "registry_creds" not in antes_del_bucle:
    malo.append("registry_creds is never materialised before the loop: cosign would be asking "
                "an authenticated registry with no credentials, so the verification could never "
                "succeed and every re-run would rebuild from scratch — hours, on every run")

for l in malo:
    print(l)
print(f"__COUNT__ {n_hechos}", file=sys.stderr)
