# scanner of check 173 — a tenant AppProject that the generator derives has
# a path that applies it AFTER it is derived.
#
# Its own file, in python, for the two reasons the last ten checks were
# corrected for: a shell scan that dies prints nothing and turns the check
# green (check 166), and a grep over this repo reads the paragraph that
# EXPLAINS the defect and accuses the file that fixes it (checks 161, 163,
# 165, 166, 167, 168). Here the subject is a program, so the measurement is
# to RUN it and read what it says, which no comment can fake.
#
# WHAT IS DERIVED, and from where:
#   · the artifact          — the module constant that names a file whose
#                             basename talks about tenant AppProjects
#   · the stage that writes  — the apply_*(write) whose source opens it "w"
#   · the project names      — read from the DOCUMENTS the stage wrote
#   · the announced path     — read from the command the run prints
# Nothing here is a list typed by hand. A list typed here would be one more
# place to remember, which is the class this whole check descends from.
import ast
import contextlib
import io
import inspect
import os
import pathlib
import re
import shutil
import sys
import tempfile

import yaml

ROOT = pathlib.Path(sys.argv[1])
SEED_PLATFORM = ROOT / "seed" / "platform"
PHASE35 = ROOT / "init" / "phases" / "35-gitops.sh"
ORG_PY = ROOT / "lib" / "aegis" / "org.py"

problems = []
ANSI = re.compile(r"\033\[[0-9;]*m")
# `#` opens a comment in bash; only at the start of a line or after
# whitespace, so ${var#pat} survives. Every scan below reads CODE.
HASH = re.compile(r"(^|\s)#.*$")


def code_of(text):
    return "\n".join(HASH.sub(r"\1", ln) for ln in text.splitlines())


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


for needed in (SEED_PLATFORM, PHASE35, ORG_PY):
    if not needed.exists():
        die(f"{needed} is not there: this check cannot have an opinion")

