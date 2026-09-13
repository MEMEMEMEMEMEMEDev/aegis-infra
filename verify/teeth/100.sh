# teeth for check 100 (the menu and the README say the same thing)
#
# Every red is the state this repository was actually in on 2026-09-12.
# None of them fails: the command works, the menu lists it, every other
# check is green, and the only difference is that a stranger cannot find
# it.

R100="$AEGIS_ROOT/README.md"
L100="$AEGIS_ROOT/libexec"

# THE ONE. A command is written and the README never hears about it.
# This is not hypothetical: it is what five commands did for two days.
red_1() { python3 - "$R100" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert "`aegis console`" in s, "re-aim this tooth"
# out of the group row and out of its own line, the way a command that
# was never documented looks
s = s.replace("`aegis console`, ", "")
s = re.sub(r'^\| `aegis console serve`.*\n', '', s, flags=re.M)
p.write_text(s)
P
}

# it stays in the detail table and falls out of the group row: the
# reader who does not already know the name has no way in
red_2() { sed -i 's/`aegis tenant`, //' "$R100"; }

# the README promises a command nobody can run. The reader types it,
# nothing happens, and concludes they got it wrong.
red_3() { python3 - "$R100" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "| backup | `aegis data`, `aegis state` |"
assert s.count(old) == 1
p.write_text(s.replace(old, "| backup | `aegis data`, `aegis state`, `aegis snapshot` |", 1))
P
}

# a whole group's row disappears: its commands have no place a reader
# would look for them
red_4() { python3 - "$R100" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s2 = re.sub(r'^\| infra \| .*\n', '', s, count=1, flags=re.M)
assert s2 != s, "re-aim this tooth"
p.write_text(s2)
P
}

# a new command appears with its metadata in order —it would show up in
# `aegis --help` tomorrow— and nothing says it exists
red_5() { python3 - "$L100" <<'P'
import sys, pathlib, os, stat
d = pathlib.Path(sys.argv[1]); f = d / "aegis-nuevo"
f.write_text("#!/usr/bin/env bash\n"
             "# aegis-summary: Something somebody added\n"
             "# aegis-group:   operate\n"
             "exit 0\n")
f.chmod(f.stat().st_mode | stat.S_IEXEC)
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the sentence describing a command changes: the rule is about the
# command being NAMED, not about how it is described
control_1() { sed -i 's/La ronda rutinaria\./La ronda de siempre./' "$R100"; }

# a maintainer's tool is added, hidden from the menu the way `aegis dev`
# already is: what is not offered is not something the README owes
control_2() { python3 - "$L100" <<'P'
import sys, pathlib, stat
d = pathlib.Path(sys.argv[1]); f = d / "aegis-interno"
f.write_text("#!/usr/bin/env bash\n"
             "# aegis-summary: A maintainer's tool\n"
             "# aegis-group:   dev\n"
             "# aegis-hidden:  true\n"
             "exit 0\n")
f.chmod(f.stat().st_mode | stat.S_IEXEC)
P
}

# a paragraph is added to the README: growing the document is not
# changing what it publishes
control_3() { printf '\n> Nota: `aegis <cmd> --help` imprime el detalle de cada comando, y\n> `aegis --help` el menú del que sale esta tabla.\n' >> "$R100"; }
