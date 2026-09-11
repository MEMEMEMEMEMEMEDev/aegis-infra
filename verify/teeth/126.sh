# teeth for check 126 (every typeface is the one that was pinned)
#
# Every red is a font arriving without anybody having looked at it, and
# none of them breaks a page: the console renders, the letters are
# letters, and the bytes shipping to everybody who installs aegis are
# not the bytes that were reviewed.

F126="$AEGIS_ROOT/share/console/fonts"

# THE SWAP. The file is replaced and the manifest is not: what ships is
# no longer what was read.
red_1() { printf 'wOF2 not the font that was reviewed' > "$F126/jetbrains-mono-latin.woff2"; }

# the other direction: somebody edits the pin to match whatever is on
# disk, which is how a digest stops being a measurement and becomes a
# comment
red_2() { sed -i 's/^plus-jakarta-sans-latin.woff2\t[0-9a-f]*/plus-jakarta-sans-latin.woff2\t0000000000000000000000000000000000000000000000000000000000000000/' "$F126/fonts.txt"; }

# a face appears in the tree that nothing declares: nobody measured it
# and it ships all the same
red_3() { cp "$F126/jetbrains-mono-latin.woff2" "$F126/extra-latin.woff2"; }

# the licence goes away. The repository is public and redistributes
# these bytes: OFL is not a formality here, it is the permission.
red_4() { rm -f "$F126/OFL-jetbrains-mono.txt"; }

# the manifest declares a face that is not there: the page falls back to
# the system stack and nothing says so
red_5() { rm -f "$F126/plus-jakarta-sans-latin.woff2"; }

# ── controls: real changes that must NOT move the verdict ────────────

# the manifest gains prose explaining itself
control_1() { printf '\n# note: only the latin subset travels; the console draws hostnames and\n# numbers, and cyrillic would triple the weight for glyphs never drawn.\n' >> "$F126/fonts.txt"; }

# the skin is repainted and the type stack reordered: taste moves, the
# pins do not
control_2() { sed -i 's/--ui:"Plus Jakarta Sans", ui-sans-serif/--ui:"Plus Jakarta Sans", "Segoe UI", ui-sans-serif/' \
                  "$AEGIS_ROOT/share/console/sereno.css"; }

# a THIRD face is vendored properly: declared, pinned to its real
# digest, and with a licence beside it. Growing the catalogue the right
# way must stay green.
control_3() { cp "$F126/jetbrains-mono-latin.woff2" "$F126/probe-126-latin.woff2" \
    && printf 'probe-126-latin.woff2\t%s\thttps://example.test/probe.woff2\n' \
       "$(sha256sum "$F126/probe-126-latin.woff2" | cut -d' ' -f1)" >> "$F126/fonts.txt" \
    && cp "$F126/OFL-jetbrains-mono.txt" "$F126/OFL-probe-126.txt"; }
