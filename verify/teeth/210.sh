# teeth for 210 — the copies must agree. Each red is the edit somebody
# forgets: one file out of six, or a tag the chain does not build.
J210="$AEGIS_ROOT/seed/platform/image-watch/Jenkinsfile"
C210="$AEGIS_ROOT/seed/platform/ci-images/Jenkinsfile"
M210="$AEGIS_ROOT/seed/platform/mirror-images/Jenkinsfile"

# one file keeps the old agent: five bumped, one left behind
red_1() { sed -i 's|jenkins/inbound-agent:[^ ]*|jenkins/inbound-agent:3200.v1111111a_11b_11-1|' "$J210"; }

# trivy is bumped in one place and nowhere else
red_2() { sed -i 's|ghcr.io/aquasecurity/trivy:[^ ]*|ghcr.io/aquasecurity/trivy:0.99.0|' "$J210"; }

# the pod template asks for a cosign this instance does not build
red_3() { python3 - "$AEGIS_ROOT" <<'P'
import sys, pathlib, re
root = pathlib.Path(sys.argv[1])
n = 0
for f in (root / "seed" / "platform").rglob("Jenkinsfile*"):
    s = f.read_text()
    if "aegis-ci-cosign:" not in s:
        continue
    f.write_text(re.sub(r"aegis-ci-cosign:[^\s'\"]+", "aegis-ci-cosign:v9.9.9", s))
    n += 1
assert n, "re-aim this tooth: no Jenkinsfile names aegis-ci-cosign"
P
}

# the crane of the templates stops matching the one its Containerfile
# builds. It is aimed at the Jenkinsfile that PINS it in a pod template
# and not at ci-images/, which is the one that BUILDS it and names it
# without a tag: the first aim mutated nothing and the harness said so.
red_4() { sed -i 's|aegis-ci-crane:v[0-9.]*|aegis-ci-crane:v0.1.0|g' "$M210"; }

# ── controls ──
# a comment in a Jenkinsfile is not a pin
control_1() { printf '\n// note: the pod templates are written by hand in every file.\n' >> "$J210"; }
# bumping the SAME image in EVERY file is a legitimate bump
control_2() { python3 - "$AEGIS_ROOT" <<'P'
import sys, pathlib, re
root = pathlib.Path(sys.argv[1])
n = 0
for f in (root / "seed" / "platform").rglob("Jenkinsfile*"):
    s = f.read_text()
    if "kaniko-project/executor:" not in s:
        continue
    f.write_text(re.sub(r"(kaniko-project/executor:)[^\s'\"]+", r"\g<1>v1.24.0-debug", s))
    n += 1
assert n, "re-aim this control"
P
}
# renaming a stage changes no pin
control_3() { sed -i '0,/stage(/s/stage(/stage (/' "$J210"; }
