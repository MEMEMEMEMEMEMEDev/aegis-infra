"""Check 201 — an edit changes what you changed, and nothing else.

MEASURED ON 2026-09-13, by opening the edit screen over a real
contract. The form shows six fields per service. A contract carries
more: `usa`, the `almacenamiento` block, the whole `ai` section with its
list of tasks. The first version of this screen REBUILT the contract
from the form, and every one of those disappeared.

Nothing refused it. `usa` is optional, so the validator had nothing to
say; the plan showed a tidy diff of the files it would rewrite; the page
said it saved. Somebody adding a database to their shop would have
silently deleted the four capabilities its API declares, and found out
when the NetworkPolicies stopped letting it reach any of them.

The shape that fixes it is «the current contract is the floor»: the
form's fields are applied ON TOP of what is there. The shape that proves
it is this check, which edits a contract carrying everything the screen
does not show and demands that the ONLY difference is the thing that was
asked for.

And the three refusals, because an edit that may do anything is not an
edit: it may not drop a service, it may not rename the organization, and
it may not create one.
"""
import copy
import importlib.machinery
import importlib.util
import os
import shutil
import sys
import tempfile

ROOT = sys.argv[1]
SERVER = os.path.join(ROOT, "libexec", "aegis-console")
sys.path.insert(0, os.path.join(ROOT, "lib"))

try:
    from aegis import console
except ImportError:
    print("SCOPE: there is no renderer: this check has no subject")
    sys.exit(0)
if not hasattr(console, "contract_from_edit"):
    print("SCOPE: the console does not edit yet: this check has no subject")
    sys.exit(0)

import yaml                                           # noqa: E402

# A contract that carries, on purpose, every kind of thing the form does
# NOT show: a `usa` list, a storage block, and an ai section with a task
# inside it.
CURRENT = yaml.safe_load("""
version: 1
organizacion: tienda
dominio: tienda.example.test
cuota: mediana
almacenamiento:
  bucket: true
ai:
  plan: basico
  tareas:
  - {nombre: chat.ayuda, capacidad: chat.rapido, prompt: ayuda.txt}
servicios:
- {nombre: web, tipo: estatico, publico: /, repo: 'git@github.com:owner/tienda-web.git'}
- nombre: api
  tipo: http
  puerto: 8080
  publico: /api
  repo: 'git@github.com:owner/tienda-api.git'
  tamano: mediano
  usa: [bucket, ai, internet]
""")

SCHEMA = {"steps": [{"step": "contract", "state": "already", "version": 1}]}
findings = []


def fields(**over):
    f = console.fields_of_contract(CURRENT)
    f.update(over)
    return f


# ── 1. the edit adds a database and touches nothing else ─────────────
added = fields(**{"servicio2.nombre": "datos", "servicio2.tipo": "postgres",
                  "servicio2.puerto": "", "servicio2.publico": "",
                  "servicio2.repo": "", "servicio2.tamano": ""})
after, text, refused = console.contract_from_edit(added, SCHEMA, CURRENT)
if refused:
    findings.append(f"adding one service to a contract is refused: {refused}")
else:
    want = copy.deepcopy(CURRENT)
    want["servicios"] = list(want["servicios"]) + [{"nombre": "datos",
                                                    "tipo": "postgres"}]
    if after != want:
        # Say WHICH key went missing: a diff of two dicts in a message
        # is unreadable, and the useful half is the name of what was
        # dropped.
        lost = [k for k in CURRENT if k not in after or after[k] != CURRENT[k]
                and k != "servicios"]
        svc_lost = []
        for a, b in zip(CURRENT.get("servicios") or [], after.get("servicios") or []):
            svc_lost += [f"{a.get('nombre')}.{k}" for k in a
                         if k not in b or b[k] != a[k]]
        findings.append(
            f"adding a service changed other things too — top level {lost or 'none'}, "
            f"services {svc_lost or 'none'}. The form shows six fields per service and "
            f"a contract carries more; anything it does not show has to come out the "
            f"other side exactly as it went in, because nothing would refuse its loss")

# ── 1b. a form with fewer rows than the contract has services ────────
# The rows are grown to fit, so this is the belt to that brace: a body
# that reaches only the first service must still come back with both.
# Losing the tail would be caught by the refusal below — which is the
# safe failure, not the right one: it would make the screen unusable
# for every organization with more services than the form drew.
short = {k: v for k, v in fields().items() if not k.startswith("servicio1.")}
after2, _t, refused = console.contract_from_edit(short, SCHEMA, CURRENT)
if refused:
    findings.append(f"an edit whose form did not reach every service is refused: "
                    f"{refused} — the services the form did not touch have to be "
                    f"carried over, or this screen cannot edit an organization with "
                    f"more services than it drew rows")
