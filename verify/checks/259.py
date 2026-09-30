"""Check 259 — `aegis app new --template` finds the templates wherever the product is installed.

MEASURED 2026-09-28 on Rob's instance (his H-07) and again 2026-09-30 on
alpha-arch: `aegis app new portafolio --template static` died with «I cannot
find the templates: ~/aegis/seed/templates does not exist … This
clone looks loose». _templates_dir() derived the product as
dirname(PLATFORM_DIR), true only in the development layout (the instance
nested inside the product). Every install the product documents puts them
side by side (~/aegis-infra, ~/aegis).

The check LOADS libexec/aegis-app and asks it, in three layouts: side by
side (the documented install), nested (the house), and no product at all
(an error that names what it looked for, never a traceback).
"""
import importlib.machinery
import importlib.util
import os
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
APP = os.path.join(ROOT, "libexec", "aegis-app")
findings = []


def ask(env):
    saved = {k: os.environ.get(k) for k in env}
    os.environ.update(env)
    try:
        name = f"aegis_app_{len(env)}_{abs(hash(tuple(sorted(env.items()))))}"
        loader = importlib.machinery.SourceFileLoader(name, APP)
        spec = importlib.util.spec_from_loader(name, loader)
        mod = importlib.util.module_from_spec(spec)
        loader.exec_module(mod)
        try:
            return "ok", mod._templates_dir()
        except mod.Error as e:
            return "error", str(e)
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


with tempfile.TemporaryDirectory() as tmp:
    # the documented install: product and instance side by side
    os.makedirs(os.path.join(tmp, "aegis", "platform"))
    kind, got = ask({"AEGIS_ROOT": ROOT, "PLATFORM_DIR": os.path.join(tmp, "aegis", "platform")})
    if kind != "ok" or os.path.realpath(got) != os.path.realpath(os.path.join(ROOT, "seed", "templates")):
        findings.append(f"product and instance side by side (~/aegis-infra, ~/aegis): {kind} — {got.splitlines()[0][:140]}")
    # the house: the instance nested inside a product checkout
    nested = os.path.join(tmp, "house")
    os.makedirs(os.path.join(nested, "seed", "templates", "static"))
    os.makedirs(os.path.join(nested, "platform"))
    kind, got = ask({"AEGIS_ROOT": os.path.join(tmp, "no-such-product"), "PLATFORM_DIR": os.path.join(nested, "platform")})
    if kind != "ok" or os.path.realpath(got) != os.path.realpath(os.path.join(nested, "seed", "templates")):
        findings.append(f"the instance nested inside the product: {kind} — {got.splitlines()[0][:140]}")
    # nowhere: an error that names the places it looked at
    kind, got = ask({"AEGIS_ROOT": os.path.join(tmp, "no-such-product"), "PLATFORM_DIR": os.path.join(tmp, "aegis", "platform")})
    if kind != "error":
        findings.append(f"with no product anywhere _templates_dir answered {got!r} instead of saying where it looked")
    elif "no-such-product" not in got:
        findings.append("with no product anywhere the error does not name the product path it looked at")

print("SCOPE: libexec/aegis-app loaded and asked in 3 layouts (side by side, nested, none)")
for x in findings:
    print(x)
