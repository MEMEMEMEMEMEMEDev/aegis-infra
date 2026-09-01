# teeth of check 163 — nobody uses the secrets tmpfs before opening it,
# and the libraries say so.

# THE STATE THE ARTIFACT WAS IN on 2026-09-01: phase 87 opened the
# tmpfs in 87.3 and fired Jenkins in 87.1a. Put it back where it was
# and the bug is back, exactly: 401 reported as a missing job.
red_1() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("secrets_workdir\n\n# ── 87.1 the images", "\n# ── 87.1 the images", 1)
s = s.replace('REG_HOST="$REGISTRY_HOST_INTERNAL"',
              'secrets_workdir\nREG_HOST="$REGISTRY_HOST_INTERNAL"', 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

# a phase that talks to Jenkins and never opens the tmpfs at all.
red_2() {
    sed -i '0,/^secrets_workdir/{/^secrets_workdir/d}' \
        "$AEGIS_ROOT/init/phases/50-jenkins.sh"
}

# the same, in the phase that carries the supply chain.
red_3() {
    python3 - "$AEGIS_ROOT/init/phases/80-supply-chain.sh" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
out = [l for l in lines if l.strip() != "secrets_workdir"]
out.append("\nsecrets_workdir\n")          # opened, but at the very end
open(p, "w", encoding="utf-8").writelines(out)
PY
}

# the precondition unsaid: the library builds a path out of the empty
# string and the error surfaces three frames away, as somebody else's
# 401. This is the mutation that keeps the DISTANCE short.
red_4() {
    python3 - "$AEGIS_ROOT/lib/jenkins.sh" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'^\s*:\s*"\$\{SECRETS_TMP:\?[^\n]*\n', '', s, count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
PY
}

# control, and it is the one this check was born owing: PROSE naming a
# helper is not a call. The first version read the comment of gate_diag
# — «the diagnosis may use functions from the libs (jenkins_get, etc.)»
# — as a dependency and accused phase 35 of a bug it does not have.
control_1() {
    printf '\n# note: a diagnosis may call jenkins_get or registry_creds.\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# control: a phase that mentions secrets_workdir in prose and already
# opens it for real is not a defect.
control_2() {
    printf '\n# note: the tmpfs (secrets_workdir) is shredded on exit.\n' \
        >> "$AEGIS_ROOT/init/phases/87-ai.sh"
}

# control: ${var#pat} is not a comment. A naive strip at the first `#`
# would blind the scanner to the rest of those lines.
control_3() {
    printf '\n_t163() { local v="${AEGIS_ROOT#/}"; printf "%%s" "$v"; }\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}
