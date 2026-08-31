# teeth of check 159 — the three numbers of a lane say the same thing.
# One red per number, on both lanes, because a check that only read one
# lane would be a check that only reads the lane it was written on.

# THE MODEL, which is the expensive one: the gateway asks by name and
# the engine serves another. Every request fails at the engine with a
# model nobody serves, and each manifest reads perfectly well alone.
red_1() {
    sed -i 's/^  SERVED_NAME: "qwen3-4b"$/  SERVED_NAME: "qwen3-4b-instruct"/' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-llm.yaml"
}
red_2() {
    sed -i 's/^  SERVED_NAME: "hy-mt2-1.8b"$/  SERVED_NAME: "hy-mt2"/' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-mt.yaml"
}

# IN FLIGHT: the gateway admits more than the engine accepts, so the
# surplus queues INSIDE the engine where the gateway cannot see it and
# the wait it reports stops being the wait there is.
red_3() {
    sed -i 's/^  MAX_NUM_SEQS: "10"$/  MAX_NUM_SEQS: "4"/' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-llm.yaml"
}

# CONTEXT: the routing promises more than the engine accepts — a 400
# the caller can do nothing about.
red_4() {
    sed -i 's/^  MAX_MODEL_LEN: "12288"$/  MAX_MODEL_LEN: "4096"/' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-llm.yaml"
}

# A LANE THE GATEWAY DECLARES AND NO ENGINE SERVES. The check has to
# watch the class: a fourth lane added tomorrow is measured without
# touching it.
red_5() {
    sed -i 's|- {name: AI_MODELO_MT, value: "hy-mt2-1.8b"}|- {name: AI_MODELO_MT, value: "hy-mt2-1.8b"}\n            - {name: AI_MODELO_XL, value: "un-modelo-sin-motor"}|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/gateway.yaml"
}

# and the check's own subject taken away: with no AI_MODELO_* to derive
# a lane from, finding no disagreement must NOT be reported as
# agreement. The shape of the bug found in check 004 on 2026-08-29.
red_6() {
    sed -i 's/AI_MODELO_/AI_MODEL_/g' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/gateway.yaml"
}

# control: a context LARGER than the routing promises is legitimate —
# the engine accepting more than it is asked for breaks nothing.
control_1() {
    sed -i 's/^  MAX_MODEL_LEN: "12288"$/  MAX_MODEL_LEN: "16384"/' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-llm.yaml"
}

# control: prose about the numbers is not a number.
control_2() {
    printf '\n# note: these three move together.\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-llm.yaml"
}
