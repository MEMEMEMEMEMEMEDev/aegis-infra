# teeth for check 152 (no line continuation is cancelled by what follows
# it on the same line)
#
# red_1 is the regression itself, byte for byte: what libexec/aegis-rotate
# carried between 2026-08-29 03:xx and the commit that removed it, and
# what killed the three negative calls of `aegis rotate check` without
# changing a single verdict on screen.
#
# Every red writes into a file that IS swept, because verify/teeth/ is
# not — the check says so and says why. That is not a convenience here,
# it is a requirement: a tooth that reintroduces this bug has to write
# the grapheme down literally, and this file therefore carries it four
# times.

# ── the regression, exactly as it was ────────────────────────────────
# A heredoc and not a printf, on purpose: the physical line has to reach
# the target file with the same bytes the patch wrote — backslash, two
# spaces, the scanner marker — and a printf format is one more place for
# them to be rewritten by accident.
red_1() {
    cat >> "$AEGIS_ROOT/libexec/aegis-rotate" <<'EOF'

check_tooth_of_152() {
    code_bad="$(curl_access -s -o /dev/null -w '%{http_code}' -X POST \  # gitleaks:allow
        --max-time 30 -d @"$p.bad-body" "https://argocd.$ROOT_DOMAIN/api/v1/session")"
}
EOF
}

