# titulo: todo destino de escritura del init en platform/ sobrevive a un clone limpio
# origen: verify-static.sh (v2) ══ 84
check() {
# Corrida en Linux nativo (2026-07-25): la fase 15 hace
# `mv "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"` y
# platform/tofu/secrets/ NO existía tras un `git clone` — git no
# versiona directorios vacíos y ese era el ÚNICO destino de escritura
# sin ningún archivo versionado. Con errexit vivo (fix de la #15) el
# mv mató la fase en seco, antes de producir un solo cifrado.
# Latente 18 corridas: la VM se poblaba COPIANDO el directorio del
# operador (que ya tenía el dir de una corrida previa), no clonando;
# el primer clone virgen lo destapó. Clase: "las referencias
# estáticas deben existir" (#3) + "estado sucio: greenfield != limpio"
# (failure-modes.md). El check resuelve las variables de ruta de las
# fases y exige que CADA directorio destino tenga al menos un archivo
# VERSIONADO — un dir que solo existe en el árbol del operador no
# cuenta, que es exactamente lo que engañó 18 corridas.
# SEGUNDA instancia (misma corrida, fase 80): `cp ...
# "$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub"` — mismo bug,
# OTRA variable de ruta. La 1ª versión de este check solo miraba
# $B/$TOKENS_DIR/$IU_DIR y dio verde igual: un check angosto es un
# check que MIENTE. Por eso ahora la lista de variables se DERIVA
# del código (las que apuntan al repo de plataforma) en vez de estar
# hardcodeada, y cualquier variable nueva sin mapear es FAIL.
# SEGUNDA instancia (misma corrida, fase 80): `cp ...
# "$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub"` — mismo bug,
# OTRA variable de ruta. La 1ª versión de este check solo miraba
# $B/$TOKENS_DIR/$IU_DIR y dio verde igual: un check angosto es un
# check que MIENTE, y esta es la meta-clase "mención != uso" aplicada
# al propio verificador. Por eso las rutas se RESUELVEN del código
# (asignaciones VAR="$OTRA/sub" encadenadas, sembradas con
# PLATFORM_DIR) en vez de estar hardcodeadas: una variable nueva
# entra sola al check. Lo que no se puede resolver estáticamente
# (interpolación dinámica) se REPORTA, nunca se ignora en silencio.
D84=""
_OUT84="$(python3 - "$AEGIS_ROOT" <<'PY84' 2>&1
import os, re, sys, glob
root = sys.argv[1]
files = sorted(glob.glob(os.path.join(root, "init/phases/*.sh")) +
               glob.glob(os.path.join(root, "init/lib/*.sh")))
text = {f: open(f, encoding="utf-8", errors="replace").read() for f in files}
# 1) mapa de variables -> ruta relativa al repo, resolviendo cadenas
# $PLATFORM_DIR es el directorio de TRABAJO de la instancia, que desde
# 2026-08-05 ya no está versionado (es el checkout del repo de la
# instancia). Su contraparte versionada —la que un clone virgen SÍ
# trae, y de la que la fase 10 lo siembra— es la semilla. El
# invariante no cambió: todo destino de escritura tiene que existir
# tras un git clone. Cambió dónde se comprueba.
resolved = {"PLATFORM_DIR": "seed/platform"}
assign = re.compile(r'^\s*([A-Z_]+)="\$\{?([A-Z_]+)\}?(/[^"]*)?"\s*$', re.M)
dynamic = []
for _ in range(5):                      # punto fijo: cadenas de 5 saltos
    for f, t in text.items():
        for var, base, sub in assign.findall(t):
            if base not in resolved or var in resolved:
                continue
            if "${" in (sub or "") or "$(" in (sub or ""):
                dynamic.append(var); continue
            resolved[var] = (resolved[base] + (sub or "")).rstrip("/")
# variables que apuntan a platform/ pero NO se pudieron resolver:
for f, t in text.items():
    for var, base, sub in assign.findall(t):
        if base == "PLATFORM_DIR" and var not in resolved:
            dynamic.append(var)
# 2) todos los usos: $VAR y $VAR/subruta
targets = set()
use = re.compile(r'\$\{?([A-Z_]+)\}?(/[A-Za-z0-9._/-]+)?')
for f, t in text.items():
    for var, sub in use.findall(t):
        if var not in resolved:
            continue
        p = (resolved[var] + (sub or "")).rstrip("/")
        if p and p != "seed/platform":
            targets.add(p)
# $APP_VALUES = "$PLATFORM_DIR/${CONTRACT[4]}", y CONTRACT sale de
# parsear core.yaml (contrato de adopción, FUENTE ÚNICA — fase 30).
# Se resuelve desde esa misma fuente en vez de excluirlo por nombre:
# si core.yaml cambia de forma, este check FALLA en vez de quedarse
# ciego, que es justo lo que dejó pasar la 2ª instancia del bug.
dynamic = set(dynamic)
if "APP_VALUES" in dynamic:
    try:
        import yaml
        core = os.path.join(root, "seed/platform/k8s/argocd-apps/core.yaml")
        docs = [d for d in yaml.safe_load_all(open(core)) if d]
        app = next(d for d in docs if d.get("kind") == "Application"
                   and d["metadata"]["name"] == "argocd")
        src = next(s for s in app["spec"]["sources"] if "chart" in s)
        vf = src["helm"]["valueFiles"][0]
        assert vf.startswith("$values/"), f"valueFiles sin ref $values: {vf}"
        resolved["APP_VALUES"] = "seed/platform/" + vf[len("$values/"):]
        targets.add(resolved["APP_VALUES"])     # entra al verificado
        dynamic.discard("APP_VALUES")
    except Exception as e:
        print("ERR no pude resolver APP_VALUES desde core.yaml:", e)
for v in sorted(dynamic):
    print("DYN", v)
for p in sorted(targets):
    # el destino de la escritura es el directorio contenedor; si el
    # último segmento no tiene extensión, el path mismo también puede
    # ser un directorio destino (cp/mkdir), así que se exigen ambos.
    d = os.path.dirname(p)
    if d and d != "platform":
        print("DIR", d)
    if "." not in os.path.basename(p):
        print("DIR", p)
PY84
)"
# El instrumento de este check es git: pregunta qué archivos están
# VERSIONADOS. Sin repositorio no hay nada que preguntar, y responder
# «ninguno» sería confundir «no pude medir» con «está mal» — el error
# que toda la doctrina de la casa existe para no cometer. Pasó de
# verdad el 2026-08-23: el producto se copió a la máquina de
# desarrollo con rsync sin .git y este check reportó 26 directorios
# rotos que estaban perfectos.
if ! git -C "$AEGIS_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    skip "no hay repositorio git en $AEGIS_ROOT: sin él no se puede saber qué archivos sobreviven a un clone (esto NO es un visto bueno)"
    return
