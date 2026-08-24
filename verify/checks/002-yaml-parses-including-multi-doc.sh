# title: YAML parses (including multi-doc)
# origin: verify-static.sh (v2) ══ 2
check() {
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib, subprocess
root = pathlib.Path(sys.argv[1]); bad = 0
cand = [f for f in root.rglob("*.y*ml")
        if not (".tpl" in f.suffixes or f.name.endswith(".tpl"))]
# Run on native Linux (2026-07-25): here the EDITING repo and the
# RUNNING one are the same, so phase 20 leaves platform/ansible/.venv
# inside the tree and this walk went in to parse Jinja templates of
# Ansible collections → 40+ YAML FAILs that are not the artifact's.
# Same principle as the __pycache__ purge in the header: the checks are
# a pure function of the VERSIONED tree. git decides what is generated
# — not a list of names that ages.
if cand:
    ig = subprocess.run(["git", "-C", str(root), "check-ignore", "--stdin"],
                        input="\n".join(str(f) for f in cand),
                        capture_output=True, text=True)
    ignored = set(ig.stdout.split("\n"))
    cand = [f for f in cand if str(f) not in ignored]
for f in cand:
    try: list(yaml.safe_load_all(f.open()))
    except Exception as e: print(f"FAIL yaml: {f}: {e}"); bad = 1
sys.exit(bad)
EOF
then pass "YAML OK"; else fail "YAML with errors"; fi
}
