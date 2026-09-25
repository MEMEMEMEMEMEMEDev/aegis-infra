# teeth of check 250 — kaniko without compressed caching.
T250="$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"

# the flag gone: the template as it was on 2026-09-24
red_1() { sed -i '/--compressed-caching=false \\/d' "$T250"; }

# the flag only in a comment, not on the call
red_2() { sed -i 's/^              --compressed-caching=false \\$/              \\/' "$T250"; }

# turned the other way
red_3() { sed -i 's/--compressed-caching=false/--compressed-caching=true/' "$T250"; }

# control: the flag moved to another position in the same call
control_1() { sed -i '/--compressed-caching=false \\/d; s|^              --no-push \\$|              --compressed-caching=false \\\n              --no-push \\|' "$T250"; }
