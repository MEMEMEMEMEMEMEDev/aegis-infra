# dientes del check 030a (todo git push va verificado)
# Corrida #9: un push que falla y sigue de largo deja un commit local
# sin pushear, y kustomize se rompe UNA fase después.
red_1() { printf '\ngit -C "$PLATFORM_DIR" push origin main\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"; }
control_1() { printf '\ngit_push_verified "$PLATFORM_DIR" main\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"; }
