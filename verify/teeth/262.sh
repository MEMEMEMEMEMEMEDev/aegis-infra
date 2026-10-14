# teeth of check 262 — a tenant build is judged on its own layers.
J262="$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"
V262="$AEGIS_ROOT/seed/platform/k8s/base/platform/vuln-policy/verdict.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# build 1 on the Arch lab VM: no split, the base's CVEs are the app's
red_1() { _sub "$J262" '($8 in B) { print > "inherited.txt"; next }' '(0) { print > "inherited.txt"; next }'; }

# build 3 on the Arch lab VM: the config read as one line, 0 base layers found
red_2() { _sub "$V262" "    tr -d ' \\t\\r\\n' | sed -n" "    sed -n"; }

# the scan decides alone again
red_3() { _sub "$J262" '                trivy image --server "${TRIVY_SERVER}" --input "${WORKSPACE}/image.tar" \
                  --exit-code 0' '                trivy image --server "${TRIVY_SERVER}" --input "${WORKSPACE}/image.tar" \
                  --exit-code 1'; }

# no policy mounted, read as clean
red_4() { _sub "$J262" '                  echo "ERROR: the platform'"'"'s vulnerability policy is not mounted (ConfigMap aegis-vuln-policy in jenkins-system, Application vuln-policy): a scan nobody can judge is not a clean one"
                  exit 3' '                  echo "ERROR: the platform'"'"'s vulnerability policy is not mounted (ConfigMap aegis-vuln-policy in jenkins-system, Application vuln-policy): a scan nobody can judge is not a clean one"
                  exit 0'; }

# what runs today is never the reference: every inherited finding of the app's own layers is «new»
red_5() { _sub "$J262" 'sh "$VP/verdict.sh" own.txt running.txt' 'sh "$VP/verdict.sh" own.txt'; }

# a stop that does not stop
red_6() { _sub "$J262" '                  1) echo "scan: the lines marked «block» above stop this build (in this image'"'"'s OWN layers)"; exit 10 ;;' '                  1) exit 0 ;;'; }

# the pod waits for the ConfigMap forever instead of the scan saying so
red_7() { _sub "$J262" '    configMap:
      name: aegis-vuln-policy
      optional: true' '    configMap:
      name: aegis-vuln-policy'; }

# ── controls ──
control_1() { _sub "$J262" 'echo "scan: $n base config(s) read (their layers are the platform'"'"'s)"' 'echo "scan: $n config(s) of the base(s) read (their layers are the platform'"'"'s)"'; }
