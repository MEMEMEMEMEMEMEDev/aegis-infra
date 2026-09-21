# teeth for 223 — each red brings back one way a base rebuild touched what
# nobody asked for. Every mutation is a REAL regression: the code as it
# was on 2026-09-13, or the one-line slip that reopens it.
JF223="$AEGIS_ROOT/seed/platform/base-images/Jenkinsfile"
DSL223="$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml"
W223="$AEGIS_ROOT/seed/platform/image-watch/Jenkinsfile"
P223="$AEGIS_ROOT/init/phases/80-supply-chain.sh"
CI223="$AEGIS_ROOT/libexec/aegis-ci"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the job-dsl forgets PROPAGATE: the pipeline and the DSL no longer say the same
red_1() { _sub "$DSL223" "                  booleanParam('PROPAGATE', false, " "                  booleanParam('PROPAGATE_OLD', false, "; }

# PROPAGATE is born true: consumers are told by default again
red_2() { _sub "$JF223" "booleanParam(name: 'PROPAGATE', defaultValue: false," "booleanParam(name: 'PROPAGATE', defaultValue: true,"; }

# MEMBERS empty goes back to «all of them»: the 2026-09-13 code
red_3() { python3 - "$JF223" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = re.search(r"          if \(!asked\) \{\n(?:.*\n)*?          \}\n", s)
assert old, "re-aim this tooth"
s = s.replace(old.group(0), "          def members = all\n          if (asked) {\n            members = asked.split(/\\s+/) as List\n          }\n", 1)
s = s.replace("          def members = asked.split(/\\s+/) as List\n", "", 1)
p.write_text(s)
PY
}

# the propagate door is gone: every member built rewrites every consumer
red_4() { python3 - "$JF223" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = re.search(r"          if \(!params\.PROPAGATE\) \{\n(?:.*\n)*?            return\n          \}\n", s)
assert old, "re-aim this tooth"
p.write_text(s.replace(old.group(0), "", 1))
PY
}

# image-watch stops saying PROPAGATE: a base rebuilt for a CVE is built and forgotten
red_5() { _sub "$W223" ",
                                 booleanParam(name: 'PROPAGATE', value: true)]" "]"; }

# phase 80 fires base-images with no query, as before: the pipeline refuses it
red_6() { python3 - "$P223" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = re.search(r'gate "base-images-build-verde" jenkins_build_retry base-images 2700 2 \\\n\s*"MEMBERS=[^\n]*\n', s)
assert old, "re-aim this tooth"
p.write_text(s.replace(old.group(0), 'gate "base-images-build-verde" jenkins_build_retry base-images 2700 2\n', 1))
PY
}

# aegis ci build sends MEMBERS and never PROPAGATE: --propagate says nothing
red_7() { _sub "$CI223" "q=\"MEMBERS=\$(jq -rn --arg m \"\$m\" '\$m|@uri')&PROPAGATE=\$p\"" "q=\"MEMBERS=\$(jq -rn --arg m \"\$m\" '\$m|@uri')\""; }

# the job-dsl's words go back to promising what the code refuses
red_8() { _sub "$DSL223" "MEMBERS names what to rebuild and is never empty;" "MEMBERS empty = every member;"; }

# aegis ci build loses the way to spell «every member»: the chain would stop
red_9() { _sub "$CI223" "ci_members_of_tree() {" "ci_members_of_tree_gone() {"; }

