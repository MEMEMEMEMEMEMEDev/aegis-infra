# teeth for check 139 (job-dsl: one job per item, the jobs named, the cron there)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# The `>` fold: two pipelineJob in one item become a chained call and
# no job is born. The rest are the ways the watch stops being daily.
JV="seed/platform/k8s/base/platform/jenkins/values.yaml"

# base-images and image-watch fold into ONE item: Groovy reads
# `} pipelineJob('image-watch')` as a chained call and throws
red_1() {
    python3 - "$AEGIS_ROOT/$JV" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
# drop the `- script: >` line (and the comment block before it) that
# opens the image-watch item, so its body continues the previous item
n = re.subn(r"\n(?:          #[^\n]*\n)*          - script: >\n(?=              pipelineJob\('image-watch'\))", "\n", t, count=1)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# the cron line disappears: the watch runs once at birth and never again
red_2() {
    python3 - "$AEGIS_ROOT/$JV" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^\s*cron\('H 6 \* \* \*'\)\n", "", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# the job renamed: phase 85 fires `image-watch` by name and gets a 404
red_3() {
    python3 - "$AEGIS_ROOT/$JV" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "pipelineJob('image-watch')"
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "pipelineJob('images-watch')", 1))
PY
}
# control: what the operator sees in the list is not the contract
control_1() {
    python3 - "$AEGIS_ROOT/$JV" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "displayName('mirror-images (third parties: pull + scan + sign)')"
assert old in t
open(p, "w").write(t.replace(old, "displayName('mirror-images (third-party images)')", 1))
PY
}
