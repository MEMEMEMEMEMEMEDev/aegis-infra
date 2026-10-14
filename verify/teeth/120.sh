# teeth for check 120 (no case carries the identity of this instance)
#
# Every red is a capture that forgot to scrub one thing. None of them
# breaks a document: the JSON stays valid, the case renders the same,
# and the value sits in a public git history where it cannot be taken
# back.

C120="$AEGIS_ROOT/console/cases"
CONF120="${AEGIS_CONF:-${AEGIS_HOME:-$HOME/aegis}/aegis.conf}"
_val() { grep -E "^\s*$1=" "$CONF120" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"''; }

# WHAT THESE PLANT is a value of THIS instance, and the check measures
# only what this instance has: on a clean clone there is no aegis.conf
# and only $HOME is contrasted (the check says so in its scope). A red
# that plants an empty value mutates a document into itself and was
# reported as DOES NOT BITE on CI and as root (2026-10-14, review of
# 2026-10-13, 4B-2). With no value to plant the red says so with 75;
# the same for a home the sidecar does not measure (`/` and `/root`
# name nobody).
_need120() {   # <KEY> — the conf value on stdout, or 75 with the reason on stdout
    local v; v="$(_val "$1")"
    [[ -n "$v" ]] || { echo "there is no aegis.conf here ($CONF120), so $1 has no value to plant: only \$HOME is measured on this machine"; return 75; }
    printf '%s\n' "$v"
}

# the domain comes back into a document: the one value that names the
# operator in every hostname of every case
red_1() { local v; v="$(_need120 ROOT_DOMAIN)" || { printf '%s\n' "$v"; return 75; }
          sed -i "s/example\.test/$v/" "$C120/round-with-findings/documents/edge.json"; }

# the GitHub owner, in the sentence a case carries about a repo
red_2() { local v; v="$(_need120 GH_OWNER)" || { printf '%s\n' "$v"; return 75; }
          printf '  duenno: %s\n' "$v" >> "$C120/round-with-findings/case.yaml"; }

# the operator's home, inside the REASON a command gave for having no
# document — exactly where the first capture leaked it
red_3() {
    case "$HOME" in /|/root) echo "the home is $HOME, which names nobody and the sidecar does not measure: nothing to plant"; return 75 ;; esac
    sed -i "s|/home/operator|$HOME|" "$C120/console-blind/case.yaml"
}

# a value nobody thought about: the cloudflare account id, pasted into a
# case as a note
red_4() { local v; v="$(_need120 CF_ACCOUNT_ID)" || { printf '%s\n' "$v"; return 75; }
          printf '  nota: cuenta %s\n' "$v" >> "$C120/contract-invalid/case.yaml"; }

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

# ── the third kind: a home by its shape (2026-10-12) ─────────────────
V120="$C120/security-vulns/documents/vulns.json"
_sub120() {   # <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$V120" "$1" "$2" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
P
}

# THE ONE: the synthetic case as it was committed — an agent's scratchpad
# path, which spells a login with dashes, and not this machine's login
red_8() { _sub120 '"/home/operator/aegis/platform"' '"/tmp/claude-1000/-home-someone-Escritorio-workspace/scratchpad/case/platform"'; }

# somebody else's home, spelled with slashes (made on another machine)
red_9() { _sub120 '"/home/operator/aegis/platform"' '"/home/someone/aegis/platform"'; }

# the capture's own spelling of a home stays legal
control_5() { _sub120 '"/home/operator/aegis/platform"' '"/home/operator/aegis/platform/"'; }
