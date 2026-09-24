# teeth of check 235 — what a base writes and what its test mounts.

N235="$AEGIS_ROOT/seed/platform/base-images/nginx"
P235="$AEGIS_ROOT/seed/platform/base-images/php"

# the nginx member as it was on 2026-09-24: /tmp not declared
red_1() { sed -i '\|^  - /tmp$|d' "$N235/runtime-test.yaml"; }

# a temp path moved somewhere nobody mounts
red_2() { sed -i 's|^\(\s*client_body_temp_path\s\+\)/tmp/client_temp;|\1/var/lib/nginx/client_temp;|' "$P235/nginx.conf"; }

# the pid moved to a path under the read-only root that no runtime test mounts
red_3() { sed -i 's|^pid\(\s\+\)/tmp/nginx.pid;|pid\1/var/run/nginx.pid;|' "$N235/nginx.conf"; }

# control: a comment naming another path is prose, not a directive
control_1() { sed -i '1i # pid /var/lib/nginx/nginx.pid; was the package default' "$N235/nginx.conf"; }
