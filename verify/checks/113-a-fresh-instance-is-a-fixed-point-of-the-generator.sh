# title: a fresh instance with zero organizations is a fixed point of the generator
# origin: T-01 (2026-08-25) — three committed artifacts had drifted from what emits them
check() {
# WHAT THIS MEASURES. The seed ships files that `aegis org` WRITES:
# tenants.yaml, appprojects-tenants.yaml, garage's two, argocd's
# secret-generator, the derived blocks inside jenkins' and vmagent's
# values.yaml, and public_hostnames inside main.tf. If any of them is
# not exactly what the generator produces, the FIRST `aegis org apply`
# a person runs rewrites files they never touched — and the diff
# appears mixed in with their own change, in a commit they are about to
# push. The generated ones are the files nobody reads, so it gets
# pushed.
#
# THE INVARIANT, stated as it is measured: on an instance just born
# from the seed and with ZERO organizations, running every stage must
# write NOTHING. Not «it converges after two runs» — the first one has
# to be a no-op, because the seed's whole job is to already be the
# answer.
#
# WHY IT DID NOT EXIST BEFORE, and what it caught the day it was
# written (2026-08-25):
#
#   1. `apply_jenkins` RAISED against the seed. The derived block's
#      markers were in no file, so it demanded them and stopped. Since
#      the eleven stages run one after another, the first real
#      `aegis org apply` of any instance died there — and the stages
#      after it never ran nor said why.
#   2. `main.tf` shipped THREE public hostnames while edge.yaml declared
#      FIVE. Phase 25 applies tofu; `aegis org edge` only runs in phase
#      85, and it does not re-apply. A clean instance was left with
#      grafana and ntfy WITHOUT a CNAME — no error, nothing red, and
#      the git tree claiming they existed. It is the exact failure mode
#      edge.yaml's own header describes.
#   3. vmagent's probes block and argocd's secret-generator were the
#      v2 hand-written files: the first `apply` reformatted them.
#
# The three are the same class: a generated artifact nobody compared
# against its generator. 091b compares the hand-written COPIES; this
# one compares the WRITTEN ORIGINALS.
#
# THE FIXTURE, declared. The generator needs an instance's conf
# (GH_OWNER/PLATFORM_REPO) and the seed is a template full of
# __PLACEHOLDERS__. So the fixture is an instance whose owner IS the
# placeholder: `GH_OWNER=__GH_OWNER__`. The generator then emits
# exactly the template form the seed carries, and nothing has to be
# substituted or excluded from the comparison.
D113=""
python3 - "$AEGIS_ROOT" "$P" <<'PY' || D113=" (see the detail above)"
import contextlib, inspect, io, os, pathlib, shutil, subprocess, sys, tempfile

root, P = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

# /dev/shm and not the disk: this copies the whole platform tree and
# runs a generator over it. On the disk it would leave the artifact's
# directory dirty if the check died halfway through.
base = "/dev/shm" if os.path.isdir("/dev/shm") else None
tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-fixpoint.", dir=base))
try:
    work = tmp / "platform"
    shutil.copytree(P, work)
    conf = tmp / "aegis.conf"
    conf.write_text("GH_OWNER=__GH_OWNER__\nPLATFORM_REPO=__PLATFORM_REPO__\n"
                    "APP_REPO=__APP_REPO__\nROOT_DOMAIN=__ROOT_DOMAIN__\n")

    sys.dont_write_bytecode = True
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    os.environ["PLATFORM_DIR"] = str(work)
    os.environ["AEGIS_CONF"] = str(conf)
    sys.path.insert(0, str(root / "lib"))
    try:
        from aegis import org as gen
    except Exception as e:
        print(f"    the product's generator does not load: {e}", file=sys.stderr)
        sys.exit(1)

    # The stage list is DERIVED from the module, never kept by hand
    # here: a stage added to org.py has to enter this check on its own.
    # The signature is the criterion — every stage is `apply_x(write)`,
    # while apply_contract takes a path and is driven by a contract.
    stages = []
    for name in sorted(dir(gen)):
        if not name.startswith("apply_"):
            continue
        fn = getattr(gen, name)
        if not callable(fn):
            continue
        try:
            params = list(inspect.signature(fn).parameters)
        except (TypeError, ValueError):
            continue
        if params == ["write"]:
            stages.append((name, fn))
    if not stages:
        print("    NOT ONE apply_*(write) stage was found in lib/aegis/org.py: "
              "either they were renamed or the module stopped exporting them, "
              "and this check was measuring nothing", file=sys.stderr)
        sys.exit(1)

    bad = []
    for name, fn in stages:
        try:
            # The stage's report is noise here: what is measured is
            # whether it WROTE, and that is read from the diff.
            with contextlib.redirect_stdout(io.StringIO()):
                fn(write=True)
        except SystemExit as e:
            # SystemExit and not Invalid: `platform_repo()` leaves this
            # way, and in the real chain it takes the stages after it
            # with it — the operator gets neither the rest of the report
            # nor a reason.
            bad.append(f"the stage {name}() left through SystemExit: {e}")
        except Exception as e:
            bad.append(f"the stage {name}() raised {type(e).__name__}: "
                       f"{str(e).splitlines()[0]}")

    # `git diff` and not a walk of our own: it already knows how to
    # ignore .aegis-app/ (the gitignored staging area) and prints the
    # change in a form a person can read.
    changed = subprocess.run(
        ["diff", "-rq", "--exclude=.aegis-app", str(P), str(work)],
        capture_output=True, text=True)
    for line in changed.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[-1].startswith(str(work)):
            rel = pathlib.Path(parts[-1]).relative_to(work)
            d = subprocess.run(["diff", "-u", str(P / rel), str(work / rel)],
                               capture_output=True, text=True).stdout
            first = next((l for l in d.splitlines()
                          if l.startswith(("+", "-"))
                          and not l.startswith(("+++", "---"))), "")
            bad.append(f"{rel}: the first `aegis org apply` would rewrite it "
                       f"— e.g. {first.strip()[:110]!r}")
        elif line.strip():
            bad.append(line.strip())

    print(f"    {len(stages)} stages run on a copy with zero organizations",
          file=sys.stderr)
    for m in bad:
        print(f"    {m}", file=sys.stderr)
    sys.exit(1 if bad else 0)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
PY
if [[ -n "$D113" ]]; then
    fail "the seed is NOT a fixed point of its generator: the first apply would move it$D113"
else
    pass "with zero organizations every stage of the generator writes nothing: the seed is already the answer"
fi
}