# ── the tab spelling ────────────────────────────────────────────────
# The same death with a character that no diff, no review and no editor
# ruler shows. It goes into lib/common.sh — a different file and a
# different half of the corpus is not the point here; the point is that
# the recogniser must not be keyed to a single blank.
red_2() {
    printf '\nrun_cmd cp -a "$SRC/." "$DST/" \\\t# the tab spelling of the same escaped blank\n    --no-preserve=ownership\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# ── the comment glued to its hash ───────────────────────────────────
# No blank after the `#`. It reads even less like a comment and bash
# opens one all the same. In libexec/aegis-image, which is a command
# with no extension: it is swept by its shebang, not by its name, and if
# the recogniser ever forgot the shebang half this red is what says so.
red_3() {
    printf '\ncurl -fsS --max-time 20 "$REGISTRY/v2/$name/manifests/$tag" \\  #no blank after the hash\n    -H "Accept: application/vnd.oci.image.manifest.v1+json"\n' \
        >> "$AEGIS_ROOT/libexec/aegis-image"
}

# ── the other half of the class: trailing blanks ────────────────────
# No comment at all. The backslash escapes three spaces, the command
# ends one line early, and the continuation line runs on its own. This
# is the spelling an editor produces by itself, and it is invisible in
# every review tool there is.
red_4() {
    printf '\nrun sops -d --input-type binary "$enc" \\   \n    > "$out"\n' \
        >> "$AEGIS_ROOT/libexec/state/backup"
}

# ── the comfortable way to switch the check off ─────────────────────
# Not a mutation of the artifact but of the instrument: the recogniser
# stops recognising shell scripts, the sweep finds nothing, and a check
# that reported «0 files swept» as green would be the very illness it
# was written against. This red is the only proof that the empty-sweep
# guard is real.
red_5() {
    python3 - "$AEGIS_ROOT/verify/checks/152-no-continuation-is-cancelled-by-what-follows-it.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
anchor = '    if f.suffix == ".sh":\n        return True\n'
assert t.count(anchor) == 1
open(p, "w").write(t.replace(anchor, '    return False\n', 1))
PY
}

# ── controls ────────────────────────────────────────────────────────
# The legitimate continuation: the backslash is the last character of
# the line and the next line is its tail. This is the single most common
# shape in the tree — hundreds of lines — and a check that bit it would
# turn every file red at once.
control_1() {
    printf '\nrun_cmd kubectl -n argocd get deploy argocd-server \\\n    -o jsonpath='"'"'{.status.readyReplicas}'"'"'\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# The comment that TELLS the story. A whole line of comment carrying the
# exact grapheme, which is what check 152's own header does twice and
# what every note about this bug will have to do. If this control turned
# red the class could not be documented anywhere in the tree, and the
# check would be switched off within a week.
control_2() {
    cat >> "$AEGIS_ROOT/lib/common.sh" <<'EOF'

# the patch that broke it wrote:  curl -sS "$url" \  # gitleaks:allow
# and bash read the backslash as an escaped blank, not as a newline.
EOF
}

# A trailing comment after code that does NOT end in a backslash: the
# ordinary way half this tree annotates a line. Nothing is lost, and the
# check must not confuse «there is a comment here» with «a continuation
# died here».
control_3() {
    printf '\nAEGIS_TOOTH_TIMEOUT=30   # seconds; the ordinary trailing comment\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# The EVEN run of backslashes, which is the rule that makes this check
# more than a grep. `\\` is one literal backslash argument, the command
# genuinely ends on this line, and nothing was lost — measured:
# `printf "[%s]" a b \\  # note` prints `[a][b][\]`. Flagging it would be
# asking an author to change code that does exactly what it says.
control_4() {
    printf '\nprintf "%%s\\n" "$prefix" \\\\  # a literal backslash argument, not a continuation\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# ── the shell that lives inside a YAML block scalar ──────────────────
# The half the check was blind to until 2026-08-29: `ansible.builtin.shell`
# with `args: {executable: /bin/bash}`, which already carries two live
# continuations. The marker goes on the pipe of the k3s installer — the
# exact spelling of the founding regression, in the exact place a patch
# would put it. Measured with pyyaml before writing this: the literal
# block scalar hands `| \` and the newline to bash byte for byte, so
# what dies here is a real install, not a lexical curiosity.
red_6() {
    python3 - "$AEGIS_ROOT/seed/platform/ansible/playbooks/install-k3s.yml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
anchor = "        curl -sfL https://get.k3s.io | \\\n"
assert t.count(anchor) == 1
open(p, "w").write(t.replace(anchor, "        curl -sfL https://get.k3s.io | \\  # gitleaks:allow\n", 1))
PY
}

# The other spelling of the same half, and the other way in: not a
# module that NAMES a shell but a container that declares one —
# `command: ["/bin/sh", "-c"]` with the program in `args:`. Trailing
# blanks and no comment at all, on the `cat` that builds the trust
# bundle: the probe would come up with half a bundle and blame the site.
# If the `/bin/sh -c` recogniser is ever keyed to the module names
# alone, this red is what says so.
red_7() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/blackbox.yaml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
anchor = "              cat /etc/ssl/certs/ca-certificates.crt /etc/blackbox/ca/ca.crt \\\n"
assert t.count(anchor) == 1
open(p, "w").write(t.replace(anchor, anchor.rstrip("\n") + "   \n", 1))
PY
}

# The comfortable way to switch the YAML half off, and the twin of
# red_5. Nothing in the clean tree is red, so a recogniser that stops
# recognising block scalars would leave the check GREEN and no red could
# ever catch it — only the guard can. It fires on the count of YAML
# files, which is the one number that cannot be zero in a GitOps product
# and does not depend on any playbook still having a shell task in it.
red_8() {
    python3 - "$AEGIS_ROOT/verify/checks/152-no-continuation-is-cancelled-by-what-follows-it.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
anchor = '    elif f.suffix in (".yml", ".yaml"):\n'
assert t.count(anchor) == 1
open(p, "w").write(t.replace(anchor, '    elif False:\n', 1))
PY
}

# ── the false positive that cost the first review ───────────────────
# A quoted string of ONE line carrying the grapheme. bash loses nothing
# here — measured: the whole string prints, hash and backslash included,
# and the next line runs — but the lexer that did not track quotes
# painted it red, and the header explained the mistake with a structural
# claim that was simply false. Every note about this bug written inside
# an `echo`, a `msg` or the text of a `fail` has this shape, so a check
# that bites it bites its own documentation.
control_5() {
    printf '\nmsg "the patch wrote: curl -sS \\  # gitleaks:allow — and bash read the backslash as a space"\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# The legitimate continuation INSIDE a block scalar. The YAML half must
# arrive with the same rule as the scripts and not with a blunter one: a
# playbook whose every continued line turned red would be reverted the
# same day, and the half would be lost with it.
control_6() {
    python3 - "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
anchor = "        set -o pipefail\n"
assert t.count(anchor) >= 1
open(p, "w").write(t.replace(anchor, "        set -o pipefail\n        kubectl version --client \\\n          --output=json >/dev/null\n", 1))
PY
}

# The trailing-blank twin of control_5: a backslash and three blanks
# ending a line INSIDE a double-quoted string that closes on the line
# below. Measured in bash — the backslash, the blanks and the newline
# all come out in the string and the next line runs — so this must stay
# green. Without it, the correction of the comment half could be undone
# on the trailing-blank half and no tooth would notice.
control_7() {
    printf '\nmsg "the age key is IRREPLACEABLE \\   \nand nothing below this line is lost"\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}
