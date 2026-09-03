# scanner of check 184 — the application pipeline's anti-loop asks the
# REGISTRY, not only the source.
#
# Comments are dropped before anything is measured. In Groovy a `//`
# only opens a comment at the start of a line or after whitespace, so
# `https://` survives the filter — and it has to, because this stage's
# own paragraphs quote the URLs and the very words the defect is made
# of. A scan that read them would accuse the fix.
import re
import sys

raiz = sys.argv[1]
ruta = f"{raiz}/seed/platform/docs/protocols/templates/Jenkinsfile.app"

try:
    crudo = open(ruta, encoding="utf-8").read().splitlines()
except OSError as e:
    print(f"Jenkinsfile.app could not be read ({e}): this check measured nothing")
    print("__COUNT__ 0", file=sys.stderr)
    sys.exit(2)


def sin_prosa(l):
    return re.sub(r"(^|\s)//.*$", "", l)


codigo = [(n, sin_prosa(l)) for n, l in enumerate(crudo, 1)]

# ── the anti-loop's region ────────────────────────────────────────
ini = next((i for i, (_, l) in enumerate(codigo) if "stage('detect-change')" in l), None)
fin = next((i for i, (_, l) in enumerate(codigo)
            if ini is not None and i > ini and re.search(r"stage\('", l)), None)

malo = []
n_hechos = 0

if ini is None:
    print("Jenkinsfile.app has no detect-change stage: the subject of this check is gone, and "
          "with it every guarantee about what a build skips")
    print("__COUNT__ 0", file=sys.stderr)
    sys.exit(0)

region = codigo[ini:fin if fin is not None else len(codigo)]
texto = "\n".join(l for _, l in region)

def linea_de(patron):
    for j, (_, l) in enumerate(region):
        if re.search(patron, l):
            return j
    return None

# 1 · it asks the registry at all
n_hechos += 1
l_ver = linea_de(r"\bcosign\s+verify\b")
if l_ver is None:
    malo.append("the anti-loop never verifies anything against the registry: it can only ask "
                "whether the source changed, and on an installation born with an empty registry "
                "that answer is «no» for an image that does not exist here")

# 2 · about the digests the deploy stage itself wrote
n_hechos += 1
if "overlays" not in texto:
    malo.append("it does not read the overlay the deploy stage writes: verifying something other "
                "than the digests these manifests pin answers about another image")

# 3 · BEFORE deciding, not after
n_hechos += 1
l_skip = linea_de(r"env\.SKIP_BUILD\s*=")
if l_skip is None:
    malo.append("the stage no longer sets SKIP_BUILD: this check constrains that decision and "
                "can no longer see it")
elif l_ver is not None and l_ver > l_skip:
    malo.append("it verifies AFTER setting SKIP_BUILD: a precondition checked once the decision "
                "is taken is a comment, not a guard")

# 4 · and with the key, or it verifies nothing
n_hechos += 1
if l_ver is not None and not re.search(r"cosign\s+verify[^\n]*--key|--key[^\n]*\n[^\n]*cosign", texto):
    if "--key" not in texto:
        malo.append("the verification carries no --key: cosign then accepts anything, which reads "
                    "greener than not asking")

# 5 · the bootstrap window is survivable: before phase 80 there is no
#     key, and a pipeline that died there could never build the first
#     image of an installation.
n_hechos += 1
# It must TEST for the key, not merely mention it: the same path
# appears in the call that derives the public half, and a check that
# accepted any mention would go green over a stage with no guard at
# all — measured, the first version of this check did exactly that.
if not re.search(r"\[\s*-f\s+/cosign/keys/cosign\.key\s*\]", texto):
    malo.append("nothing guards the case where the signing key does not exist yet: before the "
                "supply chain is up there is no key, and a stage that fails closed there cannot "
                "build the very first image")

for l in malo:
    print(l)
print(f"__COUNT__ {n_hechos}", file=sys.stderr)
