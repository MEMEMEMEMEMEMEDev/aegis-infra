# title: conf.example covers everything the phases demand
# origin: verify-static.sh (v2) ══ 10
check() {
MISSING=""
for v in ROOT_DOMAIN GH_OWNER PLATFORM_REPO APP_REPO ACME_EMAIL \
         KUBE_CONTEXT_EXPECTED REGISTRY_CLUSTER_IP AEGIS_WORKSPACE \
         CF_ACCOUNT_ID CF_ZONE_ID; do
    grep -q "^$v=" "$AEGIS_ROOT/init/aegis-init.conf.example" || MISSING="$MISSING $v"
done
if [[ -n "$MISSING" ]]; then fail "missing from conf.example:$MISSING"
else pass "conf.example complete"; fi
}
