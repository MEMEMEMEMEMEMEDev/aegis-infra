# title: no message to the operator writes a command name by hand
# origin: V-103 (03 §1) — new in v3
check() {
# Class E of the register: ~155 strings with a command's name written
# by hand. Each one is a promise that ages — the day the command is
# called something else, the messages keep saying the old name, and the
# operator types what they were told and it does not exist. Worse: the
# COMMENTS of the generated manifests, which somebody reads months
# later looking for how to redo something.
#
# The answer is not to translate 155 strings: it is to derive them from
# one. $AEGIS_CMD (bash) and cli.cmd() (python) come from argv[0].
#
# The command list is DERIVED from libexec/, it is not written here: the
# day a new command is born, this rule covers it without anybody
# touching it. And the name is required to be USED AS A COMMAND
# (followed by a space, a quote or the end) — `aegis-init.conf` is a
# file, `aegis-ca.pem` is a certificate and `require-aegis-signature` is
# a policy: none of them is a command and none of them must bite.
#
# DECLARED EXCEPTION: `clase-E-ok:` with the reason written out, on the
# same line or on the one above (there are lines that admit no trailing
# comment, such as continuations with \).
# It is used where the name is NOT a command but a datum (the label of
# a log stream, an ntfy topic).
D103=""
mapfile -t CMDS < <(for f in "$LIBEXEC"/aegis-*; do [[ -f "$f" ]] && basename "$f"; done)
PAT="$(printf '%s|' "${CMDS[@]}" | sed 's/|$//')"
HITS="$(grep -rnE "(^|[[:space:]\"'\`(=])(bin/)?($PAT)([[:space:]\"'\`,;:)]|\\\\n|$)" \
        "$AEGIS_ROOT/libexec" "$LIBS" "$AEGIS_ROOT/init" "$AEGIS_ROOT/bin" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -E '(printf|echo |print\(|log_(info|ok|warn|error)|die |die\(|morir\(|say )' \
    | grep -vE 'AEGIS_CMD|cli\.cmd|CMD_[A-Z]|clase-E-ok:' \
    | grep -vE '\$AEGIS_ROOT/libexec/|\$LIBEXEC/|libexec/state/|libexec/dev/' \
    || true)"
# The exception is also valid on the line ABOVE: a continuation with \
# admits no trailing comment, and forcing the code to be rewritten just
# to be able to annotate it would be the check dictating the design.
HITS="$(printf '%s\n' "$HITS" | while IFS= read -r h; do
    [[ -z "$h" ]] && continue
    fname="${h%%:*}"; rest="${h#*:}"; num="${rest%%:*}"
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num > 1 )) \
       && sed -n "$((num-1))p" "$fname" 2>/dev/null | grep -q 'clase-E-ok:'; then
        continue
    fi
    printf '%s\n' "$h"
done)"
N="$(printf '%s' "$HITS" | grep -c . || true)"
if [[ "$N" != 0 ]]; then
    printf '%s\n' "$HITS" | head -12 | sed 's/^/    /'
    D103=" $N messages write a command's name by hand (they must come from \$AEGIS_CMD / cli.cmd());"
fi
printf '    %s commands in the list derived from libexec/\n' "${#CMDS[@]}"
if [[ -n "$D103" ]]; then fail "Class E:$D103"
else pass "no message names a command literally: they all derive from argv[0]"; fi
}
