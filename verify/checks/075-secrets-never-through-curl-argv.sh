# title: secrets NEVER through curl's argv + loose ends (W-03 / SEC-12/SEC-02)
# origin: verify-static.sh (v2) ══ 75
check() {
D75=""
# CLASS sweep: no curl in the phases carries the secret in a -H from
# argv (visible in /proc/PID/cmdline). A header with a secret goes
# through -K (a config in tmpfs 600), like jenkins.sh's netrc-by-file:
ARGV75="$(for f in "$AEGIS_ROOT"/init/phases/*.sh; do
    sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$f" | nc \
      | grep -E -- '-H +"[^"]*(Bearer|X-Auth-Key)[^"]*\$\(cat' \
      | sed "s|^|$(basename "$f"): |"
done)"
[[ -z "$ARGV75" ]] || D75="$D75 curl with a secret in a -H from argv: $ARGV75;"
grep -q -- '-K "\$cfg"' "$PHASES/15-third-parties.sh" \
    || D75="$D75 _cf_call does not use -K (curl config by file);"
grep -q -- '-K "\$_cf_cfg"' "$PHASES/25-edge-tofu.sh" \
    || D75="$D75 _cf does not use -K (curl config by file);"
grep -q "trap 'secrets_cleanup; exit 130' INT TERM" "$LIBS/secrets.sh" \
    || D75="$D75 secrets_cleanup does not fire on INT/TERM (Ctrl-C used to leave material in tmpfs);"
grep -q 'chmod 600 "\$f"' "$PHASES/25-edge-tofu.sh" \
    || D75="$D75 the tunnel's tfstate is not protected at 600 (token in the clear at 0664);"
if [[ -n "$D75" ]]; then fail "loose ends:$D75"
else pass "CF secrets through -K (not argv), shred on INT/TERM, tfstate at 600"; fi
}