elif (after2 or {}).get("servicios") != CURRENT["servicios"]:
    findings.append("an edit whose form did not reach every service came back with the "
                    "services changed: what the form did not touch has to survive "
                    "untouched")

# ── 2. the three refusals ────────────────────────────────────────────
dropped = fields()
for key in ("nombre", "tipo", "publico", "repo"):
    dropped[f"servicio0.{key}"] = ""
_c, _t, refused = console.contract_from_edit(dropped, SCHEMA, CURRENT)
if not refused:
    findings.append("an edit that leaves a declared service out is allowed: a form with "
                    "fewer rows than the contract has services deletes the rest, "
                    "silently, at the moment somebody pressed «save»")

renamed = fields(organizacion="otra")
_c, _t, refused = console.contract_from_edit(renamed, SCHEMA, CURRENT)
if not refused:
    findings.append("an edit may rename the organization: that writes a SECOND contract "
                    "and leaves the first where it is — two files, one namespace, and a "
                    "screen that says it saved")

# And the honest half, or a function that refused everything would pass
# every line above.
_c, text_ok, refused = console.contract_from_edit(fields(cuota="grande"), SCHEMA, CURRENT)
if refused:
    findings.append(f"changing the quota of an organization is refused: {refused} — an "
                    f"edit that may do nothing is not an edit")

# ── 3. the two doors stay distinct ───────────────────────────────────
if not os.path.isfile(SERVER):
    findings.append("there is no console to check the write of")
else:
    env_before = dict(os.environ)
    home = tempfile.mkdtemp(prefix="aegis-201-")
    try:
        shutil.copytree(os.path.join(ROOT, "seed", "platform"),
                        os.path.join(home, "platform"))
        for k in [k for k in os.environ if k.startswith("AEGIS_") or k == "PLATFORM_DIR"]:
            del os.environ[k]
        os.environ["AEGIS_HOME"] = home
        os.environ["AEGIS_ROOT"] = ROOT
        loader = importlib.machinery.SourceFileLoader("aegis_console_201", SERVER)
        spec = importlib.util.spec_from_loader(loader.name, loader)
        mod = importlib.util.module_from_spec(spec)
        loader.exec_module(mod)

        if not hasattr(mod, "replace_contract"):
            findings.append("the console has no importable overwrite: the rule about "
                            "which door writes over a contract cannot be exercised")
        else:
            simple = ("version: 1\norganizacion: tienda\ndominio: tienda.example.test\n"
                      "cuota: pequena\nservicios:\n  - nombre: web\n    tipo: estatico\n"
                      "    publico: /\n    repo: git@github.com:owner/tienda-web.git\n")
            # The EDIT door may not create. A create arriving disguised
            # as an edit skips every question the create screen asks.
            target, why = mod.replace_contract(simple)
            if target or not why:
                findings.append("the edit door created an organization that did not "
                                "exist: a create arrived disguised as an edit")
            path = os.path.join(home, "platform", "orgs", "tienda.yaml")
            if os.path.exists(path):
                findings.append("a refused edit wrote the file anyway")
            # Now create it properly, and check the other direction.
            mod.write_contract(simple)
            if not os.path.exists(path):
                findings.append("the create door did not write a valid contract")
            else:
                target, why = mod.write_contract(simple)
                if target or not why:
                    findings.append("the CREATE door wrote over a contract that exists: "
                                    "an edit arrived disguised as a create, and the two "
                                    "doors are the same door")
                changed = simple.replace("cuota: pequena", "cuota: mediana")
                target, why = mod.replace_contract(changed)
                if why:
                    findings.append(f"the edit door refuses a legitimate change: {why}")
                elif open(path, encoding="utf-8").read() != changed:
                    findings.append("the edit door reported success and the file on disk "
                                    "is not what it was given")
                # And no second copy of a tenant's contract anywhere.
                strays = [f for _d, _s, fs in os.walk(os.path.join(home, "platform", "orgs"))
                          for f in fs if f.startswith("tienda") and f != "tienda.yaml"]
                if strays:
                    findings.append(f"the edit left {strays} beside the contract: git "
                                    f"already has the old one, and a second place a "
                                    f"tenant's contract lives is one too many")
    finally:
        shutil.rmtree(home, ignore_errors=True)
        os.environ.clear()
        os.environ.update(env_before)

for f in findings:
    print(f)
print(f"SCOPE: a contract carrying `usa`, a storage block and an ai task edited through "
      f"the six fields the form shows; 3 refusals and 2 doors exercised")
