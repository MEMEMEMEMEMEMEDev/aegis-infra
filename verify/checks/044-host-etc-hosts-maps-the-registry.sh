# title: the host's /etc/hosts maps the registry (H2 #13 — the kubelet does not resolve .svc)
# origin: verify-static.sh (v2) ══ 44
check() {
RHT44="$(nc "$P/ansible/playbooks/registry-host-trust.yml")"
if echo "$RHT44" | grep -q 'path: /etc/hosts' \
   && echo "$RHT44" | grep -q 'registry_cluster_ip }} registry.registry-system.svc.cluster.local'; then
    pass "registry-host-trust writes the name→ClusterIP mapping into /etc/hosts"
else
    fail "the registry's /etc/hosts entry is missing (containerd resolves the server-name BEFORE the mirror-host — the pull dies in DNS)"
fi

# HERE WAS check 45: the CA mounted as a LOOSE FILE in /etc/ssl/certs/
# of the Image Updater. It went away with the component in #59.
#
# The lesson is not lost either: the OpenSSL trust store does NOT read
# subdirectories, so mounting the CA in a subdir gives "x509 unknown
# authority" with the certificate sitting right there. And the
# volumeMount needs subPath, or it mounts a directory ON TOP of
# /etc/ssl/certs and covers the whole trust store. It applies to any
# component that has to trust the internal CA.
}
