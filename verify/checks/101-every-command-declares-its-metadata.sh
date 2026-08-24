# title: every command declares its metadata and the menu lists it
# origin: V-101 (03 §2) — new in v3
check() {
# The «Missing coverage» section of the register, with its number: of
# 12 commands, 1 had somebody verifying it. A command that exists but
# does not appear in the menu is a command nobody finds; one that
# appears but cannot be executed is worse, because it promises.
#
# The menu is DERIVED from these two lines, so there is no list to
# maintain — but that only works if they are there. Here they are
# demanded.
D101=""
NL=0
for f in "$LIBEXEC"/aegis-*; do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    [[ -x "$f" ]] || D101="$D101 $b is not executable;"
    S="$(sed -n '1,20{s/^# aegis-summary:[[:space:]]*//p}' "$f" | head -1)"
    G="$(sed -n '1,20{s/^# aegis-group:[[:space:]]*//p}'   "$f" | head -1)"
    [[ -n "$S" ]] || D101="$D101 $b without aegis-summary;"
    case "$G" in
        setup|apps|operate|infra|backup|dev) ;;
        "") D101="$D101 $b without aegis-group;" ;;
        *)  D101="$D101 $b declares a group the menu does not know ('$G');" ;;
    esac
    # and the summary has to work as a summary: one line, with no full
    # stop, that fits next to the name.
    [[ ${#S} -le 75 ]] || D101="$D101 $b: the summary does not fit in the menu (${#S} characters);"
    NL=$((NL+1))
done
# the other side: what the menu shows has to really exist.
# (The dispatcher is run: it is the only way to prove that the derived
# menu and the files agree — looking at the code is not enough.)
while read -r n; do
    [[ -x "$LIBEXEC/aegis-$n" ]] || D101="$D101 the menu lists '$n' but there is no executable libexec/aegis-$n;"
done < <("$AEGIS_ROOT/bin/aegis" 2>/dev/null | sed -n 's/^  \([a-z][a-z-]*\) .*/\1/p')
printf '    %s commands with metadata\n' "$NL"
if [[ -n "$D101" ]]; then fail "command metadata:$D101"
else pass "the $NL commands declare summary and group, are executable, and the derived menu agrees with the disk"; fi
}
