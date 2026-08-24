# title: every init run leaves a dossier
# origin: verify-static.sh (v2) ══ 96
check() {
# Minimal stage C (RUTA.md): today init's stderr is lost with the
# terminal. The aegis-init-log.sh wrapper captures the WHOLE run with
# script(1) —a live TTY for the wizard, a real rc— and the dossier's
# path is printed BEFORE executing: if the run dies, the operator
# already knows where to read. The log is local evidence, not an
# artifact: gitignored.
D96=""
ILOG="$LIBEXEC/aegis-init-log"
if [[ ! -f "$ILOG" ]]; then D96="$D96 libexec/aegis-init-log missing;"
else
    [[ -x "$ILOG" ]] || D96="$D96 it is not executable;"
    grep -q 'script -qefc' "$ILOG" \
        || D96="$D96 it does not use script -qefc (without -e init's rc is lost; without script there is no TTY for the wizard);"
    L_EXP="$(grep -n "printf 'expediente:" "$ILOG" | head -1 | cut -d: -f1)"
    L_SCR="$(grep -n 'script -qefc' "$ILOG" | tail -1 | cut -d: -f1)"
    if [[ -z "$L_EXP" ]]; then D96="$D96 it does not print 'expediente:' (the operator would not know where to read);"
    elif [[ -n "$L_SCR" && "$L_EXP" -gt "$L_SCR" ]]; then
        D96="$D96 the dossier's path is printed AFTER running: a hung run never shows it;"
    fi
fi
# The dossier is INSTANCE state, not product state. In v2 it landed in
    # init/.init-logs/ INSIDE the repo and a .gitignore line was needed
    # so that a distracted `git add` would not version the whole run
    # with the host's stderr inside. The class rule beats the exclusion:
    # do not let it be born where it should not.
    grep -q 'AEGIS_STATE_DIR' "$ILOG" \
        || D96="$D96 the dossier is not written under \$AEGIS_STATE_DIR (if it lands inside the product, a git add versions it with the host's stderr inside);"
    nc "$ILOG" | grep -qE '\$AEGIS_ROOT/(init/)?\.init-log' \
        && D96="$D96 the dossier is still written inside the product;"
if [[ -n "$D96" ]]; then fail "96:$D96"
else pass "aegis-init-log: one dossier per run, path first, log outside git"; fi
}
