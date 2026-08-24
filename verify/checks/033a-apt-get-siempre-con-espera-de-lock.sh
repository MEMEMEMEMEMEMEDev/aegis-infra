# titulo: todo apt-get de las fases espera el lock de dpkg
# origen: verify-static.sh (v2) ══ 33, parte a — partida en v3
check() {
# unattended-upgrades tiene el lock al boot → installs a medias
# (corrida #10).
BAD_APT="$(grep -rn 'apt-get' "$FASES/" | nc_hits | grep -v 'DPkg::Lock::Timeout' || true)"
if [[ -n "$BAD_APT" ]]; then fail "apt-get SIN espera de lock:"$'\n'"$BAD_APT"
else pass "todo apt-get con DPkg::Lock::Timeout (via apt_locked o inline)"; fi
}
