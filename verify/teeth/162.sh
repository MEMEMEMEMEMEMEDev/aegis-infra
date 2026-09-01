# teeth of check 162 — a sync gate forgives moving forward and never
# forgives staying behind.

# THE STATE THE ARTIFACT WAS IN until 2026-09-01: the gate compared
# strings. A revision NEWER than the pushed one read exactly like one
# that stayed behind, and phase 80 died at 09:39:01 against a cluster
# that was entirely correct.
red_1() {
    sed -i 's/_rev_is_applied "\$expected" "\$revs" "\$repo"/grep -q "$expected" <<< "$revs"/' \
        "$AEGIS_ROOT/lib/common.sh"
}

# the helper gone altogether: back to the string comparison, by
# another road.
red_2() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("_rev_is_applied", "_rev_equals")
open(p, "w", encoding="utf-8").write(s)
PY
}

# THE DANGEROUS ONE, and the reason the direction is checked and not
# only the presence of a merge-base: with the arguments the other way
# round every gate turns green against a sync that stayed BEHIND —
# the F-B #15 fault this whole gate was built for.
red_3() {
    sed -i 's/merge-base --is-ancestor "\$expected" "\$live"/merge-base --is-ancestor "$live" "$expected"/' \
        "$AEGIS_ROOT/lib/common.sh"
}

# a caller that measures a clone and does not hand it over: ancestry
# has no objects to work with, the gate silently falls back to the
# strict question and the timeout comes back for that phase alone.
red_4() {
    sed -i 's|"$(git -C "$PLATFORM_DIR" rev-parse HEAD)" "$PLATFORM_DIR"|"$(git -C "$PLATFORM_DIR" rev-parse HEAD)"|' \
        "$AEGIS_ROOT/init/phases/80-supply-chain.sh"
}

# the same, on the phase that had it written on one line.
red_5() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('rev-parse HEAD)" \\\n    "$PLATFORM_DIR"', 'rev-parse HEAD)"')
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: the caller that has NO local clone (phase 70 pushes from an
# ephemeral one and reads the sha off the remote) is not a defect. It
# keeps the strict comparison on purpose, and a check that accused it
# would be demanding a clone that does not exist.
control_1() {
    printf '\n# note: no clone here on purpose — the sha comes from ls-remote.\n' \
        >> "$AEGIS_ROOT/init/phases/70-deploy-auto.sh"
}

# control: prose about ancestry, in the phase, changes nothing.
control_2() {
    printf '\n# note: the gate forgives a revision that descends from this one.\n' \
        >> "$AEGIS_ROOT/init/phases/85-observability.sh"
}
