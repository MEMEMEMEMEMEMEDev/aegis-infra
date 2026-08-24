# titulo: buildah rootless: userns habilitado + coherencia fuse (bug D)
# origen: verify-static.sh (v2) ══ 26
check() {
# Corrida #8: el pod de buildah (idéntico al v1 VERDE en WSL2) murió
# en Ubuntu 24.04 con "failed to make mount private: permission
# denied" — Ubuntu >= 23.10 bloquea unprivileged userns por default
# (apparmor). El fix es de PLATAFORMA (sysctl en bootstrap-host +
# gate que lo ejerce en fase 20), NO tocar el manifest probado.
# a) el sysctl está en el bootstrap — anclado a la tarea sysctl REAL
#    (`name: kernel...`), no a cualquier mención: el stat del path
#    /proc/sys también contiene el string (el teeth lo reveló):
D26=""
# $BH nacía en el check 24 y este lo usaba «prestado»: uno de los
# cuatro acoplamientos que el archivo único de v2 escondía. Cada check
# calcula lo suyo (o lo pide a lib.sh) — si no, --only 26 medía el aire.
BH="$P/ansible/playbooks/bootstrap-host.yml"
nc "$BH" | grep -qE 'name:\s*kernel\.apparmor_restrict_unprivileged_userns' \
    || D26="$D26 falta el sysctl userns en bootstrap-host;"
# b) la fase 20 lo EJERCE (unshare real, no proxy):
nc "$FASES/20-k3s.sh" | grep -q 'unshare --user' \
    || D26="$D26 falta el gate userns-sin-privilegios en fase 20;"
# c) W-05: buildah ELIMINADO — kaniko construye SIN privilegios (extrae
#    capas al FS directo, no hace los mounts que mataron a buildah
#    rootless en #8/#9). Los Jenkinsfiles NO deben tener privileged ni
#    /dev/fuse; jenkins-system deja de ser PSS privileged. El escape al
#    nodo desde el build (código no confiable vía npm ci) queda cerrado.
#    (mención≠uso: se chequea 'privileged: true'/'path: /dev/fuse', que
#    NO aparecen en comentarios, no el string 'buildah'.)
# Estos dos salían de $ROOT/platform — la INSTANCIA, no el artefacto.
# Es la trampa que la cabecera del verificador de v2 denunciaba en su
# propio encabezado y que igual se coló tres veces (26, 90, 91): con
# producto e instancia en la misma carpeta, la ruta equivocada daba el
# mismo resultado y nadie lo veía. Acá miran la SEED.
for jf in "$P"/ci-images/Jenkinsfile \
          "$P"/docs/protocols/templates/Jenkinsfile.app; do
    b="$(basename "$(dirname "$jf")")/$(basename "$jf")"
    grep -q 'privileged: true' "$jf" && D26="$D26 $b tiene privileged:true (W-05: el build no escala al nodo);"
    grep -q 'path: /dev/fuse'   "$jf" && D26="$D26 $b monta /dev/fuse (hostPath);"
    grep -q 'kaniko'            "$jf" || D26="$D26 $b no usa kaniko (¿volvió buildah?);"
done
grep -q 'pod-security.kubernetes.io/enforce: privileged' \
     "$P/k8s/base/platform/jenkins-secrets/bundle.yaml" \
    && D26="$D26 jenkins-system sigue PSS privileged (el build escaparía al nodo);"
if [[ -n "$D26" ]]; then fail "build-sin-privilegios:$D26"
else pass "build SIN privilegios (W-05): kaniko en ambos Jenkinsfiles, sin /dev/fuse, jenkins-system PSS baseline; userns sysctl+gate presentes"; fi
}
