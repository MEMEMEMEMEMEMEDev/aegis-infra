# teeth of check 189 — the app scan honors a repo-local trivyignore,
# guarded and without softening the bar.
_TPL="$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"

# THE STATE THE ARTIFACT WAS IN until 2026-09-04: no ignorefile at all,
# so a base-layer CVE the platform already accepted refused the build.
red_1() { sed -i 's/--ignorefile trivyignore.yaml/--nothing-here/' "$_TPL"; }

# present but never handed to trivy: the flag is gone from the command.
red_2() {
    python3 - "$_TPL" <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = s.replace("                  --no-progress \\\n                  $IGN", "                  --no-progress")
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# the guard is gone: an app with no trivyignore.yaml would break or the
# flag would always be passed.
red_3() { sed -i 's/if \[ -f trivyignore.yaml \]; then/if true; then/' "$_TPL"; }

# the bar is softened alongside: severities dropped to CRITICAL only.
red_4() { sed -i 's/--severity CRITICAL,HIGH/--severity CRITICAL/' "$_TPL"; }

# control: PROSE naming trivyignore.yaml, --ignorefile and the guard, in
# the file that implements it. The scanner strips comments first.
control_1() {
    python3 - "$_TPL" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
anchor = "    stage('scan') {\n"
nota = "    // note: honors a repo-local trivyignore.yaml via --ignorefile, guarded by [ -f trivyignore.yaml ]. See check 189.\n"
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, nota + anchor, 1))
PYEOF
}

# control: a second, unrelated stage comment mentioning trivy — noise the
# scanner must not read as the scan command changing.
control_2() {
    python3 - "$_TPL" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
anchor = "    stage('push') {\n"
nota = "    // note: the scan (trivyignore.yaml, --ignorefile) ran before this.\n"
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, nota + anchor, 1))
PYEOF
}
