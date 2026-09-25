# teeth of check 248 — `gpu: true` is the one door to the card.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
ORG248="$AEGIS_ROOT/lib/aegis/org.py"
POL248="$AEGIS_ROOT/seed/platform/k8s/base/kyverno-policies/clusterpolicy-tenants-without-gpu.yaml"

# the quota forgets the card: a rolling update puts two copies on it
red_1() { _sub "$ORG248" "        lines.append('    requests.nvidia.com/gpu: \"1\"')" "        pass"; }

# the Namespace is not labelled: the policy refuses the card the contract granted
red_2() { _sub "$ORG248" "        lines.append(f'    {GPU_GRANT}: \"true\"')" "        pass"; }

# the lane is not asked: a cpu instance's pod waits forever for a card
red_3() { _sub "$ORG248" '        if lane != "gpu":' '        if lane == "never":'; }

# two services with the card, one quota
red_4() { _sub "$ORG248" '    if len(gpu) > 1:' '    if len(gpu) > 2:'; }

# in a granted namespace, the runtime without the request: the card outside the quota
red_5() { _sub "$POL248" '            (runtimeClassName): "nvidia"
            containers:
              - resources:
                  limits:
                    nvidia.com/gpu: "?*"' '            (runtimeClassName): "nvidia"'; }

# the exception keyed on a label the tenant's own pods can carry
red_6() { _sub "$POL248" '    - name: no-gpu-resource
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: ["org-*"]
      exclude:
        any:
          - resources:
              namespaceSelector:
                matchLabels:
                  aegis.dev/gpu-otorgada: "true"' '    - name: no-gpu-resource
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: ["org-*"]
      exclude:
        any:
          - resources:
              selector:
                matchLabels:
                  aegis.dev/gpu-otorgada: "true"'; }

# the card written into EVERY service's pods, not the gpu one's
red_7() { _sub "$ORG248" '            if s.get("gpu") is True:
                lines.append(f"""\
    # `gpu: true` in the contract' '            if True:
                lines.append(f"""\
    # `gpu: true` in the contract'; }

# control: a rule's message reworded
control_1() { _sub "$POL248" 'the only runtime an organization with the GPU granted may use is' 'the single runtime an organization with the GPU granted may use is'; }
