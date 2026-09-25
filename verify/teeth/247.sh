# teeth of check 247 — an organization does not reach the GPU unless the platform hands it one.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
POL247="$AEGIS_ROOT/seed/platform/k8s/base/kyverno-policies/clusterpolicy-tenants-without-gpu.yaml"
KUS247="$AEGIS_ROOT/seed/platform/k8s/base/kyverno-policies/kustomization.yaml"
COM247="$AEGIS_ROOT/lib/common.sh"
PH35_247="$AEGIS_ROOT/init/phases/35-gitops.sh"

# the tree as it was on 2026-09-24: no policy at all
red_1() { rm -f "$POL247"; }

# way 2 reopened: the runtime class is chosen by the repo again
red_2() { _sub "$POL247" '            X(runtimeClassName): "null"' '            =(runtimeClassName): "?*"'; }

# the policy exists and nothing lists it: it never reaches the cluster
red_3() { _sub "$KUS247" 'resources:
  - clusterpolicy-tenants-without-gpu.yaml' 'resources: []'; }

# scoped by the tenants label: ai-system carries it, the platform's GPU lane is refused
red_4() { _sub "$POL247" '    - name: no-gpu-resource
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: ["org-*"]' '    - name: no-gpu-resource
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaceSelector:
                matchLabels:
                  aegis.dev/part-of: aegis-tenants'; }

# the env rule forgets the init containers: the variable goes in through one
red_5() { _sub "$POL247" '            =(initContainers):
              - =(env):
                  - name: "!NVIDIA_*"' '            =(initContainers):
              - =(env):
                  - name: "?*"'; }

# a rule that only reports
red_6() { _sub "$POL247" '        failureAction: Enforce
        message: >-
          an organization'"'"'s pod does not choose its runtime' '        failureAction: Audit
        message: >-
          an organization'"'"'s pod does not choose its runtime'; }

# the helper as the phases were until today: `on` writes a one-entry list
red_7() { _sub "$COM247" '    res = [SIG] + res' '    res = [SIG]'; }

# phase 35's gate as it was: any clusterpolicy reads as the signature left on
red_8() { _sub "$PH35_247" "sys.exit(1 if 'clusterpolicy-require-aegis-signature.yaml' in r else 0)" "sys.exit(1 if any('clusterpolicy' in x for x in r) else 0)"; }

# webhook fails open: with Kyverno down the GPU is admitted
red_9() { _sub "$POL247" 'spec:
  webhookConfiguration:
    failurePolicy: Fail' 'spec:
  webhookConfiguration:
    failurePolicy: Ignore'; }

# control: a rule's message reworded
control_1() { _sub "$POL247" 'handed over by the platform, not requested from a repo' 'given by the platform, never requested from a repo'; }

# control: a comment added to the kustomization
control_2() { printf '# legitimate comment\n' >> "$KUS247"; }
