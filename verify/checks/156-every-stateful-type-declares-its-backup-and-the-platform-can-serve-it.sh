# title: every stateful type of the catalogue declares its backup, and the platform can render it, credential it and fence it
# origin: new in v3 — 2026-08-29, the day `redis` and `mongodb` joined `postgres` and «who backs this up» stopped having one obvious answer
check() {
# THE HOLE THIS CLOSES. While `postgres` was the only type the platform
# provided, «what holds state here» and «what aegis data captures» were
# the same sentence, so neither had to be written down. With three types
# they are not: one of them holds a COPY of somebody else's data and
# must NOT be captured, and one of them cannot be captured yet at all.
# The moment that stops being written down, a type gets added with a
# volume and no dump — and nothing anywhere turns red, because a backup
# that captures less than it should is indistinguishable from one that
# captures everything, right up until somebody needs it.
#
# So the rule is: A TYPE WITH STATE OWES ITS BACKUP, and there are
# exactly two ways of paying. `method: dump` says how, with the commands
# `aegis data` runs. `method: none` says why not. Silence is not a third
# way, and this check is what makes it not be one.
#
# WHAT IS MEASURED, and the order is the order the mechanism runs:
#
#   1. THE CATALOGUE HOLDS TOGETHER. Every type declares a backup with a
#      legal method; a dumped one names its `dump:` and its `restore:`;
#      an undumped one names a reason somebody can read. And the two
#      halves agree: with `disco:` it has to be dumped (a volume nobody
#      captures is the false promise itself) and without a dump it may
#      not have one.
#
#   2. THE COMMANDS ARE HONEST. `kubectl exec` as the transport, because
#      a tenant namespace cannot get a dump out over the network; and no
#      credential in argv, because /proc/<pid>/cmdline is readable by
#      anything in the pod. This is the ONE thing about the backup that
#      can be measured from here without demanding code that does not
#      exist yet: `libexec/aegis-data` implements this contract, and it
#      is out of this check's scope on purpose.
#
#   3. THE LABEL AND THE BACKUP SAY THE SAME THING. `aegis data` finds
#      what to capture by `aegis.dev/component=datos`. So a dumped type
#      that is not labelled `datos` is a type nothing will ever look at,
#      and an undumped type labelled `datos` is a type something WILL
#      look at and find nothing worth having. The word in the catalogue
#      and the promise in the catalogue are one fact; here they are
#      compared.
#
#   4. THE PLATFORM CAN ACTUALLY SERVE THE TYPE: the generator knows it
#      (TYPES, PROVIDED, USES, its renderer, its resources), it RENDERS
#      a Service and a StatefulSet, the volume follows `disco:`, the
#      credential is the organization's SOPS-encrypted Secret and never
#      a literal, and `usa:` yields a NetworkPolicy pointing at THAT
#      type's label and THAT type's port.
#
#   5. AND A TYPE WHOSE IMAGE NOBODY MEASURED IS REFUSED, naming the
#      commands that measure it. That refusal is the whole reason a type
#      may be declared before it can be deployed; without it the seed
#      would need an invented digest, which is the one thing the file
#      that pins by digest may not contain.
#
# WHAT IS DERIVED AND WHAT IS TYPED:
#   derived from services.yaml   which types exist and what each one
#                                promises. Nothing here enumerates them:
#                                a fourth type is measured the day it is
#                                written, without editing this file.
#   derived from lib/aegis/org.py  PROVIDED, RENDER_PROVIDED, USES and
#                                the resource table
#   typed here                   the shape of the two legal answers, and
#                                the credential-bearing flags. Both are
#                                the rule itself, and a rule read out of
#                                the file under test measures nothing.
D156=""
python3 - "$AEGIS_ROOT" "$P" <<'PY' || D156=" (see the detail above)"
import copy, os, pathlib, re, shutil, sys, tempfile

root, P = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

# A SCRATCH instance, never the seed: this check RENDERS, and rendering
# reads orgs/ off disk. An instrument leaves no trace on its subject.
tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-156-"))
(tmp / "orgs").mkdir()
os.environ["PLATFORM_DIR"] = str(tmp)
sys.path.insert(0, str(root / "lib"))
try:
    import yaml
    from aegis import org as gen
except Exception as e:                                   # noqa: BLE001
    print(f"    the product's generator does not load: {e}", file=sys.stderr)
    sys.exit(1)

bad = []
cat = yaml.safe_load((P / "services.yaml").read_text(encoding="utf-8")) or {}
types = cat.get("tipos") or {}
if not types:
    print("    services.yaml declares no `tipos:` — there is nothing to measure",
          file=sys.stderr)
    sys.exit(1)

# The flags that put a credential where /proc publishes it. `--config`
# and the `_FILE` variants are the way out and are NOT here: the point
# is not to forbid authentication, it is to forbid argv.
IN_ARGV = (
    (r"--password[ =]", "--password puts the credential in argv"),
    (r"\bPGPASSWORD=", "PGPASSWORD= on the command line is argv too"),
    (r"redis-cli[^\n]*\s-a\s", "redis-cli -a publishes the password"),
    (r"\b\w+://[^\s/]*:[^\s/@]+@", "a connection URI carries the credential in argv"),
)

# ── 1-3. the catalogue's own promise ────────────────────────────────
for kind in sorted(types):
    try:
        block = gen.provided_type(cat, kind)
    except gen.Invalid as e:
        bad.append(f"tipos.{kind} does not hold together: {str(e).splitlines()[0]}")
        continue
    except Exception as e:                               # noqa: BLE001
        bad.append(f"tipos.{kind}: the catalogue reader BROKE instead of "
                   f"refusing ({type(e).__name__}: {e}). A traceback names "
                   f"neither the file nor what is missing from it")
        continue
    backup = block["backup"]
    method = backup["method"]
    if method == "dump":
        for field in ("dump", "restore"):
            text = str(backup[field])
            if "kubectl exec" not in text:
                bad.append(f"tipos.{kind}.backup.{field} does not go through "
                           f"`kubectl exec`: a tenant namespace's egress is closed "
                           f"except for DNS, so a pod can dump its data and cannot "
                           f"get it OUT over the network")
            for pattern, why in IN_ARGV:
                if re.search(pattern, text):
                    bad.append(f"tipos.{kind}.backup.{field}: {why}. "
                               f"/proc/<pid>/cmdline is readable by anything in "
                               f"that pod")
        if block["component"] != "datos":
            bad.append(f"tipos.{kind} is dumped and is labelled "
                       f"`{block['component']}`, not `datos`: what captures it "
                       f"selects by that label, so this type promises a backup "
                       f"nothing will ever come looking for")
    else:
        if len(" ".join(str(backup["reason"]).split())) < 40:
            bad.append(f"tipos.{kind}.backup.reason is one line long: saying a "
                       f"thing is not backed up is legitimate, saying it without "
                       f"saying why is how an oversight passes for a decision")
        if block["component"] == "datos":
            bad.append(f"tipos.{kind} is NOT backed up and carries "
                       f"`component: datos`, which is the label the backup "
                       f"selects: it would be looked for, found, and found empty")

# ── 1b. and the REFUSALS are the rule, not this file's opinion ──────
#
# Everything above asks the catalogue reader whether the seed is
# coherent, and a reader that stopped asking anything would answer yes.
# So the rule is exercised against counter-examples built HERE, over a
# copy: the same shape check 149 uses for a half-written plans.yaml, and
# for the same reason — a validator that rejects nothing comes out green
# against a check that only reads the file it validates.
SOUND = next((k for k in sorted(types)
              if (types[k] or {}).get("backup", {}).get("method") == "dump"), None)
if SOUND is None:
    bad.append("no type in the catalogue declares `method: dump`: there is no "
               "sound entry to build the counter-examples from")
else:
    def mutated(**changes):
        # The base is a SOUND entry, with its digest already measured:
        # the counter-examples are about the backup and about the shape
        # of the reference, and starting from a type that is still
        # waiting for its digest would mean every one of them is refused
        # for the pending block instead of for what it is testing.
        c2 = copy.deepcopy(cat)
        block = c2["tipos"][SOUND]
        block.pop("pending", None)
        block["digest"] = "sha256:" + "0123456789abcdef" * 4
        for k, v in changes.items():
            if v is None:
                block.pop(k, None)
            else:
                block[k] = v
        return c2

    CROSSINGS = (
        ("no `backup:` at all", dict(backup=None)),
        ("a backup method nobody implements", dict(backup={"method": "magic"})),
        ("dumped, and no `restore:` written down",
         dict(backup={"method": "dump", "dump": "kubectl exec ..."})),
        ("dumped, and nothing to dump FROM (no `disco:`)", dict(disco=None)),
        ("not backed up, and a volume all the same",
         dict(backup={"method": "none",
                      "reason": "a long enough sentence to pass for a reason"})),
        # An EMPTY reason and not a short one: how long a reason has to
        # be to count is this check's judgement (the seed is measured
        # against it above) and not the generator's, which has no
        # business ruling on prose. What the generator owes is refusing
        # the field that is there and says nothing.
        ("not backed up and not saying why",
         dict(disco=None, backup={"method": "none", "reason": "   "})),
        ("a digest AND a pending block", dict(pending={"commands": ["x"],
                                                       "reason": "y"})),
        ("a digest that is not a digest", dict(digest="sha256:nope")),
    )
    for what, changes in CROSSINGS:
        try:
            gen.provided_type(mutated(**changes), SOUND)
        except gen.Invalid:
            continue
        except Exception as e:                           # noqa: BLE001
            bad.append(f"a catalogue with {what} does not give an Invalid: it "
                       f"BREAKS with {type(e).__name__}({e}). A traceback names "
                       f"neither the file nor what is wrong with it")
            continue
        bad.append(f"a catalogue entry with {what} was ACCEPTED: the rule that "
                   f"a type with state answers for its own backup is not being "
                   f"applied, and the next type written this way is deployed "
                   f"with nothing looking at it")

# ── 4. the platform can serve every type it declares ────────────────
missing = sorted(set(types) - set(gen.PROVIDED))
if missing:
    bad.append(f"services.yaml declares {', '.join(missing)} and the generator's "
               f"table does not: a contract naming it would be charged a `tamano` "
               f"it may not have and asked for a `repo` it does not need")
orphan = sorted(set(gen.PROVIDED) - set(types))
if orphan:
    bad.append(f"the generator provides {', '.join(orphan)} and services.yaml does "
               f"not declare it: the contract validates and the render dies on a "
               f"file that says nothing about the type")
for kind in sorted(set(types) & set(gen.PROVIDED)):
    for name, table in (("TYPES", gen.TYPES), ("USES", gen.USES),
                        ("RENDER_PROVIDED", gen.RENDER_PROVIDED)):
        if kind not in table:
            bad.append(f"`{kind}` is provided and is not in {name}: "
                       + ("no contract can name it" if name == "TYPES" else
                          "nothing may declare it depends on it, so the "
                          "NetworkPolicy that authorises the traffic is never "
                          "written" if name == "USES" else
                          "the contract validates and nothing renders it"))

# ── 5. the refusal, before anything is rendered ─────────────────────
pending = [k for k in sorted(types) if not (types[k] or {}).get("digest")]
for kind in pending:
    try:
        gen.image_of(cat, kind)
        bad.append(f"`{kind}` has no measured digest and the generator handed back "
                   f"an image anyway: the reference would be built out of a tag or "
                   f"out of the ORIGIN's digest, and neither is what the internal "
                   f"registry serves — an ImagePullBackOff with a manifest that "
                   f"reads correctly")
    except gen.Invalid as e:
        msg = str(e)
        for cmd in (types[kind]["pending"]["commands"] or []):
            if cmd not in msg:
                bad.append(f"the refusal for `{kind}` does not name `{cmd}`: a "
                           f"refusal that does not carry the way out makes the "
                           f"next person go and find out what this file already "
                           f"knew")
    except Exception as e:                               # noqa: BLE001
        bad.append(f"`{kind}` without a digest BREAKS the generator "
                   f"({type(e).__name__}: {e}) instead of being refused")

# ── and now the render, over a COPY with every digest measured ──────
#
# The stand-in digest is what a live registry would have answered. It
# goes into a COPY: filling it into the seed would be the check editing
# its own subject, and leaving those types out of the render would mean
# the only ones exercised here are the ones that happen to be deployable
# today — which is the opposite of what this file is for.
measured = copy.deepcopy(cat)
STANDIN = "sha256:" + "0123456789abcdef" * 4
for kind in pending:
    measured["tipos"][kind].pop("pending", None)
    measured["tipos"][kind]["digest"] = STANDIN
(tmp / "services.yaml").write_text(
    yaml.safe_dump(measured, sort_keys=False, allow_unicode=True), encoding="utf-8")
shutil.copy(P / "plans.yaml", tmp / "plans.yaml")
plans = yaml.safe_load((tmp / "plans.yaml").read_text(encoding="utf-8"))

kinds = sorted(set(types) & set(gen.PROVIDED))
servicios = [{"nombre": f"s{i}", "tipo": k} for i, k in enumerate(kinds, 1)]
servicios.append({"nombre": "api", "tipo": "http", "puerto": 8080,
                  "usa": sorted(kinds)})
contract = {"version": 1, "organizacion": "sustrato",
            "cuota": max(plans["cuota"], key=lambda q: gen._mem(
                plans["cuota"][q]["requests.memory"])),
            "repo": "git@github.com:owner/repo.git", "servicios": servicios}
try:
    c = gen.validate(copy.deepcopy(contract), plans)
    datos = [d for d in yaml.safe_load_all(gen.render_data(c, "sha256:0"))
             if isinstance(d, dict)]
    netpol = [d for d in yaml.safe_load_all(gen.render_netpol(c, "sha256:0"))
              if isinstance(d, dict)]
    secrets = gen.secrets_of(c)
    kust = yaml.safe_load(gen.render_kustomization(c, "sha256:0", secrets))
except Exception as e:                                   # noqa: BLE001
    datos = netpol = secrets = []
    kust = {}
    bad.append(f"a contract with one service of every provided type does not "
               f"render: {type(e).__name__}({e})")

by_kind = {}
for kind, s in zip(kinds, servicios):
    objs = [d for d in datos
            if (d.get("metadata") or {}).get("name") == s["nombre"]]
    by_kind[kind] = objs

if datos and "datos.yaml" not in (kust.get("resources") or []):
    bad.append("the kustomization does not list datos.yaml: every object this "
               "check just measured would be rendered into a file kustomize "
               "never reads, and nothing would be deployed")

for kind in kinds:
    t = types[kind]
    objs = by_kind[kind]
    kinds_got = sorted(d["kind"] for d in objs)
    if kinds_got != ["Service", "StatefulSet"]:
        bad.append(f"`{kind}` renders {kinds_got or 'nothing'} and not a Service "
                   f"plus a StatefulSet: a provided type with no headless Service "
                   f"has no stable name to be reached by")
        continue
    svc = next(d for d in objs if d["kind"] == "Service")
    sts = next(d for d in objs if d["kind"] == "StatefulSet")
    pod = sts["spec"]["template"]["spec"]
    label = (sts["spec"]["template"]["metadata"].get("labels") or {})
    if label.get("aegis.dev/component") != t["component"]:
        bad.append(f"the pods of `{kind}` carry component "
                   f"{label.get('aegis.dev/component')!r} and the catalogue says "
                   f"{t['component']!r}: the label decides who backs it up and who "
                   f"may reach it, and two answers is one of them being wrong")
    ports = [p.get("port") for p in svc["spec"]["ports"]]
    if ports != [t["puerto"]]:
        bad.append(f"the Service of `{kind}` publishes {ports} and the catalogue "
                   f"says {t['puerto']}")
    claims = sts["spec"].get("volumeClaimTemplates") or []
    if t.get("disco") and not claims:
        bad.append(f"`{kind}` declares `disco: {t['disco']}` and renders no "
                   f"volumeClaimTemplate: it would be dumped from a disk that is "
                   f"an emptyDir, so every capture would be of what was written "
                   f"since the last restart")
    if not t.get("disco") and claims:
        bad.append(f"`{kind}` declares no `disco` and renders a "
                   f"volumeClaimTemplate: it is not backed up, so that volume "
                   f"would be the one thing here that survives and that nobody "
                   f"captures")
    # the credential: from the organization's Secret, never a literal
    blob = yaml.safe_dump(sts)
    if f"{sts['metadata']['name']}-credenciales" not in blob:
        bad.append(f"`{kind}` renders no reference to its "
                   f"`<service>-credenciales` Secret: either it runs with no "
                   f"credential at all, or the credential is written into the "
                   f"manifest, and both are worse than the other one")
    for pattern, why in IN_ARGV:
        for container in pod.get("containers") or []:
            for argv in (container.get("command") or []) + (container.get("args") or []):
                if re.search(pattern, str(argv)):
                    bad.append(f"the container of `{kind}`: {why}")

for kind in kinds:
    want = f"allow-api-a-{kind}"
    pol = [d for d in netpol if (d.get("metadata") or {}).get("name") == want]
    if not pol:
        bad.append(f"a service declaring `usa: [{kind}]` gets no {want}: what is "
                   f"not declared is blocked, so the day the blanket "
                   f"intra-namespace rule closes, this dependency stops working "
                   f"and nothing written down says it existed")
        continue
    egress = ((pol[0]["spec"].get("egress") or [{}])[0])
    sel = ((egress.get("to") or [{}])[0].get("podSelector") or {}).get("matchLabels") or {}
    got_ports = [p.get("port") for p in egress.get("ports") or []]
    if sel.get("aegis.dev/component") != types[kind]["component"]:
        bad.append(f"{want} selects {sel!r} and `{kind}` is labelled "
                   f"{types[kind]['component']!r}: the policy authorises traffic "
                   f"to somebody else's pods, or to nobody's")
    if got_ports != [types[kind]["puerto"]]:
        bad.append(f"{want} opens {got_ports} and `{kind}` listens on "
                   f"{types[kind]['puerto']}")

for kind, s in zip(kinds, servicios):
    want = f"secret-{s['nombre']}-credenciales.enc.yaml"
    if want not in secrets:
        bad.append(f"a service of type `{kind}` gets no {want}: the generator "
                   f"references a Secret the secret-generator never lists, so the "
                   f"pod waits forever for a Secret nobody creates")

shutil.rmtree(tmp, ignore_errors=True)
dumped = [k for k in sorted(types) if (types[k].get("backup") or {}).get("method") == "dump"]
print(f"    {len(types)} provided types · {len(dumped)} dumped "
      f"({', '.join(dumped)}) · {len(pending)} still without a measured digest "
      f"· render, credential and NetworkPolicy exercised for each",
      file=sys.stderr)
for m in bad:
    print(f"    {m}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D156" ]]; then
    fail "a type with state does not answer for its own backup, or the platform cannot serve it$D156"
else
    pass "every provided type says how it is backed up or why it is not, its label agrees with that answer, no credential travels in argv, and each one renders with its volume, its Secret and its NetworkPolicy — or is refused naming the command that measures its image"
fi
}
