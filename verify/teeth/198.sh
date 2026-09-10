# teeth of check 198 — the VRAM threshold derives the number of engines
# from the same manifests as their fractions.

# THE REGRESSION THAT WAS MEASURED, run backwards: put the count back
# where it was on 2026-09-09, in the ENGINES constant, while the
# fraction keeps coming from the manifests. That was the artifact's
# real state, in the very file whose opening comment warns against
# exactly this, and no check saw it.
red_1() {
    python3 - "$AEGIS_ROOT/libexec/aegis-ai" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("int('$derived'), int('$VLLM_OVERSHOOT_MIB')",
              "int('$declared'), int('$VLLM_OVERSHOOT_MIB')")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the other half of the same defect: the sum function stops reporting
# how many it summed, so the caller has nowhere to read the count from
# but a constant.
red_2() {
    sed -i 's|print(f"{total:.4f} {seen}")|print(f"{total:.4f}")|' \
        "$AEGIS_ROOT/libexec/aegis-ai"
}

# ENGINES keeps being counted, but nobody audits the claim any more:
# the list and the manifests may disagree in silence, and the threshold
# is computed from an assertion nobody checked. This is the shape of
# tomorrow's defect — the arithmetic looks derived and the guard is
# gone.
red_3() {
    python3 - "$AEGIS_ROOT/libexec/aegis-ai" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'\n  if \[ "\$declared" -ne "\$derived" \].*?\n  fi\n', "\n", s, flags=re.S)
open(p, "w", encoding="utf-8").write(s)
PY
}

# the count is neither the constant nor the manifests' — it is written
# down again, which is where the whole story started.
red_4() {
    sed -i "s|int('\$derived'), int('\$VLLM_OVERSHOOT_MIB')|int('2'), int('\$VLLM_OVERSHOOT_MIB')|" \
        "$AEGIS_ROOT/libexec/aegis-ai"
}

# and the check's own subject taken away: with the function renamed,
# finding no bad arithmetic must NOT be reported as everything fine.
# The shape of the bug found in check 004 on 2026-08-29.
red_5() {
    sed -i 's|^vram_limit_mib() {|vram_umbral_mib() {|' \
        "$AEGIS_ROOT/libexec/aegis-ai"
}

# control: a comment inside the very function under test. The check
# reads structure, not mentions — a line explaining the arithmetic must
# not be able to change the verdict.
control_1() {
    sed -i 's|^vram_limit_mib() {|vram_limit_mib() {\n  # a legitimate note about the arithmetic below|' \
        "$AEGIS_ROOT/libexec/aegis-ai"
}

# control: `wc -w` over ENGINES somewhere ELSE in the file. Counting
# the fleet to print it is legitimate; what is forbidden is feeding
# that count into the threshold. A check that bites this is reading the
# file instead of the function.
control_2() {
    printf '\nfleet_size() { echo $ENGINES | wc -w; }\n' \
        >> "$AEGIS_ROOT/libexec/aegis-ai"
}

# control: a third engine added to BOTH halves at once — the list and
# a manifest that declares its fraction. That is the legitimate change
# this whole check exists to keep possible, and it has to stay green.
control_3() {
    sed -i 's|^ENGINES="engine-llm engine-mt"|ENGINES="engine-llm engine-mt engine-vision"|' \
        "$AEGIS_ROOT/libexec/aegis-ai"
    cat > "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-vision.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: engine-vision-profile
  namespace: ai-system
data:
  GPU_MEM_UTIL: "0.10"
YAML
}
