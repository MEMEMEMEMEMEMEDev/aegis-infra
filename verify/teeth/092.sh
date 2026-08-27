# teeth for check 092 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.
# Extended 2026-08-27 (red_1 re-aimed, red_5 and control_2 added) and
# re-VERIFIED on both profiles: 5/5 bite, 2/2 controls healthy.

# the subject disappears: if the check does not notice, it was not reading it.
# Since 2026-08-27 aegis_build_* has THREE producers (the tenant
# template, mirror-images and base-images), so the metric only goes
# orphan when all three are gone: taking one away is a legitimate
# state, not a hole.
red_1() {
    rm -f "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app" \
          "$AEGIS_ROOT/seed/platform/mirror-images/Jenkinsfile" \
          "$AEGIS_ROOT/seed/platform/base-images/Jenkinsfile"
}

# The alert whose threshold §10 verifies disappears. Before 2026-08-26
# the loop over zero matches compared nothing and passed; now the guard
# has to name the absence.
red_2() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"          - alert: JobDeScrapeDesaparecido\n(?:            .*\n|              .*\n)+", "", t)
assert n[1] == 1, n[1]
open(p, "w").write(n[0])
PY
}

# The floor of JobDeScrapeDesaparecido drifts on ONE edge only. It is
# the comfortable kind: everything renders, everything is green, and on
# the profile nobody is looking at, the alert either cries wolf every
# day or covers up a job that really did get lost.
red_3() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "        local) echo 11 ;;"
assert old in t
open(p, "w").write(t.replace(old, "        local) echo 12 ;;", 1))
PY
}

# The owner of the floor disappears: the rule keeps carrying a
# placeholder that nobody renders any more, so the alert ships with a
# literal `__OBS_SCRAPE_JOBS_MIN__` where a number should be.
red_4() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"_obs_scrape_jobs_min\(\) \{.*?\n\}\n", "", t, count=1, flags=re.S)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}

# control: adding a scrape job to vmagent AND moving the floor with it
# is exactly what somebody extending the platform must be able to do.
control_1() {
    python3 - "$AEGIS_ROOT" <<'PY'
import sys, pathlib
r = pathlib.Path(sys.argv[1])
v = r/"seed/platform/k8s/base/observability/vmagent/values.yaml"
t = v.read_text()
anchor = "    - job_name: vmagent\n"
assert t.count(anchor) == 1
v.write_text(t.replace(anchor, anchor + "    - job_name: aegis-tooth-extra\n      static_configs:\n        - targets: ['127.0.0.1:9999']\n", 1))
c = r/"lib/common.sh"
s = c.read_text()
s = s.replace("        local) echo 11 ;;", "        local) echo 12 ;;", 1)
s = s.replace("        *)     echo 12 ;;", "        *)     echo 13 ;;", 1)
c.write_text(s)
PY
}

# image-watch loses its cron in the job-dsl while images.yaml goes on
# reading its metrics with [2d]: the producer is now build-class (a
# week's floor) and every two-day window falls short. That is the hole
# in its exact shape — the watch stopped being daily and nobody told
# the rules.
red_5() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^\s*cron\('H 6 \* \* \*'\)\n", "", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# control: moving the watch an hour earlier is still daily
control_2() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "cron('H 6 * * *')"
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "cron('H 5 * * *')", 1))
PY
}
