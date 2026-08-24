# title: backup/restore of the 3 states: DR with a proven roundtrip (W-09/R4)
# origin: verify-static.sh (v2) ══ 80
check() {
# R4: the 3 states (.state-secrets/.init-state/tfstate) live ONLY on the VM
# and the age key alone does NOT recover them. aegis-backup produces ONE
# portable age-encrypted bundle WITH a verified roundtrip ("restore proven",
# not "we have backups" — Law 21.719). Invariants nailed down:
D80=""
# `aegis state backup|restore`: two verbs of one command, not two loose
# commands. They are the same operation in two directions and the
# operator looks for them together.
BK="$LIBEXEC/state/backup"; RS="$LIBEXEC/state/restore"
for s in "$BK" "$RS"; do
    [[ -f "$s" ]] || { D80="$D80 $(basename "$s") missing;"; continue; }
    bash -n "$s" 2>/dev/null || D80="$D80 $(basename "$s") does not parse;"
    [[ -x "$s" ]] || D80="$D80 $(basename "$s") not executable;"
done
if [[ -f "$BK" ]]; then
    grep -q 'STATE_SECRETS='       "$BK" || D80="$D80 backup does not cover .state-secrets;"
    grep -q 'INIT_STATE='          "$BK" || D80="$D80 backup does not cover .init-state;"
    grep -q 'terraform.tfstate'    "$BK" || D80="$D80 backup does not cover the tfstate;"
    grep -q 'age -r'               "$BK" || D80="$D80 backup does not encrypt with age -r;"
    grep -Eq 'age -d .*\| *tar'    "$BK" || D80="$D80 backup does not decrypt for the roundtrip;"
    grep -q 'ROUNDTRIP OK'         "$BK" || D80="$D80 backup without roundtrip verification (it would be 'we have backups', not DR);"
    grep -Eq "name 'aegis.key'|sops/age" "$BK" \
        || D80="$D80 backup without a guard excluding the age key (the irreducible must not be backed up);"
    grep -q 'AEGIS_BACKUP_SINK' "$BK" \
        || D80="$D80 backup without an offsite sink hook (a bundle that never leaves the VM is not DR);"
fi
if [[ -f "$RS" ]]; then
    grep -Eq 'age -d .*-i' "$RS" || D80="$D80 restore does not use the private age key;"
    grep -q 'FORCE'        "$RS" || D80="$D80 restore without a --force guard (it would blindly overwrite live state);"
    grep -q 'ALREADY exists'    "$RS" || D80="$D80 restore does not refuse to overwrite an existing destination;"
fi
if [[ -n "$D80" ]]; then fail "backup-restore:$D80"
else pass "aegis state backup/restore: 3 states, age-encrypted, proven roundtrip, key excluded, restore with a --force guard"; fi
}
