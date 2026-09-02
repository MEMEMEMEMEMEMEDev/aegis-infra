# teeth of check 180 — the README's list of gaps does not deny what the
# artifact already ships.
#
# Each red is one of the four sentences the README actually carried
# until 2026-09-02, put back exactly as it read.

_180_add() { python3 - "$AEGIS_ROOT/README.md" "$1" <<'PYEOF'
import re, sys
p, linea = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
anchor = "- El perfil `cloudflare` no se ha corrido en una máquina ajena.\n"
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, anchor + linea + "\n", 1))
PYEOF
}

# six templates ship; the README said there was one.
red_1() { _180_add "- Una sola plantilla de aplicación (\`base\`)."; }

# restore puts the objects back; the README sent the operator to
# re-upload a catalogue by hand.
red_2() { _180_add "- \`aegis data restore\` restaura la base de datos, no los objetos del bucket."; }

# the command issues the ALTER ROLE; the README asked for it by hand,
# while the operator is already restoring under pressure.
red_3() { _180_add "- Tras \`--force\`, el rol de la base de datos se realinea a mano."; }

# `secret create` derives the copy; the README pointed at the command
# that needs the private age key for work that no longer needs it.
red_4() { _180_add "- \`aegis secret create\` no deriva la copia por namespace de la credencial del registro."; }

# control: a gap that IS real. A check that turned red on any honest
# declaration would push the artifact to stop declaring its gaps, which
# is the opposite of what this section is for.
control_1() { _180_add "- No hay panel web: todo se opera desde la línea de comandos."; }

# control: the word «plantilla» in a sentence that is not the claim.
# Naming a subject is not denying it, and a scan that cannot tell them
# apart would forbid the README from discussing its own templates.
control_2() { _180_add "- Las plantillas no cubren COBOL ni Rust todavía."; }
