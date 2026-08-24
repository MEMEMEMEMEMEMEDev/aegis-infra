#!/usr/bin/env bash
# harness/runner.sh — el verificador verificándose.
#
# El runner promete tres cosas que ningún check puede garantizar por su
# cuenta: que un check mudo es rojo, que un check que se contradice es
# un bug (y no un veredicto), y que --only no invente selecciones. Si
# alguna se rompe, TODOS los checks pasan a valer menos — por eso esto
# corre antes que ellos.
set -u
: "${AEGIS_ROOT:?}"
FALLOS=0
ok()  { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
mal() { printf '  \033[1;31m✗\033[0m %s\n' "$*"; FALLOS=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/libexec" "$TMP/verify/checks" "$TMP/verify/teeth"
cp "$AEGIS_ROOT/libexec/aegis-verify" "$TMP/libexec/"
cp "$AEGIS_ROOT/verify/lib.sh" "$TMP/verify/"
V() { AEGIS_ROOT="$TMP" "$TMP/libexec/aegis-verify" "$@"; }

# 1. un check normal: PASS → rc 0
cat > "$TMP/verify/checks/001-de-mentira.sh" <<'C'
# titulo: check de mentira que pasa
check() { pass "todo bien"; }
C
V --only 001 --profile cloudflare >/dev/null 2>&1
[[ $? == 0 ]] && ok "un check que pasa da rc 0" || mal "un check que pasa NO dio rc 0"

# 2. un check que falla → rc 1
cat > "$TMP/verify/checks/002-rojo.sh" <<'C'
# titulo: check que falla
check() { fail "algo falta"; }
C
V --only 002 --profile cloudflare >/dev/null 2>&1
[[ $? == 1 ]] && ok "un check que falla da rc 1" || mal "un check que falla NO dio rc 1"

# 3. EL RENGLÓN QUE FALTA: un check que no dice nada NO es verde
cat > "$TMP/verify/checks/003-mudo.sh" <<'C'
# titulo: check mudo (no emite veredicto)
check() { local x=1; : "$x"; }
C
SAL="$(V --only 003 --profile cloudflare 2>&1)"; RC=$?
[[ $RC == 1 ]] && grep -q 'no emitió veredicto' <<<"$SAL" \
    && ok "un check mudo es FAIL, no silencio" \
    || mal "un check mudo NO fue rojo (rc=$RC)"

# 4. dos veredictos = bug del verificador (exit 3), no un resultado
cat > "$TMP/verify/checks/004-doble.sh" <<'C'
# titulo: check que emite dos veredictos
check() { pass "una"; fail "y otra"; }
C
SAL="$(V --only 004 --profile cloudflare 2>&1)"; RC=$?
[[ $RC == 3 ]] && grep -q 'emitió 2 veredictos' <<<"$SAL" \
    && ok "dos veredictos = exit 3 (bug del verificador)" \
    || mal "dos veredictos NO dieron exit 3 (rc=$RC)"

# 5. un archivo sin check() no es un check
cat > "$TMP/verify/checks/005-sin-funcion.sh" <<'C'
# titulo: archivo que no define check()
echo "hola"
C
V --only 005 --profile cloudflare >/dev/null 2>&1
[[ $? == 3 ]] && ok "un archivo sin check() = exit 3" || mal "un archivo sin check() NO dio exit 3"

# 6. un check que revienta a mitad no pasa por verde
cat > "$TMP/verify/checks/006-explota.sh" <<'C'
# titulo: check que revienta antes de emitir
check() { echo "$NO_EXISTE_ESTA_VARIABLE"; pass "nunca llego"; }
C
V --only 006 --profile cloudflare >/dev/null 2>&1
[[ $? == 1 ]] && ok "un check que revienta antes del veredicto es rojo" || mal "un check que revienta NO fue rojo"

# 7. --only con número inexistente no corre nada EN SILENCIO
V --only 999 --profile cloudflare >/dev/null 2>&1
[[ $? == 3 ]] && ok "--only inexistente = error, no corrida vacía" || mal "--only inexistente NO dio error"

# 8. sin checks, el verificador no puede estar verde
mkdir -p "$TMP/vacio/verify/checks" "$TMP/vacio/libexec"
cp "$TMP/libexec/aegis-verify" "$TMP/vacio/libexec/"; cp "$TMP/verify/lib.sh" "$TMP/vacio/verify/"
AEGIS_ROOT="$TMP/vacio" "$TMP/vacio/libexec/aegis-verify" >/dev/null 2>&1
[[ $? == 3 ]] && ok "cero checks NO es verde" || mal "cero checks dio verde"

# 9. los dientes: un rojo que no muerde se denuncia
cat > "$TMP/verify/checks/007-con-diente.sh" <<'C'
# titulo: check con diente
check() { grep -q 'centinela' "$AEGIS_ROOT/verify/marca.txt" && pass "la marca está" || fail "falta la marca"; }
C
echo "centinela" > "$TMP/verify/marca.txt"
cat > "$TMP/verify/teeth/007.sh" <<'C'
rojo_1()    { sed -i 's/centinela/otra-cosa/' "$AEGIS_ROOT/verify/marca.txt"; }
control_1() { printf 'un comentario nuevo\n' >> "$AEGIS_ROOT/verify/marca.txt"; }
C
V --only 007 --teeth --profile cloudflare >/dev/null 2>&1
[[ $? == 0 ]] && ok "un diente que muerde pasa --teeth" || mal "un diente legítimo NO pasó --teeth"

cat > "$TMP/verify/teeth/007.sh" <<'C'
rojo_1() { printf 'esto no rompe nada\n' >> "$AEGIS_ROOT/verify/marca.txt"; }
C
SAL="$(V --only 007 --teeth --profile cloudflare 2>&1)"; RC=$?
[[ $RC == 1 ]] && grep -q 'NO muerde' <<<"$SAL" \
    && ok "un diente que NO muerde se denuncia" \
    || mal "un diente inútil pasó como bueno (rc=$RC)"

# 10. un control que se pone rojo también se denuncia
cat > "$TMP/verify/teeth/007.sh" <<'C'
rojo_1()    { sed -i 's/centinela/otra-cosa/' "$AEGIS_ROOT/verify/marca.txt"; }
control_1() { : > "$AEGIS_ROOT/verify/marca.txt"; }
C
SAL="$(V --only 007 --teeth --profile cloudflare 2>&1)"; RC=$?
[[ $RC == 1 ]] && grep -q 'se puso ROJO' <<<"$SAL" \
    && ok "un control que se pone rojo se denuncia" \
    || mal "un check que muerde de más pasó (rc=$RC)"

exit $FALLOS
