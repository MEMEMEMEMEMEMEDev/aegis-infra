# teeth of check 181 — an environment variable a manifest sets is a
# name the code it configures really reads.
#
# The first two reds are the exact spellings production carried until
# 2026-09-02.

_181_ren() { python3 - "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-cpu.yaml" "$1" "$2" <<'PYEOF'
import sys
p, viejo, nuevo = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert s.count(viejo) == 1, (viejo, s.count(viejo))
open(p, "w", encoding="utf-8").write(s.replace(viejo, nuevo, 1))
PYEOF
}

# the weights: three of four lanes could not find them, and the pod
# still came up Ready.
red_1() { _181_ren "AEGIS_MODELOS_CPU" "AEGIS_CPU_MODELS"; }

# the world: the engine announced itself as the LOCAL lane, without
# signature, quota or tenant, while running inside the cluster.
red_2() { _181_ren "AEGIS_EN_CLUSTER" "AEGIS_IN_CLUSTER"; }

# a new setting nobody wired: the shape of the defect arriving fresh
# rather than by translation.
red_3() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-cpu.yaml" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '            - {name: AEGIS_WHISPER, value: /models/whisper-small}\n'
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(
    s.replace(anchor, anchor + '            - {name: AEGIS_THREADS_EAR, value: "4"}\n', 1))
PYEOF
}

# control: a THIRD PARTY's variable that our code does not mention.
# HF_HUB_OFFLINE is honoured inside a library this check cannot see, and
# a check that demanded our source name it would turn a correct
# manifest red.
control_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-cpu.yaml" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '            - {name: HF_HUB_OFFLINE, value: "1"}\n'
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(
    s.replace(anchor, anchor + '            - {name: TOKENIZERS_PARALLELISM, value: "false"}\n', 1))
PYEOF
}

# control: the PROSE of the manifest naming a variable. A comment is
# not a setting, and the parser is what keeps them apart.
control_2() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-cpu.yaml" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '            - {name: AEGIS_WHISPER, value: /models/whisper-small}\n'
assert s.count(anchor) == 1
nota = ('            # note: AEGIS_CPU_MODELS was the dead spelling of\n'
        '            # AEGIS_MODELOS_CPU, and AEGIS_IN_CLUSTER of AEGIS_EN_CLUSTER.\n')
open(p, "w", encoding="utf-8").write(s.replace(anchor, nota + anchor, 1))
PYEOF
}