# ── the fixture: an instance whose owner IS the placeholder (as 113) ──
base = "/dev/shm" if os.path.isdir("/dev/shm") else None
tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-173.", dir=base))
try:
    work = tmp / "platform"
    shutil.copytree(SEED_PLATFORM, work)
    conf = tmp / "aegis.conf"
    conf.write_text("GH_OWNER=__GH_OWNER__\nPLATFORM_REPO=__PLATFORM_REPO__\n"
                    "APP_REPO=__APP_REPO__\nROOT_DOMAIN=__ROOT_DOMAIN__\n")
    sys.dont_write_bytecode = True
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    os.environ["PLATFORM_DIR"] = str(work)
    os.environ["AEGIS_CONF"] = str(conf)
    sys.path.insert(0, str(ROOT / "lib"))
    try:
        from aegis import org as gen
    except Exception as e:                                  # noqa: BLE001
        die(f"the product's generator does not load: {e}")

    # ── the artifact, derived from the module ────────────────────────
    # The constant is looked for by WHAT IT NAMES, not by the name it has:
    # a path under the instance whose basename speaks of tenants and of
    # AppProjects. Asking for `APPPROJECTS_K8S` by name would tie this
    # check to a spelling instead of to the thing.
    consts = {n: v for n, v in vars(gen).items()
              if isinstance(v, str) and n.isupper() and os.path.isabs(v)
              and os.path.basename(v).startswith("appproject")
              and "tenant" in os.path.basename(v)}
    if len(consts) != 1:
        die("the generator no longer names exactly one file for the tenant "
            f"AppProjects (found {sorted(consts)}): the subject of this check "
            "is gone, and it has to be said and not passed over")
    CONST, ARTIFACT = next(iter(consts.items()))
    REL = os.path.relpath(ARTIFACT, str(work))

    # ── the stage that writes it, derived from its source ────────────
    stages = []
    for name in sorted(dir(gen)):
        if not name.startswith("apply_"):
            continue
        fn = getattr(gen, name)
        if not callable(fn):
            continue
        try:
            if list(inspect.signature(fn).parameters) != ["write"]:
                continue
            src = inspect.getsource(fn)
        except (TypeError, ValueError, OSError):
            continue
        if re.search(rf"open\(\s*{CONST}\s*,\s*[\"']w[\"']", src):
            stages.append((name, fn))
    if len(stages) != 1:
        die(f"exactly one apply_*(write) stage must write {CONST}; found "
            f"{[n for n, _ in stages]}")
    STAGE_NAME, STAGE = stages[0]

    # ── the function that hands the step over, derived the same way ──
    handovers = [n for n, v in vars(gen).items()
                 if inspect.isfunction(v) and v.__module__ == gen.__name__
                 and "kubectl apply -f" in (inspect.getsource(v) or "")]
    if len(handovers) != 1:
        problems.append(
            "exactly one function of the generator must carry the apply step "
            f"(found {sorted(handovers)}): with none, nothing hands it over; "
            "with several, whoever changes the path changes only one of them")
    HANDOVER = handovers[0] if len(handovers) == 1 else None
    if HANDOVER == STAGE_NAME:
        problems.append(
            f"the apply step is printed by the stage {STAGE_NAME}() itself: "
            "`projects` is the fourth of twelve stages and the eight that "
            "follow push it off the screen — the step only a person can take "
            "has to be handed over by the RUN, at the end")

    # ── run it, and read what it says ────────────────────────────────
    def run():
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            STAGE(write=True)
            if HANDOVER:
                getattr(gen, HANDOVER)()
        # The colours are decided at import time against the REAL stdout,
        # which under the verifier can be a terminal: strip them or every
        # match below would depend on where the check was launched from.
        return ANSI.sub("", buf.getvalue())

    def announced_paths(out):
        return re.findall(r"kubectl apply -f\s+(\S+)", out)

    # A contract that declares a repo is the whole precondition: one per
    # organization THAT HAS A REPO is what the generator promises.
    (work / "orgs").mkdir(exist_ok=True)
    (work / "orgs" / "verify-tenant.yaml").write_text(
        "organizacion: verify-tenant\nrepo: git@github.com:__GH_OWNER__/x.git\n")

    first = run()
    # The names come from the DOCUMENTS the stage wrote, parsed as YAML —
    # not from the contract and not from the generator's own helper. What
    # the run has to announce is what the file carries.
    names = []
    for d in yaml.safe_load_all(pathlib.Path(ARTIFACT).read_text(encoding="utf-8")):
        if isinstance(d, dict) and d.get("kind") == "AppProject":
            n = (d.get("metadata") or {}).get("name")
            if n:
                names.append(n)
    if not names:
        die("a contract that declares a repo derived NO AppProject: either "
            "the generator stopped deriving them or the fixture stopped "
            "being a contract — a scan that measured nothing is not a verdict")

    def audit(label, out, expect):
        paths = announced_paths(out)
        if expect and not paths:
            problems.append(
                f"{label}: the run derives {len(names)} tenant AppProject(s) "
                f"({', '.join(names)}) and never says how they reach the "
                "cluster — nothing in GitOps applies that file, and the init "
                "phase that does applied it when it was empty")
            return
        if not expect:
            if paths:
                problems.append(
                    f"{label}: with zero derived projects the run still asks "
                    f"for `kubectl apply -f {paths[0]}`, which is a notice "
                    "that is always on and therefore says nothing")
            return
        for p in paths:
            got = os.path.normpath(os.path.join(str(work), p))
            if got != os.path.normpath(ARTIFACT):
                problems.append(
                    f"{label}: the run tells the operator to apply {p}, which "
                    f"resolves to {got} and not to {ARTIFACT} — the file it "
                    "just wrote; a path typed by hand into a message drifts "
                    "the day the file moves and nobody finds out")
        missing = [n for n in names if n not in out]
        if missing:
            problems.append(
                f"{label}: the step is handed over without naming "
                f"{', '.join(missing)} — the operator cannot tell whether it "
                "concerns the organization just registered or another one")

    audit("on the run that derives them", first, expect=True)

    # THE ONE THAT WAS MISSING. A second identical run: the file does not
    # change, and until 2026-09-02 the notice depended on the file having
    # changed, so it went silent exactly on the run that repeats the
    # command — while the cluster still had no project.
    second = run()
    audit("on a second, identical run", second, expect=True)

    # And the other side: with nothing derived there is nothing to apply.
    # EVERY contract goes, not only the fixture's: the seed may legitimately
    # ship one, and leaving it behind would make this last measurement
    # accuse a run that still had something to announce.
    for c in (work / "orgs").glob("*.y*ml"):
        c.unlink()
    audit("with zero organizations", run(), expect=False)

    # ── the literal that must not exist ──────────────────────────────
    # The announced path has to be DERIVED from the constant. If the same
    # relative path also lives as a literal in the generator, there are two
    # copies of it and only one gets updated.
    tree = ast.parse(ORG_PY.read_text(encoding="utf-8"))
    # `in`, not `==`: the path travels inside an f-string, so the literal
    # would arrive as the fragment "kubectl apply -f k8s/bootstrap/…" and an
    # equality would walk straight past it.
    if [n for n in ast.walk(tree)
            if isinstance(n, ast.Constant) and isinstance(n.value, str)
            and REL in n.value]:
        problems.append(
            f"lib/aegis/org.py writes the literal '{REL}' next to the "
            f"constant {CONST} that already holds it: two copies of a path, "
            "and the message is the copy nobody updates")

    # ── main() hands it over, and hands it over LAST ─────────────────
    main_fn = next((n for n in tree.body
                    if isinstance(n, ast.FunctionDef) and n.name == "main"), None)
    if main_fn is None:
        die("lib/aegis/org.py has no main(): the run's entry point moved and "
            "this check no longer knows where the handover would go")
    if HANDOVER:
        calls = [n.lineno for n in ast.walk(main_fn)
                 if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                 and n.func.id == HANDOVER]
        stage_refs = [n.lineno for n in ast.walk(main_fn)
                      if isinstance(n, ast.Name) and n.id == STAGE_NAME]
        # One handover per place the stages run, and each one AFTER its
        # own. Comparing only the extremes would be wrong here: main has
        # two stage runs (delete, and plan/apply), so the delete path's
        # handover legitimately comes before the second run's stages.
        calls.sort()
        stage_refs.sort()
        if not calls:
            problems.append(
                f"main() never calls {HANDOVER}(): the step is derived and "
                "never printed, which is the same as not existing")
        elif len(calls) != len(stage_refs):
            problems.append(
                f"main() runs the stages in {len(stage_refs)} place(s) and "
                f"hands the step over in {len(calls)}: one of the paths "
                "derives AppProjects and says nothing about them")
        elif any(c < s for c, s in zip(calls, stage_refs)):
            problems.append(
                f"main() calls {HANDOVER}() before the stages of its own "
                "path: the eight stages that follow push the handover off "
                "the screen, which is where it was already being missed")

    # ── and phase 35 keeps applying it, without looking like a success ─
    ph = code_of(PHASE35.read_text(encoding="utf-8"))
    bn = os.path.basename(ARTIFACT)
    applies = [ln for ln in ph.splitlines()
               if "kubectl apply" in ln and bn in ln]
    if not applies:
        problems.append(
            f"init/phases/35-gitops.sh no longer applies {bn}: an init over a "
            "tree that ALREADY has contracts would leave every organization "
            "at 'project not found'")
    guarded = [ln for ln in ph.splitlines()
               if "yaml_has_docs" in ln and bn in ln]
    if not guarded:
        problems.append(
            f"phase 35 applies {bn} without asking whether it has documents: "
            "`kubectl apply` over a file with no objects exits 1 and takes the "
            "phase with it, which is the seed failing to start for being right")
    empty_branch = [ln for ln in ph.splitlines()
                    if "log_ok" in ln and "contract" in ln]
    if empty_branch:
        problems.append(
            "phase 35 reports the empty file with log_ok: zero contracts is "
            "not an achievement, and a success there is what made everyone "
            "believe the projects had been applied")

    for m in problems:
        print(m)
    print(f"__COUNT__ {len(names)}", file=sys.stderr)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
