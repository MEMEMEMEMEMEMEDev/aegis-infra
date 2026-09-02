# scanner of check 177 — the jobs `aegis ci` can fire are the ones the
# job-dsl declares, and there is no list of them written by hand.
#
# Its own file, and python, for the two reasons this repo has paid for
# more than once: a shell scan that dies quietly turns a check green
# (check 166), and a grep over a file that DOCUMENTS the defect it hunts
# accuses the paragraph explaining the fix (checks 161, 163, 165, 166,
# 167, 168). libexec/aegis-ci carries the whole story of this bug in its
# header, job names included, so every read here is over code with the
# comments stripped.
#
# The heart of it is not a static rule. Any static rule can be satisfied
# by writing the CURRENT eleven job names out by hand, which is the very
# state this check exists to forbid. So the command is DRIVEN, against a
# job-dsl that declares two jobs invented one second ago: a list cannot
# know a name that did not exist when it was typed.
import os, pathlib, re, subprocess, sys, tempfile, uuid, shutil
import yaml

root = pathlib.Path(sys.argv[1])          # AEGIS_ROOT (the product)
values = pathlib.Path(sys.argv[2])        # the seed's job-dsl
ci = root / "libexec" / "aegis-ci"

problems = []


def bad(msg):
    problems.append(msg)


# ── the declarative truth ────────────────────────────────────────────
# Read the same way `aegis org apply` writes it and JCasC consumes it:
# the outer document, then the block scalar as YAML of its own. A `#`
# paragraph inside that block is a comment of the INNER yaml, so prose
# never becomes a job — on either side of this comparison.
GUARD = re.compile(r"^\s*if\s*\(\s*'([^']*)'\s*\)")
DECL = re.compile(r"\b(pipelineJob|multibranchPipelineJob)\(\s*'([^']+)'")


def declared_in(text):
    v = yaml.safe_load(text) or {}
    items = yaml.safe_load(v["controller"]["JCasC"]["configScripts"]["aegis-jobs"])["jobs"]
    out = {}
    for it in items:
        script = it.get("script", "") if isinstance(it, dict) else str(it or "")
        g = GUARD.match(script)
        # `if ('__AI_GATEWAY_REPO__')` — with AI=no it renders empty,
        # an empty string is falsy in groovy, and the job is not seeded.
        if g is not None and not g.group(1):
            continue
        for kind, name in DECL.findall(script):
            out.setdefault(name, "multibranch" if kind.startswith("multi") else "pipeline")
    return out


declared = declared_in(values.read_text(encoding="utf-8"))
if not declared:
    raise SystemExit("the seed's job-dsl declares no job: the check lost its subject "
                     "and is NOT reporting that as a pass")

# ── the code, without the prose that tells this bug's story ──────────
HASH = re.compile(r'(^|\s)#.*$')
code = "\n".join(HASH.sub(r'\1', line) for line in ci.read_text(encoding="utf-8").splitlines())

# (1) it has to READ the job-dsl. Nothing else in the artifact creates a
# job, so a command that never opens that file is answering from
# somewhere it invented.
rel = "k8s/base/platform/jenkins/values.yaml"
if rel not in code:
    bad("libexec/aegis-ci never names %s: the job-dsl is the only thing that creates a "
        "job, and a command that does not read it is answering from a list of its own" % rel)

# (2) the nesting is the library's business. A multibranch's buildable
# item is its BRANCH, addressed /job/<job>/job/<branch>; writing that by
# hand is how phase 87 turned a live job into a 404 reported as «the job
# does not exist» (check 164, same day).
raw = [l.strip() for l in code.splitlines()
       if re.search(r'/job/\$[A-Za-z0-9_{]', l) and "_jenkins_job" not in l]
if raw:
    bad("libexec/aegis-ci builds a Jenkins URL out of a raw item name — %s — and a "
        "multibranch's branch addressed that way is a 404 the caller reports as a "
        "missing job" % (" | ".join(raw[:2])))

# (3) the ONE hand-written thing left is the ORDER of the platform
# chain, which the job-dsl cannot carry. Every name in it still has to
# be a job the job-dsl declares, or the order outlived its jobs.
m = re.search(r'^CHAIN_ORDER=\(([^)]*)\)', code, re.M)
if not m:
    bad("libexec/aegis-ci has no CHAIN_ORDER: the supply chain's order is not derivable "
        "from the job-dsl and firing mirror-images after base-images does not fail "
        "loudly, it builds on yesterday's mirror and says SUCCESS")
    order = []
else:
    order = m.group(1).split()
    for n in order:
        if n not in declared:
            bad("CHAIN_ORDER names %s and the job-dsl does not declare it: the order "
                "outlived its job, and the default run would fire a name nothing "
                "creates" % n)

# ── the command, DRIVEN against a job-dsl it has never seen ──────────
# Two jobs invented here and now, in a synthetic instance. A hand-written
# list cannot contain a name that did not exist when it was written, so
# this is the assertion no static rule can give.
probe = "aegis-ci-probe-" + uuid.uuid4().hex[:8]
probe_mb = probe + "-mb"

lines = values.read_text(encoding="utf-8").splitlines(keepends=True)
start = next((i for i, l in enumerate(lines) if re.match(r'^ {6}aegis-jobs: \|\s*$', l)), None)
if start is None:
    raise SystemExit("the aegis-jobs configScript was not found in the seed's job-dsl: "
                     "the injection point is gone and this check measured nothing")
