"""Check 202 — an account nobody could ask is not an empty account.

The product's thesis, applied to the one reading that comes from
outside this machine. `aegis repos` asks GitHub what the account has;
GitHub is behind a network, a token and a rate limit, and any of the
three can be the reason an answer does not arrive.

A screen that drew zero repositories there would tell somebody their
account is empty. They would go looking for what happened to their
work. And every number on that screen would be true of the document in
front of them — the failure this repository filed on 2026-09-10.

So the real command is run three ways against a stub `gh`, and the
three have to come out different:

  · GitHub silent            rc 2, and NOT ONE repository drawn
  · an account with nothing  rc 0, and it says so
  · an account with things   rc 0, and each one carries what claims it

And the claim has to be right in both directions: a repository a
contract names is reported with the organization and service that name
it, and one nothing names comes back as an OPTION rather than a
finding. Painting an unclaimed repository red would teach somebody to
ignore the colour on the one screen where the colour has to mean
something.
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
CMD = os.path.join(ROOT, "libexec", "aegis-repos")

if not os.path.isfile(CMD):
    print("SCOPE: there is no `aegis repos`: this check has no subject")
    sys.exit(0)

# The command shells out to `gh`, so a `gh` that answers from a script
# is the only way to put three different accounts in front of it inside
# `aegis verify` — no network, no token, nothing contacted.
STUB = r'''#!/usr/bin/env python3
import json, os, sys
scene = json.load(open(os.environ["STUB_GH"]))
if scene.get("silent"):
    sys.stderr.write("gh: To get started with GitHub CLI, please run: gh auth login\n")
    sys.exit(4)
# TWO PAGES, always, and the second one carries the tail. `gh api
# graphql --paginate` prints one document per page with nothing between
# them, and a reader that took only the first would lose everything past
# the hundredth repository without a word.
repos = scene.get("repos", [])
half = (len(repos) + 1) // 2
for chunk in (repos[:half], repos[half:]):
    print(json.dumps({"data": {"viewer": {"repositories": {
        "pageInfo": {"hasNextPage": False, "endCursor": None},
        "nodes": chunk}}}}))
'''

REPOS = [
    {"name": "tienda-web", "primaryLanguage": {"name": "TypeScript", "color": "#3178c6"},
     "isPrivate": True, "pushedAt": "2026-09-13T05:00:00Z", "url": "u"},
    {"name": "tienda-todo", "primaryLanguage": {"name": "Astro", "color": "#ff5a03"},
     "isPrivate": True, "pushedAt": "2026-09-12T05:00:00Z", "url": "u"},
    {"name": "algo-mio", "primaryLanguage": {"name": "Rust", "color": "#dea584"},
     "isPrivate": True, "pushedAt": "2026-09-11T05:00:00Z", "url": "u"},
    {"name": "sin-lenguaje", "primaryLanguage": None,
     "isPrivate": False, "pushedAt": "2026-09-10T05:00:00Z", "url": "u"},
]

home = tempfile.mkdtemp(prefix="aegis-202-")
try:
    shutil.copytree(os.path.join(ROOT, "seed", "platform"), os.path.join(home, "platform"))
    # A contract that claims one repository for ONE service, and another
    # for TWO — a front and a bff out of the same tree, which is how
    # this instance really runs one of its organizations.
    with open(os.path.join(home, "platform", "orgs", "tienda.yaml"), "w",
              encoding="utf-8") as fh:
        fh.write("version: 1\norganizacion: tienda\ndominio: tienda.example.test\n"
                 "cuota: pequena\nrepo: git@github.com:owner/tienda-todo.git\n"
                 "servicios:\n"
                 "  - nombre: web\n    tipo: estatico\n    publico: /\n"
                 "    repo: git@github.com:owner/tienda-web.git\n"
                 "  - {nombre: front, tipo: estatico, publico: /app}\n"
                 "  - {nombre: bff, tipo: http, puerto: 8080}\n")
    os.mkdir(os.path.join(home, "bin"))
    stub = os.path.join(home, "bin", "gh")
    with open(stub, "w", encoding="utf-8") as fh:
        fh.write(STUB)
    os.chmod(stub, os.stat(stub).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    def run(scene):
        path = os.path.join(home, "scene.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(scene, fh)
        env = {k: v for k, v in os.environ.items()
               if not (k.startswith("AEGIS_") or k == "PLATFORM_DIR")}
        env.update({"AEGIS_HOME": home, "AEGIS_ROOT": ROOT, "STUB_GH": path,
                    "PATH": os.path.join(home, "bin") + os.pathsep + env.get("PATH", "")})
        r = subprocess.run([os.path.join(ROOT, "bin", "aegis"), "repos", "list", "--json"],
                           capture_output=True, text=True, env=env, cwd=home)
        try:
            return r.returncode, json.loads(r.stdout)
        except ValueError:
            return r.returncode, None

    findings = []

    # ── 1. silent ────────────────────────────────────────────────────
    rc, blind = run({"silent": True})
    if blind is None:
        findings.append(f"with GitHub silent the command returned no document (rc {rc}): "
                        f"the screen has nothing to draw and no reason")
    else:
        drawn = [s for s in blind.get("steps") or [] if s.get("step", "").startswith("repo:")]
        if blind.get("rc") != 2:
            findings.append(f"a silent GitHub reports rc {blind.get('rc')}, not 2: «I could "
                            f"not ask» is being filed as a measurement")
        if not any(s.get("state") == "not-evaluable" for s in blind.get("steps") or []):
            findings.append("a silent GitHub produces no `not-evaluable` step")
        if drawn:
            findings.append(f"a silent GitHub still draws {len(drawn)} repositories")

    # ── 2. an account with nothing in it ─────────────────────────────
    rc, empty = run({"repos": []})
    if empty is None:
        findings.append(f"an empty account returned no document (rc {rc})")
    else:
        if empty.get("rc") != 0:
            findings.append(f"an account with no repositories reports rc {empty.get('rc')}: "
                            f"having none is not a failure, and it is not «I could not ask» "
                            f"either — those are three different answers")
        total = [s for s in empty.get("steps") or [] if s.get("step") == "repos"]
        if not total or total[0].get("total") != 0:
            findings.append("an empty account does not say out loud that it is empty: the "
                            "screen cannot tell it apart from the silent one")

    # ── 3. an account with things in it ──────────────────────────────
    rc, full = run({"repos": REPOS})
    if full is None:
        findings.append(f"a populated account returned no document (rc {rc})")
    else:
        by = {s.get("step", "").split(":", 1)[-1]: s for s in full.get("steps") or []
              if s.get("step", "").startswith("repo:")}
        if len(by) != len(REPOS):
            findings.append(f"{len(by)} of {len(REPOS)} repositories reached the document: "
                            f"one that is not on the screen cannot be taken on")
        web = by.get("tienda-web") or {}
        if [(u.get("organizacion"), u.get("servicio")) for u in web.get("sirve") or []] \
                != [("tienda", "web")]:
            findings.append(f"the repository a contract names is reported as serving "
                            f"{web.get('sirve')!r}: the join between a repository and the "
                            f"service built from it is the whole reading")
        # ONE TREE, TWO SERVICES. Reporting only the last one would hide
        # a service the platform is really running.
        todo = by.get("tienda-todo") or {}
        served = {u.get("servicio") for u in todo.get("sirve") or []}
        if served != {"front", "bff"}:
            findings.append(f"a repository that serves TWO services reports {sorted(served)}: "
                            f"one tree can be a front and a bff, and the service that falls "
                            f"out is one the platform runs and the screen does not show")
        free = by.get("algo-mio") or {}
        if free.get("sirve"):
            findings.append("a repository no contract names is reported as deployed")
        if free.get("state") != "already":
            findings.append(f"a repository nothing claims is filed as "
                            f"`{free.get('state')}`: it is an option, not a finding, and "
                            f"painting it red teaches somebody to ignore the colour on the "
                            f"one screen where it has to mean something")
        # THE COLOUR IS MEASURED TOO, and it is the honest answer to
        # «put the logos on the screen»: every one of those is a
        # trademark with a usage policy, and GitHub already publishes
        # the colour it paints its own dots with.
        if free.get("color") != "#dea584":
            findings.append(f"the colour GitHub measured for the language is not carried "
                            f"through ({free.get('color')!r}): it arrives in the same "
                            f"answer as the name, and it is what a screen can show "
                            f"without redistributing somebody else's mark")
        if free.get("lenguaje") != "Rust":
            findings.append(f"the language GitHub measured is not carried through "
                            f"({free.get('lenguaje')!r}): it is the one thing this command "
                            f"exists to bring back")
        none = by.get("sin-lenguaje") or {}
        if "lenguaje" not in none or none.get("lenguaje") is not None:
            findings.append("a repository GitHub could not put a language on does not "
                            "carry the field as empty: absent and unknown have to be "
                            "distinguishable downstream")

    for f in findings:
        print(f)
    # AND NOTHING FALLS OFF THE SECOND PAGE. The stub always answers in
    # two, because an account of more than a hundred repositories is
    # answered in pages and a reader that took the first would lose the
    # rest in silence.
    if full is not None:
        got = {s.get("step", "").split(":", 1)[-1] for s in full.get("steps") or []
               if s.get("step", "").startswith("repo:")}
        lost = sorted({r["name"] for r in REPOS} - got)
        if lost:
            findings.append(f"{lost} arrived on the second page of the answer and did not "
                            f"reach the document: an account is read in pages, and a "
                            f"reader that takes only the first loses everything past the "
                            f"hundredth repository without a word")

    print(f"SCOPE: 3 accounts in front of the command — silent rc "
          f"{(blind or {}).get('rc')}, empty rc {(empty or {}).get('rc')}, "
          f"{len(REPOS)} repositories rc {(full or {}).get('rc')}")
finally:
    shutil.rmtree(home, ignore_errors=True)
