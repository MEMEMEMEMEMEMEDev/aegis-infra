# title: phase 05 puts `aegis` on the PATH that the rest of the product promises
# origin: new in v3 — 2026-08-27, the VPS's first "Resume:" line was followed by `aegis: command not found`
check() {
# Two entry points (libexec/aegis-init, libexec/aegis-destroy) explain
# their readlink -f with "phase 05 installs /usr/local/bin/aegis as a
# symlink", every "Resume:" line prints `aegis init ...`, and the
# protocols say `aegis <command>`. Until 2026-08-27 nothing installed
# it: the comments described a design (03 §7) that had never been
# written, and the first customer to follow a Resume line got
# `command not found`. Mention != use, applied to the product's own
# comments. This check demands the install AND its measurement — a
# symlink written and never gated is the same silence one level down.
D143=""
P05="$(nc "$PHASES/05-host.sh")"
echo "$P05" | grep -qE 'ln -sfn? "\$AEGIS_ROOT/bin/aegis" /usr/local/bin/aegis' \
    || D143="$D143 phase 05 does not symlink \$AEGIS_ROOT/bin/aegis to /usr/local/bin/aegis (the entry points and every Resume line assume it);"
echo "$P05" | grep -q 'gate "aegis-en-path"' \
    || D143="$D143 phase 05 has no aegis-en-path gate (an install nobody measures);"
echo "$P05" | tr '\n' ' ' | grep -q 'gate "aegis-en-path".*command -v aegis' \
    || D143="$D143 the aegis-en-path gate does not resolve \`command -v aegis\` (it has to measure the PATH, not the file);"
# the comments that promise it still name phase 05 (if the install moves, they move)
for f in "$LIBEXEC/aegis-init" "$LIBEXEC/aegis-destroy"; do
    grep -q 'phase 05 installs /usr/local/bin/aegis' "$f" \
        || D143="$D143 $(basename "$f") no longer says which phase installs the symlink (its readlink -f has a reason, and the reason has an owner);"
done
if [[ -n "$D143" ]]; then fail "aegis on the PATH:$D143"
else pass "phase 05 symlinks the product to /usr/local/bin/aegis and gates it through command -v; the entry points name that phase"; fi
}
