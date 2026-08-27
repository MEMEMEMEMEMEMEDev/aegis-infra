# title: every bash command resolves the product the same way and does not invent the instance
# origin: V-102 (02 §1) — new in v3
check() {
# In v2 every command computed its root from its own __file__: six
# copies of the same line (aegis-org:32, aegis-app:96, aegis-edge:45,
# aegis-destroy:26, aegis-backup:21, aegis-restore:15). C1/C2 of the
# register call them «dependencies invisible to a grep»: the day the
# file changes depth, the line still compiles and points somewhere else.
#
# In v3 there is a canonical preamble and a single resolver. Two rules:
#  a) whoever resolves the PRODUCT does it with readlink -f (phase 05
#     installs /usr/local/bin/aegis as a symlink: with a bare dirname,
#     AEGIS_ROOT would be /usr/local);
#  b) nobody decides where the INSTANCE is on their own — that belongs
#     to lib/paths.sh.
#
# SCOPE: the bash commands. The python ones still compute their RAIZ
# from __file__ until lib/aegis/paths.py exists.
# TO VERIFY (2026-08-23, T-02): extend this rule to the python ones.
D102=""
# The SUBCOMMANDS too (libexec/state/*, libexec/dev/*): they are
# complete commands, they can be invoked on their own, and they have
# exactly the same problem with phase 05's symlink. The `aegis-*` glob
# left them out — the tooth discovered it, by taking the readlink out
# of state/backup while the check did not even flinch.
for f in "$LIBEXEC"/aegis-* "$LIBEXEC"/state/* "$LIBEXEC"/dev/*; do
    [[ -f "$f" ]] || continue
    b="${f#"$LIBEXEC/"}"
    head -1 "$f" | grep -q 'bash' || continue     # the python ones, in T-02
    if grep -q 'AEGIS_ROOT' "$f"; then
        grep -q 'readlink -f' "$f" \
            || D102="$D102 $b resolves the product without readlink -f (it breaks with phase 05's symlink);"
    fi
    # the instance is not invented: no hand-written $HOME/aegis, and no
    # platform/ hanging off the product.
    # $HOME/aegis EXACTLY: $HOME/aegis-respaldos is another thing (the
    # backup deliberately goes OUTSIDE the tree) and
    # $HOME/aegis-preflight.sh was, until 2026-08-27, the preflight's
    # copy of itself for a clean VM. A pattern that does not tell them
    # apart bites healthy things, and a check that shouts about healthy
    # things stops being read.
    nc "$f" | grep -qE '\$HOME/aegis($|[/"'"'"'[:space:]])' \
        && D102="$D102 $b decides where the instance is on its own (that belongs to lib/paths.sh);"
    nc "$f" | grep -q '\$AEGIS_ROOT/platform' \
        && D102="$D102 $b hangs platform/ off the PRODUCT (the instance is \$AEGIS_HOME);"
done
# and the resolver has to be one and only one
DEFS="$(grep -rl '^aegis_home()' "$LIBS" "$LIBEXEC" 2>/dev/null | wc -l)"
[[ "$DEFS" == 1 ]] || D102="$D102 there are $DEFS definitions of aegis_home() (there must be exactly one, in lib/paths.sh);"
if [[ -n "$D102" ]]; then fail "path resolution:$D102"
else pass "the bash commands resolve the product with readlink -f and the instance comes from lib/paths.sh"; fi
}
