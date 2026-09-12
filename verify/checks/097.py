"""Check 097 — the vocabulary a form is offered is the vocabulary the validator accepts.

`aegis org schema` exists so that the console can put a form in front of
somebody who does not write YAML. A form is a list of choices, and the
dangerous thing about a list of choices is that it can be RIGHT-LOOKING
and wrong: it offers five types when the platform speaks six, or it
offers a `puerto` field on a worker, or it stops offering a quota plan
somebody added to plans.yaml this morning.

None of those fail loudly. The form renders, the person fills it in, and
either the contract is rejected at the end with a message about a field
they were invited to fill, or something the platform supports simply
cannot be created and nothing anywhere says so.

So this check closes the loop, in both directions and behaviourally:

  · what `schema` says is REQUIRED is enough to pass `validate`
  · what `schema` says is FORBIDDEN really is rejected by `validate`
  · every option `schema` offers for `cuota` and `tamano` is accepted
  · a word `schema` does not offer is rejected

Both commands are run for real against a tree in tmpfs. Nothing is
imported and nothing is inspected: two programs are asked the same
question and their answers are compared.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]

# A plausible value for every field a contract may carry, so that a
# service can be assembled out of what `schema` says about it without
# this file holding an opinion about WHICH fields those are.
VALUE = {"repo": "git@github.com:owner/probando-uno.git",
         "puerto": 8080, "publico": "/", "usa": ["internet"]}

home = tempfile.mkdtemp(prefix="aegis-097-")
try:
    shutil.copytree(os.path.join(ROOT, "seed", "platform"), os.path.join(home, "platform"))
    env = {k: v for k, v in os.environ.items()
           if not (k.startswith("AEGIS_") or k == "PLATFORM_DIR")}
    env.update({"AEGIS_HOME": home, "AEGIS_ROOT": ROOT})
    AEGIS = os.path.join(ROOT, "bin", "aegis")

    def aegis(*args):
        return subprocess.run([AEGIS, *args], capture_output=True, text=True,
                              env=env, cwd=home)

    def accepts(contract):
        """Does the validator take this contract? Written to a file
        because that is how the command is used and how the console will
        use it."""
        import yaml as _y
        path = os.path.join(home, "probando.yaml")
        with open(path, "w", encoding="utf-8") as fh:
            _y.safe_dump(contract, fh, allow_unicode=True, sort_keys=False)
        r = aegis("org", "validate", path, "--json")
        return r.returncode == 0, (r.stderr or r.stdout or "").strip()[:160]

    r = aegis("org", "schema", "--json")
    try:
        doc = json.loads(r.stdout)
    except ValueError:
        print(f"`aegis org schema --json` returned no document (rc {r.returncode}): "
              f"{(r.stdout or r.stderr)[:160]!r}")
        sys.exit(0)

    by = {s.get("step", ""): s for s in doc.get("steps") or []}
    types = {k.split(":", 1)[1]: v for k, v in by.items() if k.startswith("tipo:")}
    quotas = (by.get("cuota") or {}).get("opciones") or []
    sizes = (by.get("tamano") or {}).get("opciones") or []
    findings = []

    if not types:
        print("the schema names no service type: a form built from this would offer "
              "nothing at all")
        sys.exit(0)
    if not quotas:
        findings.append("the schema offers no `cuota` plan: either plans.yaml could not "
                        "be read — in which case this is not an empty list, it is an "
                        "unmeasured one — or a form would ask for a plan and show none")

    quota = quotas[0] if quotas else "pequena"
    size = sizes[0] if sizes else None

    def build(kind, spec, extra=None):
        service = {"nombre": "uno", "tipo": kind}
        for field in spec.get("requiere") or []:
            service[field] = VALUE[field]
        service.update(extra or {})
        contract = {"version": doc_version, "organizacion": "probando",
                    "cuota": quota, "servicios": [service]}
        if service.get("publico"):
            contract["dominio"] = "probando.example.test"
        return contract

    doc_version = (by.get("contract") or {}).get("version", 1)

    offerable = [k for k, v in types.items() if v.get("disponible", True)]
    for kind, spec in sorted(types.items()):
        ok, why = accepts(build(kind, spec))
        # BOTH DIRECTIONS, and the second one is the quiet half. A type
        # the schema marks available and the validator refuses invites
        # somebody to ask for what the platform cannot give; a type it
        # marks unavailable and the validator accepts hides something
        # this platform does support.
        if spec.get("disponible", True) and not ok:
            findings.append(f"`{kind}` is offered as available and, filled in with exactly "
                            f"what the schema calls REQUIRED, the validator rejects it: "
                            f"{why} — a form built from this asks for everything it is "
                            f"told to and still fails")
        if not spec.get("disponible", True) and ok:
            findings.append(f"`{kind}` is marked NOT available and the validator accepts "
                            f"it: the form greys out a type this platform can deliver, and "
                            f"nobody finds out")
        # And every field the schema calls forbidden has to be refused.
        # Offering one is worse than not offering it: the person fills it
        # in and is told afterwards that it was never allowed.
        for field in spec.get("prohibe") or []:
            value = VALUE.get(field, size) if field != "tamano" else size
            if value is None:
                continue
            ok, _why = accepts(build(kind, spec, {field: value}))
            if ok:
                findings.append(f"the schema says `{kind}` forbids `{field}` and the "
                                f"validator accepts it: the two disagree about what a "
                                f"contract is, and the form is the one that will be "
                                f"believed")
        # The fields it offers are the ones it does not forbid: a field
        # in neither list is a field nobody decided about.
        campos = set(spec.get("campos") or [])
        overlap = campos & set(spec.get("prohibe") or [])
        if overlap:
            findings.append(f"`{kind}` offers {sorted(overlap)} in `campos` and forbids "
                            f"the same field: the form is told both things at once")
        if not campos >= set(spec.get("requiere") or []):
            missing = sorted(set(spec.get("requiere") or []) - campos)
            findings.append(f"`{kind}` requires {missing} and does not offer it: the form "
                            f"cannot produce a contract that validates")

    # Every plan on the list is a plan the validator knows, and a word
    # that is not on the list is not one. Without the second half the
    # check would pass against a schema that offered every word there is.
    if not offerable:
        print("the schema marks every service type as not offerable: a form built from "
              "this could not create an organization at all")
        print(f"SCOPE: {len(types)} type(s), none of them offerable")
        sys.exit(0)
    kind, spec = sorted((k, types[k]) for k in offerable)[0]
    for plan in quotas:
        c = build(kind, spec)
        c["cuota"] = plan
        ok, why = accepts(c)
        if not ok:
            findings.append(f"the schema offers the quota plan `{plan}` and the validator "
                            f"rejects it: {why}")
    c = build(kind, spec)
    c["cuota"] = "una-que-no-existe"
    ok, _ = accepts(c)
    if ok:
        findings.append("a quota plan the schema does not offer is accepted anyway: the "
                        "list is decoration, not the vocabulary")

    for label in sizes:
        with_size = {k: types[k] for k in offerable
                     if "tamano" not in (types[k].get("prohibe") or [])}
        if not with_size:
            break
        k2, s2 = sorted(with_size.items())[0]
        c = build(k2, s2, {"tamano": label})
        ok, why = accepts(c)
        if not ok:
            findings.append(f"the schema offers the size `{label}` for `{k2}` and the "
                            f"validator rejects it: {why}")

    for f in findings:
        print(f)
    print(f"SCOPE: {len(types)} type(s) ({len(offerable)} offerable here), {len(quotas)} "
          f"quota plan(s) and {len(sizes)} size(s) offered by the schema, each one put in "
          f"front of the validator")
finally:
    shutil.rmtree(home, ignore_errors=True)
