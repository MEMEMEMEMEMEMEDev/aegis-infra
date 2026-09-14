# teeth for check 120 (no case carries the identity of this instance)
#
# Every red is a capture that forgot to scrub one thing. None of them
# breaks a document: the JSON stays valid, the case renders the same,
# and the value sits in a public git history where it cannot be taken
# back.

C120="$AEGIS_ROOT/console/cases"
CONF120="${AEGIS_CONF:-${AEGIS_HOME:-$HOME/aegis}/aegis.conf}"
_val() { grep -E "^\s*$1=" "$CONF120" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"''; }

# the domain comes back into a document: the one value that names the
# operator in every hostname of every case
red_1() { sed -i "s/example\.test/$(_val ROOT_DOMAIN)/" \
              "$C120/round-with-findings/documents/edge.json"; }

# the GitHub owner, in the sentence a case carries about a repo
red_2() { printf '  duenno: %s\n' "$(_val GH_OWNER)" >> "$C120/round-with-findings/case.yaml"; }

# the operator's home, inside the REASON a command gave for having no
# document — exactly where the first capture leaked it
red_3() { sed -i "s|/home/operator|$HOME|" "$C120/console-blind/case.yaml"; }

# a value nobody thought about: the cloudflare account id, pasted into a
# case as a note
red_4() { printf '  nota: cuenta %s\n' "$(_val CF_ACCOUNT_ID)" >> "$C120/contract-invalid/case.yaml"; }

# ── controls: real changes that must NOT move the verdict ────────────

# prose about the corpus that names NO value of the conf: the ordinary
# case of somebody annotating a case, and it must not bite
control_1() { printf '  nota: capturado con la instancia en marcha, sin tocar nada\n' >> "$C120/round-with-findings/case.yaml"; }

# an anonymised hostname and a generic owner: what a correct capture
# writes
control_2() { printf '  ejemplo: owner/app en sitio.example.test\n' >> "$C120/contract-invalid/case.yaml"; }

# one more case, captured clean
control_3() { mkdir -p "$C120/probe-120/documents" \
    && printf '{"steps":[{"step":"x","state":"already"}],"rc":0}\n' > "$C120/probe-120/documents/edge.json" \
    && printf 'version: 1\ncaso: probe-120\nque: una captura limpia\nprocedencia: medido\nproducido_por:\n- comando: edge check\n  documento: edge.json\n  rc: 0\nmedido_en: 2026-09-11T00:00:00-03:00\naegis: 5d89b79c5cd2a60e58241d1d24208179f8f5fec3\nforma:\n  edge.json:\n    claves: [rc, steps]\n    estados: [already]\n' > "$C120/probe-120/case.yaml"; }

# ── the second kind of identity (2026-09-13) ─────────────────────────

# THE ONE. The capture stops masking the repositories nobody deploys,
# and the next case carries this account's private work into a public
# repository: an android app, a game server, an old assignment.
red_6() { python3 - "$AEGIS_ROOT/console/cases" <<'P'
import sys, pathlib, json
root = pathlib.Path(sys.argv[1])
for path in sorted(root.rglob("*.json")):
    doc = json.loads(path.read_text())
    hit = False
    for step in doc.get("steps") or []:
        n = step.get("step", "")
        if n.startswith("repo:") and not step.get("sirve") and n.endswith(("-01", "-02")):
            step["step"] = "repo:merpy-android"
            hit = True
    if hit:
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
        break
else:
    raise SystemExit("re-aim this tooth: no case carries an undeployed repository")
P
}

# a name that merely LOOKS generic is not one: the mask has to be the
# capture's, not a word somebody chose
red_7() { python3 - "$AEGIS_ROOT/console/cases" <<'P'
import sys, pathlib, json
root = pathlib.Path(sys.argv[1])
for path in sorted(root.rglob("*.json")):
    doc = json.loads(path.read_text())
    hit = False
    for step in doc.get("steps") or []:
        n = step.get("step", "")
        if n.startswith("repo:") and not step.get("sirve") and n.endswith("-03"):
            step["step"] = "repo:proyecto-viejo"
            hit = True
    if hit:
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
        break
else:
    raise SystemExit("re-aim this tooth")
P
}

# a repository a contract DOES declare keeps its real name, and that is
# correct: it is part of what this platform runs and what its own
# documents already describe
control_4() { python3 - "$AEGIS_ROOT/console/cases" <<'P'
import sys, pathlib, json
root = pathlib.Path(sys.argv[1])
for path in sorted(root.rglob("*.json")):
    doc = json.loads(path.read_text())
    hit = False
    for step in doc.get("steps") or []:
        if step.get("step", "").startswith("repo:") and step.get("sirve"):
            step["lenguaje"] = "Zig"
            hit = True
    if hit:
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
        break
P
}