# ── controls ──
# a third parameter, declared on BOTH sides, is legal
control_1() {
    _sub "$JF223" "    booleanParam(name: 'PROPAGATE', defaultValue: false," "    string(name: 'NOTE', defaultValue: '', description: 'free text for the log')
    booleanParam(name: 'PROPAGATE', defaultValue: false,"
    _sub "$DSL223" "                  booleanParam('PROPAGATE', false, " "                  stringParam('NOTE', '', 'free text for the log')
                  booleanParam('PROPAGATE', false, "
}
# the description of PROPAGATE is prose
control_2() { _sub "$DSL223" "OFF by default: the bases are built, scanned, signed and pushed, and nobody is told until asked" "off unless asked: build, scan, sign, push, and tell nobody"; }
# a comment that names the old default is not the old default
control_3() { printf '\n// note: MEMBERS empty = all of them was the rule until 2026-09-13.\n' >> "$JF223"; }

# ── the candidate runs as a pod before it is signed (2026-09-20) ────────
K223="$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins-secrets/kustomization.yaml"
R223="$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins-secrets/rbac-base-images-agent.yaml"

# the run step is gone: the tar is the only proof again
red_10() { python3 - "$JF223" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index("              // ── RUN IT, before it is signed"); j = s.index("              container('cosign') {\n                // Signed BY DIGEST")
p.write_text(s[:i] + s[j:])
PY
}
# the candidate is signed first and run afterwards
red_11() { python3 - "$JF223" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index("              // ── RUN IT, before it is signed"); j = s.index("              container('cosign') {\n                // Signed BY DIGEST")
run = s[i:j]; s = s[:i] + s[j:]
k = s.index("              sh '''\n                DIGEST=\"$(cat ${WORKSPACE}/base-${M}.digest)\"\n                BASE_DIGEST=")
p.write_text(s[:k] + run + s[k:])
PY
}
# the test pod gets a writable root: laxer than a tenant, so it passes what a tenant rejects
red_12() { _sub "$JF223" '"readOnlyRootFilesystem":true},"resources"' '"readOnlyRootFilesystem":false},"resources"'; }
# the agent runs as the default account: the API refuses the pod
red_13() { _sub "$JF223" "  serviceAccountName: base-images-agent
" ""; }
# the Role is not applied: it exists on disk and never reaches the cluster
red_14() { _sub "$K223" "  - rbac-base-images-agent.yaml" "  # - rbac-base-images-agent.yaml"; }
# the Role reaches into secrets: more than a test pod needs
red_15() { _sub "$R223" "    resources: [pods]" "    resources: [pods, secrets]"; }
# the test pod is never deleted
red_16() { python3 - "$JF223" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
n = s.count("-X DELETE"); assert n == 2, n
p.write_text(s.replace("-X DELETE", "-X GET"))
PY
}
# the API's pretty JSON is read raw again: Ready never matches (build #13)
red_17() { _sub "$JF223" "| tr -d '[:space:]')\"" ")\""; }
# the report's ternary loses its parentheses (build #13)
red_18() { _sub "$JF223" "          echo(params.PROPAGATE ? 'all members built, signed and propagated.'" "          echo params.PROPAGATE ? 'all members built, signed and propagated.'"; }
# type and status adjacent again: observedGeneration sits between them (build #14)
red_19() { _sub "$JF223" "grep -qE '\"type\":\"Ready\"[^}]*\"status\":\"True\"'" "grep -q '\"type\":\"Ready\",\"status\":\"True\"'"; }
# the token back in argv (build #14 printed it)
red_20() { _sub "$JF223" 'k() { curl -sS --cacert $SA/ca.crt -H @"$HDR" "$@"; }' 'k() { curl -sS --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" "$@"; }'; }
# the trace back on
red_21() { python3 - "$JF223" <<'PYT'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index("// ── RUN IT, before it is signed"); j = s.index("                set +x\n", i)
p.write_text(s[:j] + s[j + len("                set +x\n"):])
PYT
}
# ── controls ──
# waiting longer is still waiting
control_4() { _sub "$JF223" 'while [ $i -lt 45 ]; do' 'while [ $i -lt 60 ]; do'; }
# the Role may also watch its own pod's events
control_5() { _sub "$R223" "  - apiGroups: [\"\"]
    resources: [pods/log]
    verbs: [get]" "  - apiGroups: [\"\"]
    resources: [pods/log]
    verbs: [get]
  - apiGroups: [\"\"]
    resources: [events]
    verbs: [list]"; }
