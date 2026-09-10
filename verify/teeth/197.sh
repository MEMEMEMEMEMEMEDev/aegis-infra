# teeth of check 197 — no engine sizes a thread pool larger than the
# CPU limit it runs under, and the GPU lanes still take turns.

# THE STATE THAT WAS MEASURED, in the form it would come back: a pool
# sized for the machine instead of for the cgroup. On 2026-09-09 the
# live engine-cpu ran a budget written for 32 threads inside a
# container limited to 6, with sixty threads in the process and `nproc`
# cheerfully answering 32.
red_1() {
    sed -i 's|- {name: OMP_NUM_THREADS, value: "1"}|- {name: OMP_NUM_THREADS, value: "32"}|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-cpu.yaml"
}

# the cap that matters for MEMORY and not only for CPU: on a cold
# torch.compile, inductor forks one worker per thread and each imports
# torch. Thirty-two of those arrive in the same minute the engines are
# reading their weights.
red_2() {
    sed -i 's|- {name: TORCHINDUCTOR_COMPILE_THREADS, value: "6"}|- {name: TORCHINDUCTOR_COMPILE_THREADS, value: "32"}|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-llm.yaml"
}

# THE DRIFT DIRECTION NOBODY WATCHES: the limit comes down and the caps
# stay where they were. Both halves still look reasonable on their own,
# which is exactly why this is the one that rots.
red_3() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-mt.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'(limits:\n(?:\s+\w[\w.]*: [^\n]*\n)*?\s+)cpu: "6"', r'\1cpu: "2"', s)
open(p, "w", encoding="utf-8").write(s)
PY
}

# the turn deleted. The GPU lanes reserve their KV cache once and for
# good; two of them measuring free VRAM in the same instant is how a
# cache comes out permanently small.
red_4() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-mt.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("        - name: wait-for-turn\n", "        - name: espera-un-rato\n")
open(p, "w", encoding="utf-8").write(s)
PY
}

# a turn that waits for nothing: still there, still named, and no
# longer naming anybody. Worse than absent, because it looks present.
red_5() {
    sed -i 's|http://engine-llm.ai-system.svc.cluster.local:8000/health|http://localhost:8000/health|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-mt.yaml"
}

# and the check's own subject taken away: with no cap declared
# anywhere, finding no oversubscription must NOT read as everything
# fine. The shape of the bug found in check 004 on 2026-08-29.
red_6() {
    for f in engine-cpu engine-llm engine-mt; do
        sed -i '/OMP_NUM_THREADS\|MKL_NUM_THREADS\|TORCHINDUCTOR_COMPILE_THREADS/d' \
            "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/$f.yaml"
    done
}

# control: the limit and its caps raised TOGETHER. That is the
# legitimate change this check exists to keep possible, and it has to
# stay green.
control_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-llm.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'(limits:\n(?:\s+\w[\w.]*: [^\n]*\n)*?\s+)cpu: "6"', r'\1cpu: "8"', s)
s = s.replace('- {name: TORCHINDUCTOR_COMPILE_THREADS, value: "6"}',
              '- {name: TORCHINDUCTOR_COMPILE_THREADS, value: "8"}')
s = s.replace('- {name: OMP_NUM_THREADS, value: "6"}',
              '- {name: OMP_NUM_THREADS, value: "8"}')
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: one more cap, declared at a legal value. Growing the budget
# has to stay green.
control_2() {
    sed -i 's|- {name: MKL_NUM_THREADS, value: "1"}|- {name: MKL_NUM_THREADS, value: "1"}\n            - {name: OPENBLAS_NUM_THREADS, value: "1"}|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-cpu.yaml"
}

# control: PROSE naming a cap without setting one. The manifests
# explain these variables at length now, and an explanation must not
# be read as a declaration.
control_3() {
    sed -i 's|^      containers:$|      # a legitimate note: OMP_NUM_THREADS and\n      # TORCHINDUCTOR_COMPILE_THREADS are set per container below.\n      containers:|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/gateway.yaml"
}
