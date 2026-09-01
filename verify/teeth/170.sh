# teeth of check 170 — a phase that builds a file the seed ships says
# whether the instance's copy differs.

# THE STATE THE ARTIFACT WAS IN until 2026-09-01: nothing compared, so
# a fix made in the product could fail to reach a live instance and
# say nothing about it. Three times in one day, and the third cost a
# whole cycle on an error that had already been corrected.
red_1() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'^seed_drift_report\(\) \{.*?\n\}\n', '', s, count=1, flags=re.S | re.M)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# present and INERT: it exists and compares nothing, so it can only
# ever report agreement. Structure without measurement.
red_2() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'^seed_drift_report\(\) \{.*?\n\}\n',
           'seed_drift_report() {\n    return 0\n}\n', s, count=1, flags=re.S | re.M)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# THE DANGEROUS ONE: reporting is fine, copying is not. The instance's
# working tree is the operator's, and overwriting it is precisely what
# seed_platform_dir refuses to do for a reason.
red_3() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('    [[ -n "$drift" ]] || return 0',
              '    for rel in $drift; do cp "$AEGIS_ROOT/seed/platform/$rel" "$PLATFORM_DIR/$rel"; done\n    [[ -n "$drift" ]] || return 0', 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# said too late: after the first build is fired, which is twenty
# minutes after it was worth knowing.
red_4() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r'^seed_drift_report [^\n]*\n(?:[ ]+[^\n]*\n)*', s, re.M)
blk = m.group(0)
s = s.replace(blk, "", 1).rstrip("\n") + "\n\n" + blk
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# control: the helper's own OUTPUT is a `cp` suggested to the operator,
# and the first version of this check read that suggestion as the
# helper copying. Eighth time in one day that prose was read as code.
control_1() {
    printf '\n# note: to reconcile, cp the seed file over the instance one by hand.\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# control: prose in the phase naming the report changes nothing.
control_2() {
    printf '\n# note: seed_drift_report only says it, it never copies.\n' \
        >> "$AEGIS_ROOT/init/phases/87-ai.sh"
}
