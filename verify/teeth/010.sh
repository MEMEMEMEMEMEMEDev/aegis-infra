# teeth of check 010 — regenerated on 2026-08-29, when the check stopped
# carrying a written list of names and started deriving them from the
# wizard. Every red below was applied over a copy of the tree.

# the subject disappears: if the check does not notice, it was not
# reading it
red_1() { rm -f "$AEGIS_ROOT/init/aegis-init.conf.example"; }

# THE REGRESSION THAT WAS MEASURED, and the reason the list had to go:
# a variable the wizard writes, missing from the example. With the old
# written list this was green.
red_2() { sed -i '/^AI="no"$/d' "$AEGIS_ROOT/init/aegis-init.conf.example"; }

# the other direction, which rots without anybody looking: the example
# documents something the wizard does not write. A lie in the file
# people copy in order to automate the init.
red_3() { printf '\nOLD_SETTING="value"\n' >> "$AEGIS_ROOT/init/aegis-init.conf.example"; }

# the check's own subject taken away: if config_wizard's write block
# cannot be read, deriving nothing must NOT be reported as "nothing
# missing". This is the shape of the 2026-08-29 bug in check 004.
red_4() { sed -i 's/atomic write of the \.conf/atomic write of the file/' "$AEGIS_ROOT/lib/config.sh"; }

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/aegis-init.conf.example"; }
