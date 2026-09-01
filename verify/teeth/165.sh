# teeth of check 165 — a build that signs declares what it pushed, in
# the form the platform reads.

# THE STATE THE ARTIFACT WAS IN until 2026-09-01: the AI lanes printed
# the event WITHOUT the marker. The JSON was right there in the console
# and reached nothing — not the audit store, not the dashboard.
red_1() {
    sed -i "s/printf 'AEGIS_EVENT {\"event\"/printf '{\"event\"/" \
        "$AEGIS_ROOT/seed/platform/ai/engine-cpu/Jenkinsfile"
}

# the same on the GPU lane, whose build is the four-hour one: losing
# the record of THAT one costs the most.
red_2() {
    sed -i "s/printf 'AEGIS_EVENT {\"event\"/printf '{\"event\"/" \
        "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Jenkinsfile"
}

# the pipeline every application in every organization derives from.
red_3() {
    python3 - "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("AEGIS_EVENT %s", "SUPPLY_CHAIN %s")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the phase composing the tag again instead of reading what the build
# declared: two places deciding the same thing, and the lanes do not
# name their tags the same way.
red_4() {
    sed -i 's/jenkins_build_event/jenkins_build_evento/' \
        "$AEGIS_ROOT/init/phases/87-ai.sh"
}

# control: the marker is DERIVED from vector, so prose naming it is
# not a declaration and must not stand in for one. Adding a comment to
# a pipeline that already declares it changes nothing.
control_1() {
    printf '\n// note: the report stage emits AEGIS_EVENT for the audit store.\n' \
        >> "$AEGIS_ROOT/seed/platform/ai/engine-cpu/Jenkinsfile"
}

# control: a protocol document that shows `cosign sign` in an example
# is not a pipeline and is not asked to declare anything. Accusing the
# documentation of the code's obligation is the trap checks 161 and
# 163 were both corrected for.
control_2() {
    printf '\n```sh\ncosign sign --key cosign.key example@sha256:0\n```\n' \
        >> "$AEGIS_ROOT/seed/platform/docs/protocols/images.md"
}
