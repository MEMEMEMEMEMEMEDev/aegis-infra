# title: greenfield: when cleaning the cloud, purge the LOCAL tfstate
# origin: verify-static.sh (v2) ══ 21
check() {
# Run #6, bug 2: the dirty-cloud pre-check deletes the Cloudflare
# tunnel but the local terraform.tfstate survives on the VM's disk
# between --from 25 → tofu takes it for existing and does a PUT
# configurations → 404. The two halves of the greenfield are cleaned
# TOGETHER. Static: the cleanup block of phase 25 MUST purge the env's
# tfstate (rm of terraform.tfstate) — deleting in the cloud is not
# enough. Co-occurrence in the same file is demanded:
P25="$PHASES/25-edge-tofu.sh"
if grep -q 'cfd_tunnel/\$TID_PREV' "$P25" \
   && grep -qE 'rm -f .*\$TUNNEL_ENV/terraform\.tfstate' "$P25"; then
    pass "phase 25: the cloud cleanup also purges the local tfstate"
else
    fail "phase 25 deletes in the cloud but does NOT purge the local tfstate (bug 2: cloud and state out of sync)"
fi
}
