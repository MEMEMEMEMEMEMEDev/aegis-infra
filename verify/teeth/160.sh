# teeth of check 160 — every AI image the kustomization pins has a
# producer named in the artifact.

# THE STATE THE ARTIFACT WAS ACTUALLY IN on 2026-08-30, run backwards:
# the GPU engine's Jenkinsfile stops declaring the image it pushes, so
# nothing in the tree claims to produce `aegis-ai-vllm` and its row is
# pinned by nobody.
red_1() {
    sed -i "s/^    IMAGE        = 'aegis-ai-vllm'$/    IMAGE        = 'otro-nombre'/" \
        "$AEGIS_ROOT/seed/platform/ai/engine-gpu/Jenkinsfile"
}

# the same on the CPU lane, so the check is not reading one name.
red_2() {
    sed -i "s/^    IMAGE        = 'aegis-engine-cpu'$/    IMAGE        = 'otro-cpu'/" \
        "$AEGIS_ROOT/seed/platform/ai/engine-cpu/Jenkinsfile"
}

# A NEW ROW pinned with nobody to build it: the class, not the two
# cases already known. This is tomorrow's defect entering by the same
# door as yesterday's.
red_3() {
    cat >> "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/kustomization.yaml" <<'EOF'
  - name: registry.registry-system.svc.cluster.local:5000/aegis-engine-futuro
    digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
EOF
}

# THE INSTANCE-PROVIDED KIND, half of it removed. The gateway is a
# legitimate answer only while BOTH halves are there: take the
# placeholder away and it becomes a job pointing nowhere.
red_4() {
    sed -i 's/AI_GATEWAY_REPO\\|//' "$AEGIS_ROOT/lib/common.sh"
}

# the other half: the placeholder stays and no job uses it — a question
# nobody acts on.
red_5() {
    sed -i "s/repository('__AI_GATEWAY_REPO__')/repository('otro')/" \
        "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml"
}

# and the subject taken away: with no row pinned, no producer could be
# missing, and that has to be said instead of passing. The shape of the
# bug found in check 004 on 2026-08-29.
red_6() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/kustomization.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"(?ms)^images:.*", "", s))
PY
}

# control: a mirrored image is a legitimate producer, so adding one
# more row that IS mirrored cannot turn it red.
control_1() {
    cat >> "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/kustomization.yaml" <<'EOF'
  - name: registry.registry-system.svc.cluster.local:5000/redis
    digest: sha256:1111111111111111111111111111111111111111111111111111111111111111
EOF
}

# control: prose naming an image is not a row.
control_2() {
    printf '\n# note: ai-gateway comes from its own repository.\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/kustomization.yaml"
}
