# teeth for check 097 (the form's vocabulary is the validator's)
#
# Every red makes `aegis org schema` describe a contract that is not the
# contract `validate` accepts. None of them fails at the command: the
# document comes out well-formed and the disagreement only surfaces
# later, in front of somebody filling in a form.

C097="$AEGIS_ROOT/lib/aegis/org.py"

# THE ONE. A type the platform cannot deliver on this instance is
# offered anyway. The person picks it, fills everything in, and the
# generator refuses at the end with a recipe they cannot run.
red_1() { python3 - "$C097" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            data["disponible"] = bool(spec.get("digest"))'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '            data["disponible"] = True', 1))
P
}

# the other direction, and the quiet one: everything provided by the
# platform is greyed out. A form that offers no database at all looks
# like a platform with no databases.
red_2() { python3 - "$C097" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            data["disponible"] = bool(spec.get("digest"))'
assert s.count(old) == 1
p.write_text(s.replace(old, '            data["disponible"] = False', 1))
P
}

# a field a type forbids is offered as a field it may declare: the
# person fills in a port on a worker and is told afterwards that a
# worker does not listen
red_3() { python3 - "$C097" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        data["campos"] = sorted({"nombre", "tipo", "repo", "puerto", "publico",
                                 "usa", "tamano"} - set(data["prohibe"]))'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''        data["campos"] = sorted({"nombre", "tipo", "repo", "puerto", "publico",
                                 "usa", "tamano"})''', 1))
P
}

# the quota plans stop coming out of plans.yaml and come out of the
# command: it keeps answering with confidence after the file moves
red_4() { python3 - "$C097" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        quotas = sorted(plans.get("cuota") or {})'
assert s.count(old) == 1
p.write_text(s.replace(old, '        quotas = ["pequena", "enorme"]', 1))
P
}

# a type stops being required to bring its repo. The contract validates
# nowhere and the form never asked for the one thing that makes the
# service buildable.
red_5() { python3 - "$C097" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        if own:
            data["requiere"] = sorted(set(data["requiere"]) | {"repo"})'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''        if False:
            data["requiere"] = sorted(set(data["requiere"]) | {"repo"})''', 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the narration changes: it is for people, and no check reads it
control_1() { sed -i 's/not offerable here yet/not available on this instance yet/' "$C097"; }

# a field is added to the description: saying more about a type is not
# deciding anything different about it
control_2() { python3 - "$C097" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '                "imagen_propia": own, "disponible": True,'
assert s.count(old) == 1
p.write_text(s.replace(old, '                "imagen_propia": own, "disponible": True, "descrito": True,', 1))
P
}

# a comment recording why the list is derived
control_3() { printf '\n# note: every option `schema` offers comes out of the constants\n# validate() checks against. A list written into a form is a list that\n# stops being true the day a type is added.\n' >> "$C097"; }