fi
_n84=0
while read -r _k84 _p84; do
    case "$_k84" in
      DYN) D84="$D84 \$$_p84 apunta a platform/ con interpolación dinámica — el check NO puede verificar su destino (resolvelo o documentalo);" ;;
      DIR)
        _n84=$((_n84 + 1))
        if [[ ! -d "$AEGIS_ROOT/$_p84" ]]; then
            D84="$D84 $_p84 no existe en el árbol;"
        elif [[ -z "$(git -C "$AEGIS_ROOT" ls-files -- "$_p84" 2>/dev/null)" ]]; then
            D84="$D84 $_p84 NO tiene ningún archivo versionado — no sobrevive a un git clone (poné un .gitkeep);"
        fi ;;
      *) [[ -n "$_k84" ]] && D84="$D84 el resolvedor de rutas falló: $_k84 $_p84;" ;;
    esac
done <<< "$(printf '%s\n' "$_OUT84" | sort -u)"
[[ "$_n84" -ge 20 ]] || D84="$D84 solo $_n84 destinos detectados (esperados >=20) — el resolvedor dejó de encontrar rutas, el check quedó ciego;"
if [[ -n "$D84" ]]; then fail "clone-limpio:$D84"
else pass "los $_n84 destinos de escritura del init en platform/ tienen archivos versionados (sobreviven a git clone)"; fi
}
