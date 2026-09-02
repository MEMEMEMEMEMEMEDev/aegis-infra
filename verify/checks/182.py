# scanner of check 182 — a task that cannot fit its own prompt is
# refused where the contract is written, not in front of a visitor.
#
# The rule is EXERCISED, never read: the product's own registry
# generator is imported and called over a toy platform, so a validation
# that was deleted, weakened or made unreachable is red on the first
# case. Reading the source for a `raise` would pass on a guard that
# nothing can reach.
#
# Three cases, and the third is the one that keeps the rule honest: a
# refusal whose suggested escape hatch does not work is a worse error
# than no refusal at all.
import importlib
import os
import pathlib
import shutil
import sys
import tempfile

import yaml

raiz = pathlib.Path(sys.argv[1])
semilla = raiz / "seed" / "platform"

for req in ("ai/tasks.yaml", "ai/routes.yaml"):
    if not (semilla / req).is_file():
        print(f"the seed does not ship {req}: this check cannot build a platform to exercise "
              f"the rule against")
        print("__COUNT__ 0", file=sys.stderr)
        sys.exit(3)

CHICO = "Sos una guia breve."
ENORME = "Sos una guia. " * 500          # 7000 characters


def escenario(tmp, prompt_txt, override=None):
    """A toy platform with ONE organization and ONE text task."""
    tmp = pathlib.Path(tmp)
    (tmp / "ai").mkdir(parents=True, exist_ok=True)
    (tmp / "k8s" / "base" / "ai-system").mkdir(parents=True, exist_ok=True)
    (tmp / "orgs").mkdir(parents=True, exist_ok=True)
    shutil.copy2(semilla / "ai" / "routes.yaml", tmp / "ai" / "routes.yaml")

    # Built by PARSING and re-dumping, never by cutting the text on the
    # word `tareas:`. The seed's own file explains the override section
    # in a comment that contains that word, so a split lands inside the
    # prose and the override is written into a comment: the first draft
    # of this scanner did exactly that and blamed the product.
    doc = yaml.safe_load((semilla / "ai" / "tasks.yaml").read_text(encoding="utf-8")) or {}
    doc["tareas"] = {"probe.chat.guia": dict(override)} if override else {}
    (tmp / "ai" / "tasks.yaml").write_text(yaml.safe_dump(doc, allow_unicode=True),
                                           encoding="utf-8")

    (tmp / "k8s" / "base" / "ai-system" / "prompts.yaml").write_text(
        "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: ai-prompts\ndata:\n"
        f"  guia.txt: |\n    {prompt_txt}\n", encoding="utf-8")

    (tmp / "orgs" / "probe.yaml").write_text(
        "organizacion: probe\n"
        "ai:\n  plan: basico\n"
        "  tareas:\n"
        "    - {nombre: chat.guia, capacidad: chat.rapido, prompt: guia.txt}\n",
        encoding="utf-8")
    return tmp


def correr(tmp):
    """Import the product fresh against this platform and generate."""
    os.environ["PLATFORM_DIR"] = str(tmp)
    sys.path.insert(0, str(raiz / "lib"))
    for m in [k for k in sys.modules if k.startswith("aegis")]:
        del sys.modules[m]
    org = importlib.import_module("aegis.org")
    return org, org.ai_registry_json()


malo = []
n = 0

# 1 · a prompt that fits: the rule must not stand in the way of the
#     ordinary case, or somebody will delete it.
n += 1
try:
    with tempfile.TemporaryDirectory(prefix="aegis-182a.") as t:
        correr(escenario(t, CHICO))
except Exception as e:                                   # noqa: BLE001
    malo.append(f"a task whose prompt easily fits its context ceiling was refused "
                f"({type(e).__name__}: {e}): the rule is stricter than the arithmetic it "
                f"claims, and a check that cries wolf gets removed")

# 2 · a prompt that cannot fit: this is the defect that reached
#     production and answered 400 in front of a visitor.
n += 1
try:
    with tempfile.TemporaryDirectory(prefix="aegis-182b.") as t:
        correr(escenario(t, ENORME))
except Exception as e:                                   # noqa: BLE001
    msg = str(e)
    # Naming the number is not enough: what the operator needs is WHERE
    # to change it. A refusal that says «too big» and stops sends a
    # person to read the generator's source at the worst moment.
    falta = [q for q in ("max_context_tokens", "tasks.yaml") if q not in msg]
    if falta:
        malo.append(f"the refusal does not tell the operator {' nor '.join(falta)}, so it says "
                    f"what is wrong without saying what to do: {msg[:160]}")
else:
    malo.append("a task whose prompt alone exceeds its whole context window was ACCEPTED: "
                "it cannot answer a single character, and nothing says so until a visitor "
                "gets a 400 on the public path")

# 3 · and the escape hatch the refusal names has to work. A message
#     that sends the operator to a knob that changes nothing is worse
#     than silence, because it spends their trust as well as their time.
n += 1
try:
    with tempfile.TemporaryDirectory(prefix="aegis-182c.") as t:
        correr(escenario(t, ENORME, override={"max_context_tokens": 4000}))
except Exception as e:                                   # noqa: BLE001
    malo.append(f"raising max_context_tokens in ai/tasks.yaml, which is exactly what the "
                f"refusal tells the operator to do, does not lift it ({type(e).__name__}: "
                f"{e}): the way out the product offers is not a way out")

for l in malo:
    print(l)
print(f"__COUNT__ {n}", file=sys.stderr)
