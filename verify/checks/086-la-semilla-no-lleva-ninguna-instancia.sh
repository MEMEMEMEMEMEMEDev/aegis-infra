# titulo: la semilla no lleva NINGUNA instancia horneada adentro
# origen: verify-static.sh (v2) ══ 86
check() {
# El riesgo estructural de sincronizar la semilla desde la instancia:
# el árbol vivo tiene los placeholders YA RESUELTOS (la fase 10 los
# renderiza en el sitio), así que copiar sin des-renderizar mete los
# valores de UNA instancia dentro del producto. El fallo no aparece
# acá: aparece en el arranque siguiente, en otra máquina, contra un
# repo que no existe.
#
# Ya pasó: hasta el 2026-08-11 org-canary/bundle.yaml de la semilla
# apuntaba a git@github.com:ejemplo-org/hello-aegis-v2.git. Una
# instancia nacida de esa semilla clonaba el canario de OTRO dueño.
#
# El check mide por FORMA, no contra aegis-init.conf, porque ese
# archivo está en .gitignore y en un clone limpio no existe: un check
# que dependa de él pasaría a verde por ausencia, que es exactamente la
# señal que no distingue "no hay fuga" de "no miré". La forma alcanza:
# material generado (age/PEM) no tiene ningún motivo legítimo de estar
# en el artefacto, y todo repo de GitHub del artefacto se referencia
# por __GH_OWNER__.
D86=""
# 1) material de clase-generado (dueños: fases 10 y 80). En la semilla
#    van como __AGE_PUBLIC__ / __COSIGN_PUB__ / __AEGIS_CA_PEM__.
FUGA_GEN="$(grep -rlE 'age1[0-9a-z]{20,}|-----BEGIN (CERTIFICATE|PUBLIC KEY|EC PRIVATE KEY)-----' \
            "$P" 2>/dev/null || true)"
[[ -n "$FUGA_GEN" ]] && D86="$D86 material generado (age/PEM) versionado en la semilla: $(echo "$FUGA_GEN" | tr '\n' ' ');"
# 2) todo dueño de repo GitHub del artefacto es el placeholder. Se
#    excluye docs/: la prosa nombra los repos por default a propósito.
#    El patrón exige forma de REPO (esquema + dueño + nombre): sin el
#    `/repo` final este mismo check leía `https://api.github.com/meta`
#    —un endpoint de la API, en un comentario— como si fuera un dueño.
DUENOS="$(grep -rhoE '(git@|https://)github\.com[:/][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$P" \
          --include='*.yaml' --include='*.yml' --include='*.tf' \
          --include='*.tpl' --include='*.j2' --include='*.sh' 2>/dev/null \
          | sed -E 's|.*github\.com[:/]||; s|/.*||' | sort -u | grep -v '^__GH_OWNER__$' || true)"
[[ -n "$DUENOS" ]] && D86="$D86 dueño de repo GitHub literal en manifiestos (debería ser __GH_OWNER__): $(echo "$DUENOS" | tr '\n' ' ');"
# 3) refuerzo cuando SÍ hay config local: los valores que distinguen a
#    esta instancia son los que DIFIEREN del default del .example — uno
#    igual al default no identifica a nadie y no es fuga.
# El conf de la INSTANCIA (02 §1): en v2 vivía dentro del producto y
# esta comparación funcionaba sola. Con el corte producto/instancia hay
# que ir a buscarlo — si no, el sub-check más fuerte (contrastar los
# valores REALES de esta máquina contra el artefacto) se apagaba solo y
# el check pasaba «por forma» sin decir que había perdido la mitad de
# su alcance. Lo reveló su diente.
CONF86="${AEGIS_CONF:-${AEGIS_HOME:-$HOME/aegis}/aegis.conf}"
if [[ -f "$CONF86" ]]; then
    N86=0
    for k in GH_OWNER PLATFORM_REPO APP_REPO ROOT_DOMAIN REGISTRY_CLUSTER_IP ACME_EMAIL; do
        vivo="$(grep -E "^\s*$k=" "$CONF86" | head -1 | sed -E 's/^[^=]+=\s*"?([^"#]*[^"# ])"?.*/\1/')"
        ejem="$(grep -E "^\s*$k=" "$AEGIS_ROOT/init/aegis-init.conf.example" | head -1 | sed -E 's/^[^=]+=\s*"?([^"#]*[^"# ])"?.*/\1/')"
        [[ -z "$vivo" || "$vivo" == "$ejem" ]] && continue
        N86=$((N86+1))
        HIT="$(grep -rl -- "$vivo" "$P" 2>/dev/null || true)"
        [[ -n "$HIT" ]] && D86="$D86 el valor de $k de ESTA instancia aparece en: $(echo "$HIT" | tr '\n' ' ');"
    done
    EXTRA86="+ $N86 valores propios contrastados contra el .example"
else
    EXTRA86="(sin $CONF86: solo el contraste por forma)"
fi
if [[ -n "$D86" ]]; then fail "la semilla tiene una instancia adentro:$D86"
else pass "la semilla no hornea ninguna instancia: sin age/PEM versionado, todo repo por __GH_OWNER__ $EXTRA86"; fi
}
