# title: the python package does not just parse: it LOADS
# origin: new in v3 — the ES->EN rename of 2026-08-24
check() {
# Check 001 validates SYNTAX with `ast.parse`, and that is exactly what
# is not enough. `from . import rutas` parses perfectly on the day
# `rutas.py` becomes `paths.py`: the file is valid, the reference is
# dead, and nobody finds out until somebody runs the command.
#
# It happened right here on 2026-08-24, during the rename to English:
# the package's three modules were moved, `aegis verify` came out ALL
# PASS with its 113 checks, and `aegis org apply` blew up on the
# import. One hundred and thirteen checks and not one imported the
# package that six commands use.
#
# It is the same family that 001 documents —«a filter that stops biting
# when the file changes shape»— moved up one step: here the instrument
# measured the right shape (the syntax tree) of the wrong question.
# Parsing is not loading.
#
# It is measured in TWO passes because they are two different failures
# and one has to be able to say which:
#   (a) static: every `from aegis import X` / `import aegis.X` in the
#       product names a module that EXISTS in lib/aegis/;
#   (b) real: every module of the package is genuinely imported, which
#       is the only thing that proves its own internal imports resolve.
command -v python3 >/dev/null || { skip "no python3: I cannot load the package"; return; }
[[ -d "$LIBS/aegis" ]] || { skip "$LIBS/aegis does not exist — there is no package to load"; return; }

D108="$(python3 - "$AEGIS_ROOT" <<'PY'
import ast, pathlib, subprocess, sys

root = pathlib.Path(sys.argv[1])
libs, libexec = root / "lib", root / "libexec"
pkg = libs / "aegis"

# The modules the package OFFERS, derived from the directory: a
# hand-written list goes stale the day somebody adds one.
available = {p.stem for p in pkg.glob("*.py") if p.stem != "__init__"}
failures = []

# (a) STATIC — every import of `aegis` names something that exists.
def sources():
    for base in (libs, libexec):
        for p in base.rglob("*"):
            if not p.is_file() or "__pycache__" in p.parts:
                continue
            if p.suffix == ".py":
                yield p
            elif p.suffix == "":
                try:
                    if p.open("rb").read(200).splitlines()[0].find(b"python") >= 0:
                        yield p
                except (OSError, IndexError):
                    pass

n_imports = 0
for p in sources():
    try:
        tree = ast.parse(p.read_text(encoding="utf-8", errors="replace"))
    except SyntaxError:
        continue                      # that belongs to check 001, not this one
    for node in ast.walk(tree):
        requested = []
        if isinstance(node, ast.ImportFrom):
            # `from aegis import a, b` and `from . import a, b` (inside the package)
            if node.module == "aegis" or (node.level and node.module is None
                                          and pkg in p.parents):
                requested = [a.name for a in node.names]
            elif node.module and node.module.startswith("aegis."):
                requested = [node.module.split(".", 1)[1]]
            elif node.level and node.module and pkg in p.parents:
                requested = [node.module]
        elif isinstance(node, ast.Import):
            requested = [a.name.split(".", 1)[1] for a in node.names
                         if a.name.startswith("aegis.")]
        for m in requested:
            n_imports += 1
            if m not in available:
                failures.append(f"{p.relative_to(root)}:{node.lineno} imports "
                                f"'aegis.{m}' and lib/aegis/{m}.py does not exist")

# (b) REAL — every module is genuinely imported, in a clean interpreter.
# A subprocess and not `importlib` here: an import that fails halfway
# leaves rubbish in sys.modules and the next one lies.
for m in sorted(available):
    r = subprocess.run([sys.executable, "-c", f"import aegis.{m}"],
                       cwd=str(root), env={"PATH": "/usr/bin:/bin",
                                           "PYTHONPATH": str(libs),
                                           "AEGIS_ROOT": str(root)},
                       capture_output=True, text=True)
    if r.returncode != 0:
        last = (r.stderr.strip().splitlines() or ["(no stderr)"])[-1]
        failures.append(f"lib/aegis/{m}.py does NOT load: {last}")

print(f"    {len(available)} modules · {n_imports} package imports verified",
      file=sys.stderr)
print("; ".join(failures))
PY
)"
if [[ -n "$D108" ]]; then fail "the python package does not load: $D108"
else pass "every module of lib/aegis/ loads in a clean interpreter and every import in the product names one that exists"; fi
}
