# title: GitHub host keys pinned (3)
# origin: verify-static.sh (v2) ══ 11
check() {
HK="$(grep -c 'github.com ' "$P/k8s/base/platform/jenkins/values.yaml" || true)"
[[ "$HK" -ge 3 ]] && pass "host keys: $HK pinned" \
                  || fail "host keys: $HK (< 3)"
}
