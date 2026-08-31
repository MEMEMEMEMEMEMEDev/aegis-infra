# title: every pipeline the seed ships has a job that fires it, and every job names a pipeline that exists
# origin: new in v3 — measured on 2026-08-31, the day two AI engines had a build definition nobody could trigger
check() {
# A Jenkinsfile nobody fires is, from the instance's side, exactly the
# same as having no source at all. That is not a theory: on 2026-08-31
# `ai/engine-gpu/Jenkinsfile` had existed for two days, complete, and
# no job-dsl item named it — so the image row stayed on the
# sixty-four-zero marker and phase 87 could not open. The artifact
# looked like it could build a GPU engine and could not.
#
# BOTH DIRECTIONS, and the second is the one that rots quietly:
#
#   · a pipeline the seed ships with no item whose scriptPath names it
#     — a build definition that cannot be triggered;
#   · an item whose scriptPath names a file the seed does NOT ship —
#     a job that is born broken and fails at the first run, which is
#     late and looks like an infrastructure problem.
#
# The subject is DERIVED from the tree on both sides: every
# `*/Jenkinsfile` under seed/platform (at any depth), and every
# `scriptPath('...')` of the job-dsl. A written list of pipelines is
# the thing this check exists to replace.
#
# `docs/protocols/templates/Jenkinsfile.app` is NOT swept, and the
# reason is structural rather than an exemption: it is a TEMPLATE that
# `aegis org` derives per tenant repo into `.aegis-app/`, so its job is
# born from a contract and not from the seed's job-dsl. It is check 147
# and the harness that watch that one.
# AND the third thing, because `libexec/aegis-ai` names this check by
# number for it: every row of `AI_CONTAINERFILES` has to point at a
# Containerfile the seed actually ships. That table is what
# `aegis ai images` walks to resolve the `__FROM_*__` bases, and a row
# naming a directory that is not there fails at build time — late, and
# looking like a registry problem.
VALUES="$SEED/platform/k8s/base/platform/jenkins/values.yaml"
[[ -f "$VALUES" ]] || { fail "jenkins/values.yaml is not there: $VALUES"; return; }

OUT="$(python3 - "$SEED/platform" "$VALUES" "$AEGIS_ROOT/libexec/aegis-ai" <<'PY'
import os, re, sys, pathlib, yaml
root, values = pathlib.Path(sys.argv[1]), sys.argv[2]

# The AI Containerfile table, derived from its owner and never listed
# here: a copy of that list in this file is the pair that drifts.
src = pathlib.Path(sys.argv[3])
if src.is_file():
    m = re.search(r'^AI_CONTAINERFILES="([^"]*)"', src.read_text(encoding="utf-8"), re.M)
    rows = (m.group(1).split() if m else [])
    if not rows:
        print("FAILAI_CONTAINERFILES could not be read from libexec/aegis-ai: with no "
              "row, no missing Containerfile could be found and that is a verdict "
              "about the reader")
    for r in rows:
        if not (root / r).is_file():
            print("FAILAI_CONTAINERFILES names %s and the seed does not ship it: "
                  "`aegis ai images` would fail to resolve its base at build time, "
                  "which is late and looks like a registry problem" % r)

shipped = sorted(
    str(p.relative_to(root))
    for p in root.rglob("Jenkinsfile")
    if "docs/protocols/templates" not in str(p.relative_to(root))
)
if not shipped:
    print("FAILno Jenkinsfile was found under seed/platform: the check lost its "
          "subject and is NOT reporting that as a pass")
    raise SystemExit

try:
    v = yaml.safe_load(open(values, encoding="utf-8"))
    items = yaml.safe_load(v["controller"]["JCasC"]["configScripts"]["aegis-jobs"])["jobs"]
except Exception as e:
    print(f"FAILthe job-dsl could not be read ({e!r}): with no items, every pipeline "
          "would look unfired and that is a verdict about the reader, not the artifact")
    raise SystemExit

named = {}
for it in items:
    script = it.get("script", "") if isinstance(it, dict) else ""
    job = re.search(r"(?:pipelineJob|multibranchPipelineJob)\(\s*'([^']+)'", script)
    for sp in re.findall(r"scriptPath\(\s*'([^']+)'", script):
        named.setdefault(sp, job.group(1) if job else "?")

print("    %d pipeline(s) in the seed · %d scriptPath(s) in the job-dsl · %d AI Containerfile row(s)"
      % (len(shipped), len(named), len(rows)))

for jf in shipped:
    if jf not in named:
        print("FAIL%s is shipped and NO job-dsl item names it: a build definition "
              "nobody can trigger, which from the instance is the same as no source "
              "at all" % jf)
for sp, job in sorted(named.items()):
    if not (root / sp).is_file():
        print("FAILthe job %s names scriptPath %s and the seed does not ship it: the "
              "job is born broken and fails at its first run" % (job, sp))
PY
)" || { fail "the reading of the pipelines could not be completed"; return; }
printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "pipelines and jobs disagree: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "every pipeline the seed ships is named by a job, and every job names a pipeline that exists"
fi
}
