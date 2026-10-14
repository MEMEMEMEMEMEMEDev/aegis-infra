# title: no variable of a platform pipeline is declared twice in one scope chain (Groovy refuses it only when Jenkins compiles the run)
# origin: new in v3 — 2026-10-02, the Arch lab VM: image-watch #3 died at compile time over `def mrc` declared inside a block that already had one; the declarative linter had validated the file
check() {
D274=""
[[ -f "$AEGIS_ROOT/verify/checks/274.py" ]] || { fail "check 274 has no sidecar"; return; }
OUT274="$(python3 "$AEGIS_ROOT/verify/checks/274.py" "$AEGIS_ROOT" 2>&1)"
RC274=$?
(( RC274 == 0 )) || { fail "the exercise of check 274 itself failed (rc $RC274): ${OUT274:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE274="${hit#SCOPE: }" ;;
        *)       D274="$D274 $hit;" ;;
    esac
done <<< "$OUT274"
printf '    %s\n' "${SCOPE274:-the scope was not reported}"
if [[ -n "$D274" ]]; then
    fail "a pipeline would not compile:$D274"
else
    pass "no Jenkinsfile of the seed declares a name an enclosing scope already holds (${SCOPE274})"
fi
}
