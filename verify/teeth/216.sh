# teeth for 216 — each red folds one answer back into another, which is
# exactly how the four-answer version got written in the first place.
U216="$AEGIS_ROOT/lib/aegis/upstream.py"
C216="$AEGIS_ROOT/libexec/aegis-update"
S216="$AEGIS_ROOT/lib/aegis/screens.py"

# an unorderable tag scheme goes back to being «I could not look»:
# permanently rc 2 about a pin that is simply tagged that way
red_1() { python3 - "$U216" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        return Answer(SIN_ORDEN, digest=d,'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '        return Answer(NO_MEDIBLE, digest=d,', 1))
P
}

# «nobody to ask» joins the blind: three images this instance builds
# itself become three things nobody could measure
red_2() { python3 - "$U216" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            return Answer(SIN_ARRIBA,\n                          why="it is built by this instance'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '            return Answer(NO_MEDIBLE,\n                          why="it is built by this instance', 1))
P
}

# the groups stop partitioning: an answer that belongs to none of them
# is one every consumer reads through its default
red_3() { python3 - "$U216" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'MEASURED = (AL_DIA, SIN_ARRIBA, SIN_ORDEN)'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'MEASURED = (AL_DIA, SIN_ARRIBA)', 1))
P
}

# what the instrument failed to measure is reported as a measurement:
# the whole inversion, in one word
red_4() { python3 - "$C216" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            elif a.state == upstream.NO_MEDIBLE:'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            elif a.state == "never-happens":''', 1))
P
}

# the console loses the word for an answer: the machine's own spelling
# reaches the screen
red_5() { python3 - "$S216" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    "sin-orden": "no order to follow",\n'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '', 1))
P
}

# the console's table assigns a state beside each word: the page starts
# inventing states no document carries
red_6() { python3 - "$S216" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    "atrasado": "behind",'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    "atrasado": ("behind", ATTENTION),', 1))
P
}

# the cache stops checking which vocabulary it was written in: a rename
# is read back for six hours meaning what it used to mean
red_7() { python3 - "$U216" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if data.get("vocabulario") != CACHE_VOCABULARY:
        return {}
'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '', 1))
P
}

# ── controls ──
# the sentence that travels with an answer is prose
control_1() { sed -i 's/it is built by this instance: its version is a tag of the /it is this instance that builds it: its version is a tag of the /' "$U216"; }
# a word on the screen reads better; the answers behind it do not move
control_2() { python3 - "$S216" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    "sin-arriba": "built here",'
assert s.count(old) == 1
p.write_text(s.replace(old, '    "sin-arriba": "built by this instance",', 1))
P
}
# one more group derived from the ones that exist adds no answer
control_3() { python3 - "$U216" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'UNACTIONABLE = (SIN_ARRIBA, SIN_ORDEN)'
assert s.count(old) == 1
p.write_text(s.replace(old, 'UNACTIONABLE = (SIN_ARRIBA, SIN_ORDEN)\n#: Everything a window may act on.\nACTIONABLE = (ATRASADO,)', 1))
P
}
