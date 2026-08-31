# teeth of check 158 — every pipeline the seed ships has a job that
# fires it, and every job names a pipeline that exists.

# THE REGRESSION THAT WAS MEASURED, run backwards: take the GPU
# engine's job out of the job-dsl and its Jenkinsfile goes back to
# being a build definition nobody can trigger. That was the artifact's
# real state on 2026-08-30, and no check saw it.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("scriptPath('ai/engine-gpu/Jenkinsfile')", "scriptPath('ai/engine-gpu/Otro')")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the same defect on the CPU lane, so the check is not reading one name.
red_2() {
    sed -i "s|scriptPath('ai/engine-cpu/Jenkinsfile')|scriptPath('ai/engine-cpu/Nope')|" \
        "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml"
}

# a NEW pipeline that arrives with no job: the check has to watch the
# CLASS and not the two cases it already knows. This is the shape of
# tomorrow's defect, not yesterday's.
red_3() {
    mkdir -p "$AEGIS_ROOT/seed/platform/future-tool"
    printf 'pipeline { agent any; stages { stage("x") { steps { sh "true" } } } }\n' \
        > "$AEGIS_ROOT/seed/platform/future-tool/Jenkinsfile"
}

# the other direction, which rots without anybody looking: the seed
# stops shipping a pipeline and the job that named it stays.
red_4() { rm -f "$AEGIS_ROOT/seed/platform/image-watch/Jenkinsfile"; }

# and the check's own subject taken away: with no job-dsl readable,
# finding no pipeline fired must NOT be reported as everything fine.
# The shape of the bug found in check 004 on 2026-08-29.
red_5() {
    sed -i 's/^        jobs:$/        trabajos:/' \
        "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml"
}

# the third half, the one libexec/aegis-ai names this check by number
# for: a row of AI_CONTAINERFILES pointing at a directory the seed does
# not ship. It fails at build time otherwise, which is late and reads
# like a registry problem.
red_6() {
    sed -i 's|^AI_CONTAINERFILES=.*|AI_CONTAINERFILES="ai/engine-gpu/Containerfile ai/engine-tpu/Containerfile"|' \
        "$AEGIS_ROOT/libexec/aegis-ai"
}

# control: the template the tenants derive is NOT swept — it is born
# from a contract and not from the seed's job-dsl, and biting it would
# be biting the wrong thing.
control_1() {
    printf '\n// a legitimate note\n' \
        >> "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"
}

# control: another item in the job-dsl that fires nothing of the seed
# (a tenant multibranch has no scriptPath) cannot turn it red.
control_2() {
    printf '\n# a legitimate comment\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml"
}