end = next((i for i in range(start + 1, len(lines))
            if lines[i].strip() and not lines[i].startswith(" " * 7)), len(lines))
extra = ("          - script: >\n"
         "              pipelineJob('%s') {\n"
         "                displayName('%s')\n"
         "              }\n"
         "          - script: >\n"
         "              multibranchPipelineJob('%s') {\n"
         "                displayName('%s')\n"
         "              }\n" % (probe, probe, probe_mb, probe_mb))
lines.insert(end, extra)
grown = "".join(lines)
expected = declared_in(grown)
if probe not in expected or probe_mb not in expected:
    raise SystemExit("the probe jobs could not be injected into a copy of the job-dsl: "
                     "the instrument never reached the subject")

sandbox = tempfile.mkdtemp(prefix="aegis-177.")
try:
    jenkins = pathlib.Path(sandbox, "platform", rel)
    jenkins.parent.mkdir(parents=True, exist_ok=True)
    jenkins.write_text(grown, encoding="utf-8")
    # A kubectl that answers nothing to everything. The check drives a
    # command whose next step after resolving the jobs is the cluster,
    # and the verifier does not talk to the cluster: with this on PATH
    # the walk stops at «COULD NOT EVALUATE», which is exactly the
    # answer that proves the name WAS accepted.
    stub = pathlib.Path(sandbox, "bin")
    stub.mkdir()
    (stub / "kubectl").write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
    (stub / "kubectl").chmod(0o755)

    env = dict(os.environ)
    env.update(PATH=str(stub) + os.pathsep + env.get("PATH", ""),
               AEGIS_ROOT=str(root),
               AEGIS_HOME=sandbox,
               PLATFORM_DIR=os.path.join(sandbox, "platform"),
               AEGIS_CONF=os.path.join(sandbox, "aegis.conf"),
               AEGIS_STATE_DIR=os.path.join(sandbox, ".init-state"),
               AEGIS_SECRETS_DIR=os.path.join(sandbox, ".state-secrets"),
               KUBECONFIG="/dev/null")

    def run(*args):
        return subprocess.run(["bash", str(ci), *args], env=env,
                              capture_output=True, text=True, timeout=120)

    # (4) every job the job-dsl declares is LISTED, with the item Jenkins
    # builds and a timeout that is a number.
    r = run("jobs")
    if r.returncode != 0:
        bad("«ci jobs» exited %d instead of listing the jobs (%s): a reader that dies "
            "leaves the set empty, and an empty set makes every name the operator types "
            "look invalid" % (r.returncode, (r.stderr.strip().splitlines() or ["no output"])[-1]))
        listed = {}
    else:
        listed = {}
        for line in r.stdout.splitlines():
            f = line.split()
            if len(f) >= 4 and f[1] in ("pipeline", "multibranch"):
                listed[f[0]] = (f[1], f[2], f[3])
        for name, kind in sorted(expected.items()):
            if name not in listed:
                bad("the job-dsl declares %s (%s) and «ci jobs» does not list it: a job "
                    "this artifact creates that the command cannot fire is the bug of "
                    "2026-09-01, and %s was invented one second before this run" % (
                        name, kind, probe))
                continue
            got_kind, item, timeout = listed[name]
            # a multibranch is a FOLDER: what builds is /job/<x>/job/main
            want = "%s/job/main" % name if kind == "multibranch" else name
            if item != want:
                bad("«ci jobs» says %s builds the item %s and Jenkins builds %s: a "
                    "multibranch has no build of its own, its branch does" % (name, item, want))
            if not re.fullmatch(r"\d+s", timeout) or int(timeout[:-1]) <= 0:
                bad("%s is given the timeout «%s»: jenkins_wait_build reads a timeout that "
                    "is not a positive number as zero and gives up on its first lap" % (
                        name, timeout))
        for name in sorted(set(listed) - set(expected)):
            bad("«ci jobs» offers %s and the job-dsl declares no such job: the command is "
                "offering a name Jenkins would answer 404 to" % name)

    # (5) a job that exists is ACCEPTED. It gets as far as the cluster,
    # which is not there — «could not evaluate», never «that is not a
    # job».
    for name in (probe, probe_mb):
        r = run("build", name)
        if r.returncode == 3 or "is not a job" in r.stderr:
            bad("«ci build %s» is refused as not a job while the job-dsl declares it: %s" % (
                name, (r.stderr.strip().splitlines() or ["no reason given"])[0]))

    # (6) and a name nothing declares is refused WITH THE DERIVED LIST.
    # The point is not that it says no; it is that what it offers grew
    # when the job-dsl grew.
    r = run("build", "zzz-no-such-job")
    if r.returncode != 3:
        bad("«ci build zzz-no-such-job» exited %d: a name the job-dsl does not declare is "
            "a usage error, answered before any cluster is touched" % r.returncode)
    for name in (probe, probe_mb):
        if name not in r.stderr:
            bad("the refusal does not name %s among the jobs that DO exist: it is listing "
                "a constant, and a constant is what stopped mentioning the AI lanes and "
                "every tenant multibranch" % name)
            break
finally:
    shutil.rmtree(sandbox, ignore_errors=True)

for p in problems:
    print(p)
print("__COUNT__ %d %d" % (len(declared), len(order)), file=sys.stderr)
