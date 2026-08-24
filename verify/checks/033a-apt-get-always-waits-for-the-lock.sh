# title: every apt-get of the phases waits for the dpkg lock
# origin: verify-static.sh (v2) ══ 33, part a — split in v3
check() {
# unattended-upgrades holds the lock at boot → half-done installs
# (run #10).
BAD_APT="$(grep -rn 'apt-get' "$PHASES/" | nc_hits | grep -v 'DPkg::Lock::Timeout' || true)"
if [[ -n "$BAD_APT" ]]; then fail "apt-get WITHOUT waiting for the lock:"$'\n'"$BAD_APT"
else pass "every apt-get with DPkg::Lock::Timeout (via apt_locked or inline)"; fi
}
