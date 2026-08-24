# teeth of check 030a (every git push goes verified)
# Run #9: a push that fails and carries on leaves a local commit that
# was never pushed, and kustomize breaks ONE phase later.
red_1() { printf '\ngit -C "$PLATFORM_DIR" push origin main\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"; }
control_1() { printf '\ngit_push_verified "$PLATFORM_DIR" main\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"; }
