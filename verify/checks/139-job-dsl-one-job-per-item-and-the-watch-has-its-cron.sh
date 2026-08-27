# title: job-dsl: one job per item, the five platform jobs named, and image-watch carries its cron
# origin: new in v3 — 2026-08-27, the day a second pipelineJob folded into the first one's item
check() {
# jenkins/values.yaml seeds the platform's jobs through JCasC job-dsl:
# a `jobs:` list of `- script: >` items. Three things about that shape
# break silently, and each one leaves Jenkins running with fewer jobs
# than the seed says:
#   · the `>` FOLD. It joins the block onto one line, so two
#     pipelineJob() in the same item become `...} pipelineJob(...)`,
#     which Groovy reads as a chained call on the previous job. It
#     throws MissingMethodException in the JCasC reload log and no job
#     is born — not the second, not the first. One item, one job.
#   · a job renamed or dropped. Phase 80 fires `mirror-images` and
#     phase 85 fires `image-watch` by NAME; the protocols name them;
#     a rename here is a 404 there.
#   · image-watch's cron. It lives HERE and not in the Jenkinsfile: a
#     declarative `triggers { cron }` inside a Jenkinsfile is only
#     registered after the job's FIRST run, so until somebody ran it by
#     hand the schedule did not exist. In the job-dsl it is effective
#     the moment JCasC seeds the job. Without it the watch is a job
#     that runs once at birth (phase 85) and never again — and
#     ImageWatchSilent is the alert that would say so, two days late.
V="$P/k8s/base/platform/jenkins/values.yaml"
[[ -f "$V" ]] || { fail "$V does not exist: nothing seeds the platform's jobs"; return; }
D139=""
python3 - "$V" <<'PY' || D139=" (see the detail above);"
import re, sys, yaml
p = sys.argv[1]
try:
    raw = yaml.safe_load(open(p))["controller"]["JCasC"]["configScripts"]["aegis-jobs"]
except (KeyError, TypeError) as e:
    print(f"    controller.JCasC.configScripts.aegis-jobs is not there ({e!r}): no job-dsl, no jobs", file=sys.stderr); sys.exit(1)
try:
    items = yaml.safe_load(raw)["jobs"]
except Exception as e:
    print(f"    aegis-jobs does not parse as a job-dsl document with a `jobs:` list: {e}", file=sys.stderr); sys.exit(1)
bad = []
if not isinstance(items, list) or len(items) < 5:
    bad.append(f"the jobs list has {len(items) if isinstance(items, list) else 0} items and the platform seeds five (hello-aegis, ci-images, mirror-images, base-images, image-watch)")
    items = items if isinstance(items, list) else []
DECL = re.compile(r"\b(multibranchPipelineJob|pipelineJob)\(\s*'([^']+)'")
names = {}
for i, it in enumerate(items, 1):
    script = it.get("script", "") if isinstance(it, dict) else ""
    decls = DECL.findall(script)
    if len(decls) != 1:
        bad.append(f"item {i} declares {len(decls)} jobs ({', '.join(n for _, n in decls) or 'none'}): the `>` fold turns two into a chained call and NEITHER is born — one item, one job")
    for kind, name in decls:
        names[name] = script
for want in ("ci-images", "mirror-images", "base-images", "image-watch"):
    if want not in names:
        bad.append(f"no item declares a job named {want!r}: the phases and the protocols fire it by that name")
iw = names.get("image-watch")
if iw is not None:
    m = re.search(r"triggers\s*\{(.*?)\}", iw, re.S)
    if not m or "cron(" not in m.group(1):
        bad.append("the image-watch item has no cron( inside triggers { }: the watch runs once at birth and never again, and only ImageWatchSilent would notice, two days late")
print(f"    {len(items)} items, jobs: {', '.join(sorted(names))}", file=sys.stderr)
for b in bad: print(f"    {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D139" ]]; then fail "job-dsl:$D139"
else pass "every job-dsl item declares exactly one job, the four platform jobs are named, and image-watch carries its cron in triggers"; fi
}
