# title: YAML parsean (incluye multi-doc)
# origen: verify-static.sh (v2) ══ 2
check() {
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib, subprocess
root = pathlib.Path(sys.argv[1]); bad = 0
cand = [f for f in root.rglob("*.y*ml")
        if not (".tpl" in f.suffixes or f.name.endswith(".tpl"))]
# Corrida en Linux nativo (2026-07-25): acá el repo de EDICIÓN y el de
# CORRIDA son el mismo, así que la fase 20 deja platform/ansible/.venv
# dentro del árbol y este walk se metía a parsear plantillas Jinja de
# colecciones de Ansible → 40+ FAIL de YAML que no son del artefacto.
# Mismo principio que el purgado de __pycache__ de la cabecera: los
# checks son función pura del árbol VERSIONADO. git decide qué es
# generado — no una lista de nombres que envejece.
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
then pass "YAML OK"; else fail "YAML con errores"; fi
}
