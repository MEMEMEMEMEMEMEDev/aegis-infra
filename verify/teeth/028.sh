# teeth of check 028 — regcreds with type dockerconfigjson.
#
# Re-aimed on 2026-08-29. The single red used to be «delete phase 40»,
# and it worked for one reason that stopped being true that day: phase
# 40 was the ONLY phase minting a regcred, so removing it took the
# check's subject count to zero and the check failed for lack of
# subjects. Phase 87 arrived with the AI subsystem and its own regcred,
# so deleting phase 40 now leaves a subject behind, the check stays
# green, and the tooth reported nothing. The full teeth run said
# «0/1 bite» in both profiles.
#
# The lesson is the one this file keeps re-learning: a tooth aimed at
# the ONLY instance of a class stops biting the day there are two. So
# the reds below aim at the DEFECT, which does not depend on how many
# phases there are.

# THE REGRESSION ITSELF: a regcred encrypted without its type. The
# kubelet ignores an Opaque Secret as an imagePullSecret ("no basic
# auth credentials") and the pods stay in ImagePullBackOff with a
# credential that is right there and correct.
red_1() {
    sed -i '0,/--type kubernetes.io\/dockerconfigjson/{s/--type kubernetes.io\/dockerconfigjson//}' \
        "$AEGIS_ROOT/init/phases/40-registry-pki.sh"
}

# the same defect in the OTHER phase that mints one, because there are
# two now and a check that only watched the first would be the tooth
# this file just had to replace.
red_2() {
    sed -i '0,/--type kubernetes.io\/dockerconfigjson/{s/--type kubernetes.io\/dockerconfigjson//}' \
        "$AEGIS_ROOT/init/phases/87-ai.sh"
}

# the subject disappears — ALL of it, which is what the old red meant
# to do. With no regcred anywhere, finding no defect must not be
# reported as «every regcred is fine».
red_3() {
    grep -rl 'dockerconfigjson' "$AEGIS_ROOT/init/phases/" | xargs -r rm -f
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/40-registry-pki.sh"; }
