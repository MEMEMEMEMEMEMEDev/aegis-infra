# title: the watch is watched: rules ↔ metrics ↔ jobs ↔ panels
# origin: verify-static.sh (v2) ══ 92
check() {
# Until today this verifier had ZERO observability checks, and the sweep
# of 2026-08-22 found nine defects in the stack. Of the nine, most were
# STATICALLY DETECTABLE — no cluster was needed to see them, only
# looking. None of them was an outage: the nine were the same disease,
# an instrument reporting health without having measured anything.
#
# That is the blind spot this check covers. A panel, an alert and a
# scrape do not fail when they break: they stay EMPTY, and empty reads
# exactly like green. The only way to see it without a cluster is to
# cross the four layers against each other and demand that each one have
# a subject in the next.
#
# The ten comprobations, and each one names the REAL defect that brought
# it (proven by reintroduction: 12 mutations, 12 caught):
#
#   1. the DERIVED probe block falls inside config.scrape_configs.
#      Written with 8 spaces instead of 4 the YAML parses just the same
#      and the jobs do not exist — ArgoCD Synced, blackbox idle, nobody
#      says a word.
#   2. every panel points at a datasource grafana PROVISIONS, and every
#      dashboard carries the label the sidecar picks it up by.
#   3. every alert that COMPARES against a value has, in its own file, a
#      sister with absent(). Without it the series that disappears does
#      not go false: it goes empty, and an empty alert never fires. The
#      exceptions are declared ONE BY ONE with their why.
#   4. every own metric that is read is produced by somebody in the tree...
#   5. ...and every metric the tree produces is read by somebody.
#      Measuring and not looking is case (d) of the sweep: the cost is
#      paid and there is no signal.
#   6. every SPARSE metric (pushed by a CronJob) is read with
#      last_over_time and a window of at least two periods. Without that
#      the instant query falls between two pushes and returns empty: it
#      was TrivyDBSinMedida's daily false positive.
#   7. every job cited in a rule or a panel exists in vmagent.
#   8. JobDeScrapeDesaparecido's baked-in threshold == how many platform
#      jobs vmagent declares. A number kept by hand ages on its own.
#   9. vmalert and vmagent declare hot reload. Without it a rule
#      committed and synced is NOT LOADED.
#  10. vmagent with Recreate: its buffer is an RWO PVC with an exclusive
#      lock and with RollingUpdate the rollout enters CrashLoop forever.
D92=""
python3 - "$P" "$AEGIS_ROOT/lib/aegis/org.py" <<'PY' || D92="$D92 (see the detail above);"
import json, os, re, sys, pathlib, yaml

P = pathlib.Path(sys.argv[1])
OBS = P / "k8s/base/observability"
# In v2 the generator lived INSIDE the artifact (seed/platform/bin/). In
# v3 the code lives in the product and the seed is pure artifact (02 §1,
# V-134): the probe generator is looked for in libexec/.
GENERATOR = pathlib.Path(sys.argv[2])
if not OBS.is_dir():
    print(f"    {OBS} does not exist: there is no observability to cross-check", file=sys.stderr)
    sys.exit(1)
bad = []

# ── 1. inventory: vmagent's scrape_configs ──────────────────────────
vmag_txt = (OBS / "vmagent/values.yaml").read_text()
vmag = yaml.safe_load(vmag_txt)
jobs = [j["job_name"] for j in vmag["config"]["scrape_configs"]]

MARKER_START = "# --- DERIVED by aegis-org (tenant probes): do not edit by hand ---"
MARKER_END = "# --- END DERIVED ---"
i, f = vmag_txt.find(MARKER_START), vmag_txt.find(MARKER_END)
if i < 0 or f < 0:
    bad.append("vmagent/values.yaml: the markers of the block aegis-org derives are missing "
               "— without them the generator has nowhere to write the probes")
    derived, jobs_base = [], jobs
else:
    derived = re.findall(r"^\s*-\s*job_name:\s*(\S+)", vmag_txt[i:f], re.M)
    jobs_base = [j for j in jobs if j not in derived]
    for d in derived:
        if d not in jobs:
            bad.append(f"the derived job {d!r} sits between the markers but does NOT fall "
                       "inside config.scrape_configs: the wrong indentation parses as "
                       "valid YAML and leaves the job out, without a single complaint")

# In the seed the derived block is EMPTY —there are no contracts, and
# that is day one's normal state (check 87)—, so the tenant rules point
# at jobs that do NOT exist today and will exist as soon as there is an
# organization. To tell «it has no subject yet» from «it points at a job
# nobody declares», the pattern the generator emits is READ from the
# generator. Baking it in here would be the same trap this check is
# after: a copy that ages on its own.
# The generator stopped being an executable and is a module of the
# package (lib/aegis/org.py): `aegis org` is now 34 lines of argparse on
# top. This check measures the GENERATOR, so it follows the body, not
# the file name.
GEN = GENERATOR
derivable = []
if GEN.is_file():
    derivable = [re.sub(r"\{[a-z_]+\}", "xx", m)
                 for m in re.findall(r"job_name:\s*(\S*\{[a-z_]+\}\S*)", GEN.read_text())]
if not derivable:
    bad.append(f"{GEN} declares no derivable job_name: if the generator stopped emitting "
               "probes, the tenant rules were left with no possible subject")

# And the module each probe asks for has to exist in blackbox: asking
# for a nonexistent one is not a startup error, it is a permanent
# probe_success=0 — indistinguishable from «the site is down».
bb = [d for d in yaml.safe_load_all((OBS / "blackbox.yaml").read_text())
      if isinstance(d, dict) and d.get("kind") == "ConfigMap"]
modules = {m for d in bb for m in yaml.safe_load(d["data"]["config.yml"])["modules"]}
used = set(re.findall(r"module:\s*\[([a-z0-9_]+)\]", vmag_txt))
if GEN.is_file():
    used |= set(re.findall(r"module:\s*\[([a-z0-9_]+)\]", GEN.read_text()))
for m in sorted(used - modules):
    bad.append(f"a probe asks for blackbox module {m!r} and blackbox.yaml does not define it: "
               "the probe returns 0 forever, which reads exactly like «the site went down»")

# ── 2. inventory: own metrics the tree PRODUCES ─────────────────────
# They are derived from the producer (whoever pushes to
# /api/v1/import/prometheus), never from a list here: a hand-kept list
# drifts and this check would end up measuring its own copy instead of
# the artifact.
#
# There are two classes of producer and the difference is the CADENCE,
# which is what decides the minimum window it can be read with:
#  · cron  — period derivable from the schedule. Window ≥ 2 periods.
#  · build — there is no period: a repo can go weeks without one. The
#    floor is a POLICY (one week), not the mirror of a value living
#    somewhere else: that is why it is written here and not derived.
# Three kinds of file push: a CronJob under k8/ (its schedule is the
# cron), a tenant template (a build), and — since 2026-08-27 — every
# seed/platform/*/Jenkinsfile the platform runs itself. A platform
# Jenkinsfile's cadence is NOT in the Jenkinsfile: it is the `cron(…)`
# of the job-dsl item whose scriptPath names it (check 139 says why it
# lives there). One with a cron is a cron producer; one without is a
# build. So deleting image-watch's cron line turns its daily metrics
# into build-class ones, and every [2d] that reads them falls short of
# the week — which is exactly the shape of the hole: the watch stopped
# being daily and the rules went on reading it as if it were.
BUILD_FLOOR = 7 * 86400
def cron_period(sched):
    """Seconds between two runs of a 5-field cron, or None if the shape
    is not one of the four this check knows. Jenkins' `H` (a hash-
    spread value) counts as a fixed number: `H 6 * * *` is daily."""
    c = sched.split()
    if len(c) != 5 or c[2] != "*" or c[3] != "*" or c[4] != "*":
        return None
    m, h = c[0], c[1]
    fixed = lambda x: x == "H" or re.fullmatch(r"\d+", x) is not None
    if h == "*" and fixed(m):                                 return 3600
    if h.startswith("*/") and h[2:].isdigit() and fixed(m):   return int(h[2:]) * 3600
    if m.startswith("*/") and m[2:].isdigit() and h == "*":   return int(m[2:]) * 60
    if fixed(h) and fixed(m):                                 return 86400
    return None
producers = {}   # metric -> (file, class, minimum_secs)
for y in sorted((P / "k8s").rglob("*.yaml")):
    txt = y.read_text()
    if "/api/v1/import/prometheus" not in txt:
        continue
    for d in [d for d in yaml.safe_load_all(txt) if isinstance(d, dict)]:
        if d.get("kind") != "CronJob":
            continue
        sched = d["spec"]["schedule"]
        per = cron_period(sched)
        if per is None:
            bad.append(f"{y.name}: could not derive the period of the cron {sched!r} — with "
                       "no period there is no minimum window to demand of whoever reads it")
            continue
        for met in set(re.findall(r"\b(aegis_[a-z0-9_]+)\b", txt)):
            producers.setdefault(met, (str(y.relative_to(P)),
                                       f"cron every {per}s", 2 * per))
# The cron of each platform pipeline, from the job-dsl: scriptPath → cron.
job_cron = {}
try:
    jv = yaml.safe_load((P / "k8s/base/platform/jenkins/values.yaml").read_text())
    for it in yaml.safe_load(jv["controller"]["JCasC"]["configScripts"]["aegis-jobs"])["jobs"]:
        s = it.get("script", "") if isinstance(it, dict) else ""
        sp = re.search(r"scriptPath\(\s*'([^']+)'", s)
        tr = re.search(r"triggers\s*\{(.*?)\}", s, re.S)
        cr = re.search(r"cron\(\s*'([^']+)'", tr.group(1)) if tr else None
        if sp:
            job_cron[sp.group(1)] = cr.group(1) if cr else None
except Exception as e:
    bad.append(f"jenkins/values.yaml: the job-dsl could not be read ({e!r}): no platform pipeline has a known cadence")
# A metric emitted from a Jenkinsfile: `aegis_x{labels} value` or a bare
# `aegis_x value` (image-watch pushes its heartbeat without labels). A
# name followed by a word is prose in a comment, not a push.
JF_METRIC = re.compile(r"\b(aegis_[a-z0-9_]+)(?=\{|\s+[-+0-9$%\"'(])")
def jenkinsfile_producer(jf, rel, cadence, minimum):
    txt = jf.read_text()
    if "/api/v1/import/prometheus" not in txt:
        return
    for met in set(JF_METRIC.findall(txt)):
        producers.setdefault(met, (rel, cadence, minimum))
for jf in sorted((P / "docs/protocols/templates").glob("Jenkinsfile*")):
    jenkinsfile_producer(jf, str(jf.relative_to(P)), "every build", BUILD_FLOOR)
for jf in sorted(P.glob("*/Jenkinsfile")):
    rel = str(jf.relative_to(P))
    sched = job_cron.get(rel)
    per = cron_period(sched) if sched else None
    if per is None:
        jenkinsfile_producer(jf, rel, "every build", BUILD_FLOOR)
    else:
        jenkinsfile_producer(jf, rel, f"cron every {per}s ({sched!r} in the job-dsl)", 2 * per)

# The FOURTH class, since 2026-08-29: a producer that does not live in
# the cluster at all. The backups run from a systemd timer ON THE HOST,
# and after every capture the unit pipes `aegis data remote status`
# into the same import endpoint. It was found the way these things are
# supposed to be found — the rules for the off-site copy were written,
# and this check said nobody in the tree produced what they read.
#
# The metric names are not in the unit: the unit runs an `aegis <verb>`
# and the names live in that command, so the chain is followed instead
# of being restated here. The cadence is the timer's own, and the
# minimum window is taken against the SHIPPED value even though the
# operator can lower it: the shipped one is also the CEILING the
# command allows, so it is the slowest this producer can legitimately
# be, and a window sized for anything faster would go empty on a
# correctly configured instance.
SYSTEMD = pathlib.Path(os.environ["AEGIS_ROOT"]) / "share" / "systemd"
# Not JF_METRIC: these commands are python, and a series is emitted
# from an f-string, so the name is followed by `{{` (a literal brace),
# by the quote that closes the fragment, or by a space and a `{`
# placeholder. JF_METRIC recognises none of those three, and the first
# version of this block used it — it found nothing and reported that
# nobody produced what the rules read.
PY_METRIC = re.compile(r"\b(aegis_[a-z0-9_]+)(?=\{|['\"]|\s+[-+0-9$%{\"'(])")
for svc in sorted(SYSTEMD.glob("*.service")):
    txt = svc.read_text()
    if "/api/v1/import/prometheus" not in txt:
        continue
    timer = svc.with_suffix(".timer")
    m = re.search(r"^OnUnitActiveSec=(\d+)\s*(s|m|h)\s*$", timer.read_text(), re.M) \
        if timer.is_file() else None
    if not m:
        bad.append(f"{svc.name} pushes metrics and its timer declares no readable "
                   "OnUnitActiveSec: with no period there is no minimum window to "
                   "demand of whoever reads what it publishes")
        continue
    per = int(m.group(1)) * {"s": 1, "m": 60, "h": 3600}[m.group(2)]
    # Only the ExecStart* lines, and the whole verb chain. Reading the
    # unit's PROSE cost one iteration of this very check: a comment
    # that mentioned `aegis check` made it believe the timer published
    # that command's metrics too.
    for line in txt.splitlines():
        # The line that PIPES is the producer, not every line that runs
        # something. `ExecStart=aegis data backup` makes the bundle and
        # publishes nothing; attributing the command's whole catalogue
        # of series to it said four metrics were published every 24h
        # that in truth appear when an operator asks for them by hand.
        if not line.startswith("ExecStart") or "/api/v1/import/prometheus" not in line:
            continue
        for chain in re.findall(r"\baegis\s+((?:[a-z][a-z-]*\s+)*[a-z][a-z-]*)", line):
            parts = chain.split()
            cmd = pathlib.Path(os.environ["AEGIS_ROOT"]) / "libexec" / f"aegis-{parts[0]}"
            if not cmd.is_file():
                continue
            src = cmd.read_text()
            # The metrics of the VERB, not of the whole command. A file
            # like libexec/aegis-data emits series under several verbs
            # and this unit runs two of them: attributing the rest to
            # this timer would claim a metric is published every 24h
            # when in truth it appears when an operator asks for it by
            # hand. The verb chain names the function by the house's
            # own convention (`remote status` -> `remote_status`); when
            # nothing matches, the whole file is used and SAID so,
            # because a silent fallback would quietly restore the
            # over-attribution this comment exists to prevent.
            body, where = None, None
            for name in ("_".join(parts[1:]), parts[-1]):
                m = re.search(r"^def %s\(.*?(?=^def |\Z)" % re.escape(name),
                              src, re.S | re.M) if name else None
                if m:
                    body, where = m.group(0), f"{name}()"
                    break
            if body is None:
                body, where = src, "the whole command (no function matched the verb)"
            for met in set(PY_METRIC.findall(body)):
                producers.setdefault(met, (f"share/systemd/{svc.name} -> "
                                           f"libexec/aegis-{parts[0]} {where}",
                                           f"timer every {per}s", 2 * per))

# ── 3. the rules ────────────────────────────────────────────────────
cm = yaml.safe_load((OBS / "rules/vmalert-rules.yaml").read_text())
alerts = [(key, r["alert"], r["expr"])
          for key, body in cm["data"].items()
          for g in yaml.safe_load(body)["groups"]
          for r in g.get("rules", [])]

# ── 4. the dashboards and the provisioned datasources ───────────────
graf = yaml.safe_load((OBS / "grafana/values.yaml").read_text())
uids_ds = {ds["uid"] for ds in graf["datasources"]["datasources.yaml"]["datasources"]}
panels = []
n_dash = 0
for dash in sorted((OBS / "dashboards").glob("*.yaml")):
    n_dash += 1
    d = yaml.safe_load(dash.read_text())
    if d.get("metadata", {}).get("labels", {}).get("grafana_dashboard") != "1":
        bad.append(f"dashboards/{dash.name}: without the grafana_dashboard=1 label the sidecar "
                   "does not pick it up and the dashboard simply does not exist in Grafana")
    for name, raw in d["data"].items():
        j = json.loads(raw)
        if j.get("editable") is not False:
            bad.append(f"dashboards/{dash.name}: {name} does not declare editable:false "
                       "(design.md §4.1: none is born or changed by clicking)")
        for pan in j["panels"]:
            uid = pan.get("datasource", {}).get("uid")
            if uid not in uids_ds:
                bad.append(f"dashboards/{dash.name}: the panel {pan['title']!r} points at "
                           f"datasource {uid!r} and grafana/values.yaml does not provision it — "
                           "it renders empty forever, which is what green looks like")
            for t in pan.get("targets", []):
                panels.append((dash.name, pan["title"], t.get("expr", "")))
                # omitting it is legitimate (it inherits the panel's);
                # declaring ANOTHER sends the query to a store without
                # that series:
                own = t.get("datasource", {}).get("uid")
                if own is not None and own != uid:
                    bad.append(f"dashboards/{dash.name}: the panel {pan['title']!r} reads from "
                               f"{uid!r} and its query from {own!r}")

# ── 5. every alert that compares has an absence guard ───────────────
NO_GUARD = {
    "DeadmanAegis": "vector(1) does not depend on any series",
    "InquilinoAlLimiteDeMemoria":
        "zero organizations is day one's normal state; the tenant's disappearance is "
        "covered by SitioDeInquilinoSinSonda, which is the same family",
    "TargetDeScrapeCaido":
        "the disappearance of `up` as a whole is covered by JobDeScrapeDesaparecido",
    "JobDeScrapeDesaparecido":
        "it IS the guard: it counts discovered jobs instead of looking at values, which is "
        "exactly what absent() cannot do job by job",
    "KyvernoAdmisionRechazadaEnTenant":
        "increase() over a counter: with no rejections there is no series, and that IS "
        "health. The job's disappearance is covered by JobDeScrapeDesaparecido",
    "ImagenSinEscaneo":
        "the absence is day one: a newborn platform has no builds. An absent() here would "
        "scream from startup until the first build, which is the chronic false red. The "
        "«deployed and unmeasured» case is reported by aegis check, "
        "which knows how to cross it against what is running",
    "ImagenSinFirma": "same reason as ImagenSinEscaneo",
    "TrivyIgnoreExpiring":
        "zero exceptions is healthy: the metric legitimately vanishes. One series per "
        "trivyignore entry, and a file with no entries pushes none — an absent() here "
        "would page for the cleanest possible state",
    "BasePropagationFailed":
        "build-cadence, absent until the first base rebuild. Same family as "
        "ImagenSinEscaneo: the series is born with the first propagation, and a newborn "
        "platform has had none",
}
METRIC = re.compile(r"\b([a-z][a-z0-9_]+)\s*(?:\{|\[|\)|\s|$)")
WORDS = {"time", "sum", "max", "min", "avg", "count", "rate", "increase", "absent",
         "last_over_time", "max_over_time", "min_over_time", "avg_over_time",
         "vector", "by", "without", "and", "or", "unless", "topk", "bottomk",
         "clamp_max", "clamp_min", "on", "ignoring", "group_left", "group_right"}

def metrics_of(expr):
    return {m for m in METRIC.findall(re.sub(r"\{[^}]*\}", " ", expr))
            if m not in WORDS and not re.fullmatch(r"\d+[a-z]", m)}

def subjects_of(expr):
    """What an expr measures: its metrics AND the jobs it filters on.

    Both count, because the guard may be placed on a SISTER metric of
    the same job: if blackbox stops probing the registry, probe_success
    and probe_ssl_earliest_cert_expiry disappear TOGETHER, so an
    absent() over the first protects the second. Demanding the same
    metric would be asking for one alert per series, and nobody can
    sustain that — a check that asks for the unsustainable gets switched
    off.
    """
    return metrics_of(expr) | {v for _, v in re.findall(r'job\s*(=~|=)\s*"([^"]+)"', expr)}

guards = {}
for fname, name, expr in alerts:
    for a in re.findall(r"absent\(([^)]*(?:\)[^)]*)*?)\)", expr):
        guards.setdefault(fname, set()).update(subjects_of(a))
for fname, name, expr in alerts:
    if "absent(" in expr or name in NO_GUARD:
        continue
    if not re.search(r"(==|!=|>=|<=|>|<)", expr):
        continue
    subj = subjects_of(expr)
    if not subj & guards.get(fname, set()):
        bad.append(f"the alert {name} ({fname}) compares against a value and no alert in "
                   f"its file guards with absent() anything it measures ({sorted(subj)}): "
                   "if the series disappears it does not go false, it goes empty, and empty does not fire")
declared = {n for _, n, _ in alerts}
for name in NO_GUARD:
    if name not in declared:
        bad.append(f"the declared exception for {name} no longer has a subject: that alert does "
                   "not exist. Delete it from NO_GUARD or fix the name")

# ── 6/7. the own metrics: read ↔ produced ───────────────────────────
read_metrics = set()
for fname, name, expr in alerts:
    read_metrics |= {m for m in metrics_of(expr) if m.startswith("aegis_")}
for dash, title, expr in panels:
    read_metrics |= set(re.findall(r"\b(aegis_[a-z0-9_]+)\b", expr))
for m in sorted(read_metrics - set(producers)):
    bad.append(f"the metric {m} is read in rules or panels and NOBODY in the tree produces it: "
               "the panel stays empty and the alert never fires")
for m in sorted(set(producers) - read_metrics):
    bad.append(f"the metric {m} is produced by {producers[m][0]} and is read by neither a rule "
               "nor a panel: it is paid for and nobody looks at it")

# ── 8. sparse metric: always with a window of ≥ 2 periods ───────────
SECS = {"s": 1, "m": 60, "h": 3600, "d": 86400}
readers = ([(f"the alert {n}", e) for _, n, e in alerts]
           + [(f"the panel {t!r} of {d}", e) for d, t, e in panels])
for m, (src, cadence, minimum) in sorted(producers.items()):
    for where, expr in readers:
        if m not in expr:
            continue
        window = re.findall(rf"last_over_time\(\s*{m}[^)]*\[(\d+)([smhd])\]", expr)
        if not window:
            bad.append(f"{where} reads {m} without last_over_time: {src} pushes it {cadence} and "
                       "an instant query's default window is shorter — the query falls "
                       "between two pushes and returns empty")
            continue
        for n, u in window:
            if int(n) * SECS[u] < minimum:
                bad.append(f"{where}: the window [{n}{u}] does not reach the minimum of "
                           f"{minimum}s for a metric that {src} pushes {cadence} — "
                           "one late push and the series disappears from the query")

# ── 9. every cited job exists ───────────────────────────────────────
for where, expr in readers:
    for op, val in re.findall(r'job\s*(=~|=)\s*"([^"]+)"', expr):
        if op == "=" and val not in jobs:
            bad.append(f'{where} filters job="{val}" and vmagent does not declare that job_name: '
                       "the query returns nothing, and it will not say so")
        if op == "=~" and not any(re.fullmatch(val, j) for j in jobs):
            if any(re.fullmatch(val, g) for g in derivable):
                continue      # no subject TODAY; it will have one with the 1st organization
            bad.append(f'{where} filters job=~"{val}": no vmagent job_name matches '
                       "and it is not a pattern aegis-org knows how to derive either")

# ── 10. the baked-in threshold is derived, not remembered ───────────
# Guarded against the alert simply not being there: a loop over zero
# matches compares nothing and passes, which is the blindness this
# check exists to prevent (the NO_GUARD table above names the same
# alert; fixing one occurrence and not this one left it measuring nothing).
# The jobs that DO NOT EXIST on a given edge. Declared here, next to the
# other tables of this check, because nothing in a manifest says it: the
# `cloudflared` job scrapes a Deployment that EDGE=local never installs,
# and a job that discovers no targets does not produce up==0 — it
# produces nothing, so the count simply comes out one lower.
JOBS_ABSENT_ON = {"local": {"cloudflared"}, "cloudflare": set()}

threshold_seen = False
for fname, name, expr in alerts:
    if name != "JobDeScrapeDesaparecido":
        continue
    threshold_seen = True
    ph = "__OBS_SCRAPE_JOBS_MIN__"
    if ph in expr:
        # The floor is a placeholder, so what is verified is its OWNER:
        # the two numbers lib/common.sh derives have to be the ones
        # vmagent's job list actually produces on each edge. Reading the
        # literal would have been reading a number nobody renders.
        owner = (P.parent.parent/"lib"/"common.sh") if (P.parent.parent/"lib"/"common.sh").exists() \
                else pathlib.Path(os.environ["AEGIS_ROOT"])/"lib"/"common.sh"
        body = owner.read_text()
        m2 = re.search(r"_obs_scrape_jobs_min\(\)\s*\{(.*?)\n\}", body, re.S)
        if not m2:
            bad.append("the floor of JobDeScrapeDesaparecido is a placeholder and "
                       "lib/common.sh does not derive it: nobody renders that number")
        else:
            derived = dict(re.findall(r"(local|\*)\)\s*echo\s+(\d+)", m2.group(1)))
            for edge, key in (("local", "local"), ("cloudflare", "*")):
                want = len(jobs_base) - len(JOBS_ABSENT_ON[edge] & set(jobs_base))
                got = derived.get(key)
                if got is None:
                    bad.append(f"lib/common.sh does not derive the floor for edge {edge}")
                elif int(got) != want:
                    bad.append(f"the floor of JobDeScrapeDesaparecido for edge {edge} is {got} "
                               f"and vmagent declares {want} jobs there: the threshold went "
                               "stale, so on that edge it either screams every day or covers "
                               "up a lost job")
    else:
        m = re.search(r"<\s*(\d+)", expr)
        if not m:
            bad.append("JobDeScrapeDesaparecido stopped comparing against a number of jobs")
        elif int(m.group(1)) != len(jobs_base):
            bad.append(f"JobDeScrapeDesaparecido expects {m.group(1)} jobs and vmagent declares "
                       f"{len(jobs_base)} platform ones: the threshold went stale, so it either "
                       "screams too much or covers up a lost job")
if not threshold_seen:
    bad.append("the alert JobDeScrapeDesaparecido is gone: nothing compares the number of "
               "scrape jobs against vmagent any more, and a lost job goes unnoticed")

# ── 11. hot reload and the rollout strategy ─────────────────────────
if vmag.get("extraArgs", {}).get("promscrape.configCheckInterval") is None:
    bad.append("vmagent without promscrape.configCheckInterval: the probe aegis-org derives "
               "stays written in the ConfigMap and nobody scrapes it")
if vmag.get("deployment", {}).get("spec", {}).get("strategy", {}).get("type") != "Recreate":
    bad.append("vmagent without deployment.spec.strategy.type=Recreate: its buffer is an RWO "
               "PVC with an exclusive lock and the new pod goes into CrashLoop against the old one")
vmal = yaml.safe_load((OBS / "vmalert/values.yaml").read_text())
if vmal["server"].get("extraArgs", {}).get("configCheckInterval") is None:
    bad.append("vmalert without configCheckInterval: a rule committed and synced is NOT "
               "loaded until somebody restarts the pod for some other reason")

print(f"    {len(jobs)} scrape jobs ({len(jobs_base)} platform + {len(derived)} "
      f"derived), {len(alerts)} alerts in {len(cm['data'])} families, "
      f"{len(panels)} queries in {n_dash} dashboards, "
      f"{len(producers)} own metrics", file=sys.stderr)
for m in bad:
    print(f"    {m}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D92" ]]; then fail "the watch does not hold itself up:$D92"
else pass "rules, metrics, jobs and panels cross with no gaps: no alert compares without an absence guard, no query points at a job or a datasource that does not exist, and both hot reloads are declared"; fi
}
