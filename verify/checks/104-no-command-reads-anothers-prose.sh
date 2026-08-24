# title: no command decides by reading another one's PROSE
# origin: V-104 (03 §3) — new in v3
check() {
# A3 of the register, with a line number: aegis-app:713 decided whether
# the webhook had been created by looking for the text «webhook creado»
# in aegis-webhook's output. A change of wording —an accent, a capital,
# a «ya estaba» instead of «creado»— broke the program without touching
# a line of logic, and the symptom appeared in ANOTHER command.
#
# State between commands travels by CONTRACT: `aegis: <step> <state>`
# lines and --json. Prose is for people.
#
# It is measured with the AST and not with grep, on purpose: this
# check's first version used a regular expression and bit its own
# documentation —cli.py's docstring, which QUOTES the bug to explain
# it—. Mention ≠ use: it is the class already paid for in checks 22,
# 25, 66 and 71, and there is no reason to pay it a fifth time.
D104=""
ROOT="$AEGIS_ROOT" LIBEXEC="$LIBEXEC" LIBS="$LIBS" python3 - <<'PY' || D104=" (see the detail above);"
import ast, os, pathlib, sys

# SCOPE: the prose of ANOTHER AEGIS COMMAND. Reading the error text of
# a foreign tool (gh, kubectl) is different: we do not control its
# contract and sometimes there is no other way —aegis-app tells a 404
# from a 409 from GitHub that way, and that stays—. What this rule
# forbids is TWO OF THE HOUSE'S COMMANDS talking to each other through
# prose, because there we do have the alternative and the bug already
# happened.
def aegis_in(node):
    """Does this call execute an aegis command?"""
    for h in ast.walk(node):
        if isinstance(h, ast.Constant) and isinstance(h.value, str) and "aegis-" in h.value:
            return True
        if isinstance(h, ast.Name) and h.id in AEGIS_VARS:
            return True
        if isinstance(h, ast.Attribute) and h.attr in ("run", "run_json") and \
           isinstance(h.value, ast.Name) and h.value.id == "cli":
            return False       # cli.run_json IS the contract, not the prose
    return False

bad = []
files = list(pathlib.Path(os.environ["LIBEXEC"]).glob("aegis-*"))
files += list(pathlib.Path(os.environ["LIBS"]).rglob("*.py"))
for f in files:
    if not f.is_file():
        continue
    txt = f.read_text(errors="replace")
    if "python" not in txt.split("\n")[0] and f.suffix != ".py":
        continue
    try:
        tree = ast.parse(txt)
    except SyntaxError:
        continue
    # variables pointing at an aegis command (WEBHOOK = .../aegis-webhook)
    AEGIS_VARS = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Assign):
            for h in ast.walk(n.value):
                if isinstance(h, ast.Constant) and isinstance(h.value, str) and "aegis-" in h.value:
                    for d in n.targets:
                        # one-letter names are not command constants:
                        # they are throwaway variables
                        # (p = ArgumentParser(prog="aegis-app"))
                        if isinstance(d, ast.Name) and len(d.id) > 2:
                            AEGIS_VARS.add(d.id)
    # PER FUNCTION, not per file: `r` is the most common name in the
    # world for a subprocess result, and mixing everything together the
    # check accused `r = _gh(...)` of being a call to aegis just because
    # ANOTHER function in the same file had `r = subprocess.run([WEBHOOK]`.
    # A check that shouts about healthy things stops being read.
    # ast.walk() over the whole module DESCENDS into the functions,
    # which meant «the module scope» mixed everything again and the fix
    # fixed nothing. The top level is built from its body, without the
    # functions.
    top_level = ast.Module(body=[n for n in tree.body
                                 if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef,
                                                       ast.ClassDef))],
                           type_ignores=[])
    scopes = [n for n in ast.walk(tree)
              if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))] + [top_level]
    for scope in scopes:
        TAINTED = set()
        for n in ast.walk(scope):
            if isinstance(n, ast.Assign) and isinstance(n.value, ast.Call) and aegis_in(n.value):
                for d in n.targets:
                    if isinstance(d, ast.Name):
                        TAINTED.add(d.id)
        if not TAINTED:
            continue
        for n in ast.walk(scope):
            if isinstance(n, ast.Compare) and len(n.ops) == 1 and isinstance(n.ops[0], ast.In):
                left, right = n.left, n.comparators[0]
                if not (isinstance(left, ast.Constant) and isinstance(left.value, str)):
                    continue
                base = None
                if isinstance(right, ast.Attribute) and right.attr in ("stdout", "stderr"):
                    base = right.value.id if isinstance(right.value, ast.Name) else None
                elif isinstance(right, ast.Name) and right.id in ("salida", "out"):
                    base = right.id
                if base and base in TAINTED:
                    bad.append(f"    {f.name}:{n.lineno}: decides with «{left.value}» "
                               f"inside the output of another aegis command")
for m in bad:
    print(m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
# and the bash equivalent: capturing another command and grepping the capture
for f in "$LIBEXEC"/aegis-*; do
    [[ -f "$f" ]] && head -1 "$f" | grep -q bash || continue
    nc "$f" | grep -qE '\$\((aegis_exec|[^)]*libexec/aegis-)[^)]*\)[^|]*\| *grep' \
        && D104="$D104 $(basename "$f") greps another command's output;"
done
if [[ -n "$D104" ]]; then fail "state through prose:$D104"
else pass "no command decides by another's text: state travels by contract (aegis: <step> <state> / --json)"; fi
}
