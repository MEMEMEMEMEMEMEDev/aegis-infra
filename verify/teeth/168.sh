# teeth of check 168 — a build that installs OS packages does not run
# through the container exec API.

# THE STATE THE ARTIFACT WAS IN on 2026-09-01: the GPU lane built
# through container('kaniko'){ sh }, and every attempt died with
# «permission denied» after the apt RUN had printed its whole output.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Jenkinsfile" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("""        sh '''
          set -eu
          W=/home/jenkins/agent""",
              """        container('kaniko') {
        sh '''
          set -eu
          W=/home/jenkins/agent""", 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# the builder goes back to being something you exec into: no arguments
# file means the measured arrangement is gone even if nobody wrote
# container('kaniko') anywhere.
red_2() {
    sed -i 's/kaniko\.args/kaniko.parametros/g' \
        "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Jenkinsfile"
}

# a Containerfile that installs packages with no pipeline beside it:
# nothing in the artifact says how it is built, so nothing can
# guarantee it is built the way that works.
red_3() {
    mkdir -p "$AEGIS_ROOT/seed/platform/ai/engine-tpu"
    printf 'FROM __FROM_PYTHON__\nRUN apt-get update && apt-get install -y --no-install-recommends less\n' \
        > "$AEGIS_ROOT/seed/platform/ai/engine-tpu/Containerfile"
}

# the scanner broken: a scan that dies must take the check with it,
# never wave it through (the lesson check 166 paid for).
red_4() {
    printf '\nraise SystemExit("the scanner is broken")\n' \
        >> "$AEGIS_ROOT/verify/checks/168.py"
}

# control: THE PROSE that explains the fix names the shape it forbids
# — the comment above the kaniko container says exactly
# «container('kaniko'){ sh }». The first version of this check read
# that as the defect. Seventh time in one day, and the reason the scan
# strips comments in both languages.
control_1() {
    printf '\n// note: never container(\x27kaniko\x27){ sh } for a build that installs packages.\n' \
        >> "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Jenkinsfile"
}

# control: a Containerfile that installs nothing is not subject to
# this rule, and adding one must not turn the check red.
control_2() {
    mkdir -p "$AEGIS_ROOT/seed/platform/ai/engine-sin-paquetes"
    printf 'FROM __FROM_PYTHON__\nRUN pip install --no-cache-dir packaging\n' \
        > "$AEGIS_ROOT/seed/platform/ai/engine-sin-paquetes/Containerfile"
}
