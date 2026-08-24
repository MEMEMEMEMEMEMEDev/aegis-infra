# teeth of check 005b (argo_sync ↔ declared Applications)
# The class of the hello-aegis hole: a phase syncs an App that nobody
# declares. The sync «does not fail»: it waits for something that does
# not exist and gives up on a timeout, with a message that talks about
# ArgoCD and not about the manifest that is missing.
red_1() { printf '\nargo_sync app-that-nobody-declares\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"; }
control_1() { printf '\n# argo_sync app-that-nobody-declares (example inside a comment)\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"; }
