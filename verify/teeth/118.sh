# teeth for check 118 (a declared --json is not thrown away)
#
# Every red is the same lie in a different disguise: the command says it
# speaks the contract and does not. None of them fails anywhere else —
# the flag parses, the exit code is right, and the output is the prose
# it always was.

E118="$AEGIS_ROOT/libexec/aegis-edge"
H118="$AEGIS_ROOT/libexec/aegis-host"

# «this variable is unused» — and with it goes the whole flag. This is
# the literal shape aegis-edge carried until 2026-09-11.
red_1() { sed -i 's/^    a = ap\.parse_args()$/    ap.parse_args()/' "$E118"; }

# subtler and more plausible: the namespace is kept, and then nobody
# looks at it. Somebody «simplifies» the two places that read it.
red_2() { python3 - "$E118" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace("steps = outcomes.Steps(json_mode=a.json_mode)", "steps = outcomes.Steps()")
s = s.replace("narrate = not a.json_mode", "narrate = True")
p.write_text(s)
P
}

# the same disease in ANOTHER command, to prove the universe is derived
# and not a list with aegis-edge written in it. host declares --json on
# six subparsers and consults it once per verb, so muting ONE of them
# proves nothing: somebody removing the flag's effect removes all six.
red_3() { sed -i 's/^\([[:space:]]*\)if args\.json:$/\1if False:/' "$H118"; }

# the bash shape of the same lie: aegis-check accepts --json, sets
# JSON_MODE, and then nothing in the file ever asks for it
red_4() { sed -i -E 's/^(if|.*\[\[) -n "\$JSON_MODE" \]\]/\1 -n "$NEVER_SET_118" ]]/' "$AEGIS_ROOT/libexec/aegis-check"; }

# ── controls: real changes that must NOT move the verdict ────────────

# somebody rewrites the explanation
control_1() { python3 - "$E118" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
p.write_text(s.replace("    # ASSIGNED. Until 2026-09-11 this line was a bare",
                       "    # KEPT ON PURPOSE. Until 2026-09-11 this line was a bare"))
P
}

# a new command appears that declares the flag CORRECTLY: it joins the
# universe by itself and stays green, which is the point of deriving it
control_2() { cat > "$AEGIS_ROOT/libexec/aegis-probe118" <<'Q'
#!/usr/bin/env python3
# aegis-summary: a probe that speaks the contract
import argparse
def main():
    ap = argparse.ArgumentParser("probe")
    ap.add_argument("--json", action="store_true", dest="json_mode")
    a = ap.parse_args()
    print("document" if a.json_mode else "prose")
main()
Q
chmod +x "$AEGIS_ROOT/libexec/aegis-probe118"
}

# a command that CONSUMES a --json document without declaring one must
# not be dragged into the universe: aegis-preflight is exactly that,
# and demanding it read a flag it never declared would be a false red.
control_3() { python3 - "$AEGIS_ROOT/libexec/aegis-preflight" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
p.write_text(s.replace("#!/usr/bin/env bash",
                       "#!/usr/bin/env bash\n# consumes `aegis host --json`; declares no flag of its own", 1))
P
}
