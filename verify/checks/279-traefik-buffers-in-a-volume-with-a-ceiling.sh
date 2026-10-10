# title: traefik buffers request bodies in a volume with a ceiling, not in the chart's uncapped /tmp
# origin: new in v3 — 2026-09-27, the home instance: orphaned temp-multibuf files piled up to 9.7 GB in traefik's emptyDir and took the system disk
check() {
D279=""
[[ -f "$AEGIS_ROOT/verify/checks/279.py" ]] || { fail "check 279 has no sidecar"; return; }
OUT279="$(python3 "$AEGIS_ROOT/verify/checks/279.py" "$AEGIS_ROOT" 2>&1)"
RC279=$?
(( RC279 == 0 )) || { fail "the exercise of check 279 itself failed (rc $RC279): ${OUT279:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE279="${hit#SCOPE: }" ;;
        *)       D279="$D279 $hit;" ;;
    esac
done <<< "$OUT279"
printf '    %s\n' "${SCOPE279:-the scope was not reported}"
if [[ -n "$D279" ]]; then
    fail "traefik's buffer can fill the disk:$D279"
else
    pass "traefik's TMPDIR is a mounted emptyDir with a sizeLimit: a pile of orphaned buffers evicts one replica instead of filling the disk (${SCOPE279})"
fi
}
