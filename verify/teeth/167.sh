# teeth of check 167 — the base of an AI lane is resolved before its
# build, and the guard reads the FROM.

# THE STATE THE ARTIFACT WAS IN on 2026-09-01: the guard grepped the
# WHOLE file, and the file documents its own placeholder in a comment
# above the FROM. The lane was unbuildable whether or not anybody had
# resolved anything.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Jenkinsfile" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("grep -E '^[[:space:]]*FROM[[:space:]]' ai/engine-gpu/Containerfile | grep -q '__FROM_'",
              "grep -q '__FROM_' ai/engine-gpu/Containerfile", 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# the twin, which until today carried no guard at all — one lane
# protected and the other not is the asymmetry that produced the
# reserved-word bug too.
red_2() {
    python3 - "$AEGIS_ROOT/seed/platform/ai/engine-cpu/Jenkinsfile" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r"\n    stage\('base-is-mirrored'\).*?\n    \}\n", "\n", s, count=1, flags=re.S)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# the precondition that is not one: resolving AFTER the first build.
red_3() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('run_cmd "$AEGIS_ROOT/libexec/aegis-ai" bases\n', '', 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# an error that names a command the CLI does not dispatch costs the
# reader exactly what no error costs: the first version pointed at
# `aegis ai images`, which by then only reported.
red_4() {
    sed -i 's/echo "  aegis ai bases"/echo "  aegis ai imagenes"/' \
        "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Jenkinsfile"
}

# control: THE COMMENT that explains the placeholder is the very thing
# the old guard tripped on. It must stay harmless — the whole point.
control_1() {
    printf '\n# `__FROM_PYTHON__` is resolved before building; see aegis ai bases.\n' \
        >> "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Containerfile"
}

# control: the phase's prose cites jenkins_build_retry to explain the
# shape of the step. Counting that as the first build is how this
# check accused itself on its first run.
control_2() {
    printf '\n# note: the shape is the one of jenkins_build_retry in phase 50.\n' \
        >> "$AEGIS_ROOT/init/phases/87-ai.sh"
}
