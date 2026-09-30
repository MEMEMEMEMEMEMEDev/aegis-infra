# teeth of check 257 — the mirror's door judges what comes in; retained is not broken.
M257="$AEGIS_ROOT/seed/platform/mirror-images/Jenkinsfile"
P257="$AEGIS_ROOT/init/phases/80-supply-chain.sh"
L257="$AEGIS_ROOT/lib/jenkins.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the door as it was until 2026-09-30: trivy decides alone
red_1() { _sub "$M257" '--exit-code 0 --severity CRITICAL,HIGH --ignore-unfixed \
                    --scanners vuln --no-progress \
                    --ignorefile "${WORKSPACE}/mirror-images/trivyignore.yaml" \
                    --format json' '--exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed \
                    --scanners vuln --no-progress \
                    --ignorefile "${WORKSPACE}/mirror-images/trivyignore.yaml" \
                    --format json'; }

# a retained image is taken for a clean one, and pushed
red_2() { _sub "$M257" '                    1) exit 10 ;;' '                    1) exit 0 ;;'; }

# a verdict that could not be given passes as clean
red_3() { _sub "$M257" '*) echo "the verdict could not be given (rc $rc): an unjudged scan is not a clean one"; exit 1 ;;' '*) exit 0 ;;'; }

# the signature forgets where the image came from: nothing is ever recognised again
red_4() { _sub "$M257" '                    --tlog-upload=false \
                    -a "aegis.dev/source=${SRC}" \' '                    --tlog-upload=false \'; }

# phase 80 as it was: an UNSTABLE mirror is a dead install
red_5() { _sub "$P257" '    (( rc == 4 )) || return "$rc"' '    return "$rc"'; }

# phase 80 stops caring whether the platform runs a retained image
red_6() { _sub "$P257" '            needed+="$img "' '            :'; }

# the retry re-fires a retained image as if it were the network
red_7() { _sub "$L257" '        if (( wrc == 4 )); then
            JENKINS_LAST_BUILD="$next"
            return 4
        fi' ''; }

# verify asks for a provenance sign never writes
red_8() { _sub "$M257" '-a "aegis.dev/source=${SRC}" "${REGISTRY}/${DST}"' '-a "aegis.dev/origin=${SRC}" "${REGISTRY}/${DST}"'; }

# ── controls ──
control_1() { _sub "$M257" 'retained at the door — the findings marked «block» above stop it' 'held at the door — the findings marked «block» above stop it'; }
control_2() { _sub "$P257" 'retained at the door, not needed by the platform to run:' 'waiting at the door, not needed by the platform to run:'; }
