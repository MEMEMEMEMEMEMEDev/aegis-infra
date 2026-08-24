# title: /etc/hosts del host mapea el registry (H2 #13 — kubelet no resuelve .svc)
# origen: verify-static.sh (v2) ══ 44
check() {
RHT44="$(nc "$P/ansible/playbooks/registry-host-trust.yml")"
if echo "$RHT44" | grep -q 'path: /etc/hosts' \
   && echo "$RHT44" | grep -q 'registry_cluster_ip }} registry.registry-system.svc.cluster.local'; then
    pass "registry-host-trust escribe el mapeo nombre→ClusterIP en /etc/hosts"
else
    fail "falta el /etc/hosts del registry (containerd resuelve el server-name ANTES del mirror-host — pull muere en DNS)"
fi

# ACÁ ESTABA el check 45: la CA montada como ARCHIVO SUELTO en
# /etc/ssl/certs/ del Image Updater. Se fue con el componente en #59.
#
# La lección tampoco se pierde: el trust store de OpenSSL NO lee
# subdirectorios, así que montar la CA en un subdir da "x509 unknown
# authority" teniendo el certificado ahí mismo. Y el volumeMount necesita
# subPath, o monta un directorio ENCIMA de /etc/ssl/certs y tapa todo el
# trust store. Aplica a cualquier componente que tenga que confiar en el
# CA interno.
}
