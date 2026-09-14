# teeth for check 203 (the form is filled from what was measured)
#
# Every red puts something in front of somebody that nobody measured.
# None of them fails: the form renders, the contract validates, and the
# wrongness arrives days later in a repository that is not theirs.

C203="$AEGIS_ROOT/lib/aegis/console.py"

# THE ONE, and it is the version I actually wrote first. With no URL to
# hand, the owner is invented — the contract validates, the deploy key
# goes to somebody else's repository, and the first push builds nothing.
red_1() { python3 - "$C203" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            "servicio0.publico": "/", "servicio0.repo": ssh}'
assert s.count(old) == 1, "re-aim this tooth"
new = ('            "servicio0.publico": "/",\n'
       '            "servicio0.repo": ssh or f"git@github.com:owner/{repo}.git"}')
p.write_text(s.replace(old, new, 1))
P
}

# the owner is dropped from a URL that HAD one: same outcome, arrived at
# from the other side
red_2() { python3 - "$C203" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            ssh = f"git@github.com:{tail}.git"'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '            ssh = f"git@github.com:owner/{repo}.git"', 1))
P
}

# a hostname is invented from the repository's name. It validates, the
# CNAME gets created, and nobody later knows why it is there.
red_3() { python3 - "$C203" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    return {"organizacion": base, "dominio": "", "cuota": "",'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(
    old, '    return {"organizacion": base, "dominio": f"{base}.example.com", "cuota": "",', 1))
P
}

# the guess falls the other way: a language nobody has a rule for is
# suggested static, so an http service is declared with nowhere to run
red_4() { python3 - "$C203" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    return SUGGESTS.get((language or "").lower(), "http")'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    return SUGGESTS.get((language or "").lower(), "estatico")', 1))
P
}

# the form stops saying that it guessed. Every other value on that
# screen was measured, and now a person cannot tell which one was not.
red_5() { python3 - "$C203" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "    suggested = bool((filled or {}).get(\"servicio0.repo\")) and not existing"
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, "    suggested = False", 1))
P
}

# a name the validator would refuse is handed over anyway, so the form
# is rejected at the end for a field it filled in itself
red_6() { python3 - "$C203" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    if not _re.match(r"^[a-z][a-z0-9-]{2,29}$", base):\n        base = ""'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    if False:\n        base = ""', 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# one more language gets a rule: growing the table is not changing how a
# language nobody has a rule for falls
control_1() { python3 - "$C203" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    "svelte": "estatico", "vue": "estatico", "mdx": "estatico",'
assert s.count(old) == 1
p.write_text(s.replace(old, old + '\n    "hugo": "estatico",', 1))
P
}

# the words on the form change: they are for a person, and the rule is
# that the guess is LABELLED, not that it is labelled with this sentence
control_2() { sed -i 's/suggested from the language: change it if it is /suggested from what the repository is written in: change it if it is /' "$C203"; }

# a comment recording the URL that was invented once
control_3() { printf '\n# note: the first version of import_fields wrote `owner` into the\n# repository URL because the owner was not to hand. It validated.\n' >> "$C203"; }
