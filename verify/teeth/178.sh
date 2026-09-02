# teeth of check 178 — a file of the seed reaches the instance
# rendered, or it does not reach it.

# THE STATE THE ARTIFACT WAS IN until the night of 2026-09-01: the
# drift report named the file that differed and told the operator to
# `cp` the seed's copy over the instance's. Following that advice on
# k8s/base/platform/jenkins-secrets/bundle.yaml put __ROOT_DOMAIN__
# back into Jenkins's route and took jenkins.<domain> off Traefik.
red_1() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '        log_warn "    seed_fetch $rel   # then commit and push"\n'
new = ('        log_warn "    cp \\"\\$AEGIS_ROOT/seed/platform/$rel\\" '
       '\\"\\$PLATFORM_DIR/$rel\\"   # then commit and push"\n')
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PYEOF
}

# the path exists and still copies, but the render is gone: a fetch
# that only copies IS the bare cp, with a nicer name.
red_2() {
    sed -i '/^    render_platform_placeholders$/d' "$AEGIS_ROOT/lib/common.sh"
}

# the render happens BEFORE the copy. Present, and useless: what lands
# afterwards keeps every placeholder it was shipped with. Order is the
# property, not the mention.
red_3() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
call = "    render_platform_placeholders\n"
anchor = '    local rel seedf instf\n    for rel in "$@"; do\n        seedf="$AEGIS_ROOT/seed/platform/$rel"\n'
assert s.count(call) == 1 and s.count(anchor) == 1
s = s.replace(call, "", 1)
open(p, "w", encoding="utf-8").write(s.replace(anchor, call + anchor, 1))
PYEOF
}

# a NEW consumer copies one file of the seed over the instance's,
# somewhere else entirely. The set of places that copy is derived from
# the tree, so a place nobody thought of is still measured.
red_4() {
    cat > "$AEGIS_ROOT/libexec/aegis-freshen" <<'EOF'
#!/usr/bin/env bash
# aegis-summary: Brings a file of the seed over to the instance
# aegis-group:   dev
set -euo pipefail
source "$AEGIS_ROOT/lib/paths.sh"
cp -a "$AEGIS_ROOT/seed/platform/$1" "$PLATFORM_DIR/$1"
EOF
    chmod +x "$AEGIS_ROOT/libexec/aegis-freshen"
}

# the birth copy stops refusing to write onto a tree with a history:
# the one unrendered copy in the artifact was legitimate ONLY because
# it never lands on a rendered file, and that is the whole reason it is
# not an exception written down by name.
red_5() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '''    if [[ -d "$PLATFORM_DIR/.git" ]]; then
        log_info "platform/ is already an instance (it has .git): NOT seeding from the seed"
        return 0
    fi
'''
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, "", 1))
PYEOF
}

# the scanner broken: a scan that dies has to take the check with it,
# never wave it through.
red_6() {
    printf '\nraise SystemExit("the scanner is broken")\n' \
        >> "$AEGIS_ROOT/verify/checks/178.py"
}

# control: THE MESSAGE ITSELF, which contains the word `cp` because it
# is what the operator must NOT do — and the paragraph above the
# function spells the forbidden command out in full, with both paths.
# A check that read prose as code would accuse the very comment that
# explains the bug. Ninth time this trap has been laid in one day.
control_1() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "seed_fetch() {   # <path relative to platform/>...\n"
note = ('# note: never cp "$AEGIS_ROOT/seed/platform/$rel" "$PLATFORM_DIR/$rel"\n'
        '# by hand — that copy un-renders the file (__ROOT_DOMAIN__ came back\n'
        '# into Jenkins\'s route exactly that way).\n')
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, note + anchor, 1))
PYEOF
}

# control: one more line of ADVICE that names the bare copy in order to
# warn against it. It speaks, it does not copy.
control_2() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '    log_warn "  seed_fetch copies AND renders: a bare cp puts the seed\'s placeholders back into a rendered tree"\n'
extra = ('    log_warn "  do NOT cp \\"\\$AEGIS_ROOT/seed/platform/$rel\\" over '
         '\\"\\$PLATFORM_DIR/$rel\\": jenkins.<domain> left Traefik that way"\n')
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, anchor + extra, 1))
PYEOF
}

# control: a copy that is NOT from the seed into the instance — a
# backup of the instance's own file, taken before overwriting it. This
# rule is about one direction only, and a check that bites every `cp`
# is a check nobody can work beside.
control_3() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '        run_cmd cp -a "$seedf" "$instf"\n'
extra = '        [[ -f "$instf" ]] && run_cmd cp -a "$instf" "$instf.before-fetch"\n'
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, extra + anchor, 1))
PYEOF
}

# control: a SECOND legitimate path, brought over whole — it copies
# from the seed and renders afterwards, which is the property. The
# check derives the paths that render from the code, so a new one is
# green on arrival and the drift report's advice is measured against
# the set, not against a name typed into the check.
control_4() {
    cat >> "$AEGIS_ROOT/lib/common.sh" <<'EOF'

# brings a whole directory of the seed over, rendered (same act).
seed_fetch_dir() {   # <dir relative to platform/>
    local rel="$1"
    run_cmd mkdir -p "$PLATFORM_DIR/$rel"
    run_cmd cp -a "$AEGIS_ROOT/seed/platform/$rel/." "$PLATFORM_DIR/$rel/"
    render_platform_placeholders
}
EOF
}
