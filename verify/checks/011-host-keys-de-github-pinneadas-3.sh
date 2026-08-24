# title: host keys de GitHub pinneadas (3)
# origen: verify-static.sh (v2) ══ 11
check() {
HK="$(grep -c 'github.com ' "$P/k8s/base/platform/jenkins/values.yaml" || true)"
[[ "$HK" -ge 3 ]] && pass "host keys: $HK pinneadas" \
                  || fail "host keys: $HK (< 3)"
}
