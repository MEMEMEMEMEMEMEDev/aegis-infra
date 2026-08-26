# teeth for check 115 (both edges of every phase that branches)
#
# The three regressions it exists for, and the first one is not
# hypothetical: it was live in phases 15 and 85 on 2026-08-26, sixteen
# times, and it would have killed the phase on every instance whose conf
# predated EDGE.

# the safe default disappears: with a conf written before EDGE existed,
# `set -u` kills the phase with «unbound variable» instead of falling
# back to the edge it could only have been
red_1() {
    sed -i '0,/\[\[ "${EDGE:-cloudflare}" == /s//[[ "$EDGE" == /' \
        "$AEGIS_ROOT/init/phases/25-edge-tofu.sh"
}

# a gate that cloudflare emits stops being declared for local: on that
# edge it does not fail, it vanishes from gates.jsonl — and a missing
# line reads exactly like a green one
red_2() {
    python3 - "$AEGIS_ROOT/init/phases/15-third-parties.sh" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r'    gate_no_subject "tokens-roundtrip" \\\n[^\n]*\n', "", t, count=1)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}

# the same, on the phase where the gate is SUBSTITUTED rather than lost:
# a rename is still a contract that stops being honoured
red_3() {
    python3 - "$AEGIS_ROOT/init/phases/60-webhook.sh" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r'    gate_no_subject "build-disparado-por-webhook" \\\n[^\n]*\n', "", t, count=1)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}

# a branch left with no body: the phase does nothing on that edge and
# says nothing about it, which is the silence this tree treats as red
red_4() {
    printf '\nif [[ "${EDGE:-cloudflare}" == local ]]; then\nfi\n' \
        >> "$AEGIS_ROOT/init/phases/20-k3s.sh"
}

# control: a phase that does NOT branch on EDGE is not this check's
# business, and adding one more of them must not turn it red
control_1() {
    printf '\nlog_info "a step that is the same on both edges"\n' \
        >> "$AEGIS_ROOT/init/phases/30-argocd.sh"
}

# control: a gate that exists ONLY on the local edge is a gain, not a
# loss — demanding a declaration for it would be demanding that the
# local edge apologise for having mechanisms cloudflare does not
control_2() {
    python3 - "$AEGIS_ROOT/init/phases/25-edge-tofu.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
anchor = '    run_cmd sudo systemctl daemon-reload\n'
assert anchor in t
open(p, "w").write(t.replace(anchor, '    gate "edge-tooth-local-only" true\n' + anchor, 1))
PY
}

# control: telling the story in a comment, naming a gate and a bare
# "$EDGE", is what this tree does everywhere
control_3() {
    printf '\n# history: this used to read [[ "$EDGE" == cloudflare ]] and gate "ns-en-cloudflare"\n' \
        >> "$AEGIS_ROOT/init/phases/25-edge-tofu.sh"
}
