# titulo: backup/restore de los 3 estados: DR con roundtrip probado (W-09/R4)
# origen: verify-static.sh (v2) ══ 80
check() {
# R4: los 3 estados (.state-secrets/.init-state/tfstate) SÓLO viven en la VM
# y la age key sola NO los recupera. aegis-backup produce UN bundle age-
# cifrado portable CON roundtrip verificado ("restauración probada", no
# "tenemos backups" — Ley 21.719). Invariantes clavados:
D80=""
BK="$LIBEXEC/aegis-backup"; RS="$LIBEXEC/aegis-restore"
for s in "$BK" "$RS"; do
    [[ -f "$s" ]] || { D80="$D80 falta $(basename "$s");"; continue; }
    bash -n "$s" 2>/dev/null || D80="$D80 $(basename "$s") no parsea;"
    [[ -x "$s" ]] || D80="$D80 $(basename "$s") no ejecutable;"
done
if [[ -f "$BK" ]]; then
    grep -q 'STATE_SECRETS='       "$BK" || D80="$D80 backup no cubre .state-secrets;"
    grep -q 'INIT_STATE='          "$BK" || D80="$D80 backup no cubre .init-state;"
    grep -q 'terraform.tfstate'    "$BK" || D80="$D80 backup no cubre tfstate;"
    grep -q 'age -r'               "$BK" || D80="$D80 backup no cifra con age -r;"
    grep -Eq 'age -d .*\| *tar'    "$BK" || D80="$D80 backup no descifra para el roundtrip;"
    grep -q 'ROUNDTRIP OK'         "$BK" || D80="$D80 backup sin verificación de roundtrip (sería 'tenemos backups', no DR);"
    grep -Eq "name 'aegis.key'|sops/age" "$BK" \
        || D80="$D80 backup sin guarda de exclusión de la age key (el irreducible no se respalda);"
    grep -q 'AEGIS_BACKUP_SINK' "$BK" \
        || D80="$D80 backup sin hook de sink offsite (un bundle que no sale de la VM no es DR);"
fi
if [[ -f "$RS" ]]; then
    grep -Eq 'age -d .*-i' "$RS" || D80="$D80 restore no usa la age key privada;"
    grep -q 'FORCE'        "$RS" || D80="$D80 restore sin guarda --force (pisaría estado vivo a ciegas);"
    grep -q 'YA existe'    "$RS" || D80="$D80 restore no rechaza pisar un destino existente;"
fi
if [[ -n "$D80" ]]; then fail "backup-restore:$D80"
else pass "aegis-backup/restore: 3 estados, age-cifrado, roundtrip probado, key excluida, restore con --force guard"; fi
}
