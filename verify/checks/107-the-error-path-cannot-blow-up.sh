# title: the error path cannot blow up
# origin: new in v3 — the defect of 2026-08-24
check() {
# A command that cannot go on has ONE obligation: to say why. If the
# expression that builds that message can raise an exception, the
# operator does not receive the reason: they receive a traceback about
# something else, and the «I could not» disguises itself as a bug.
#
# `Path.relative_to` is this tree's concrete trap because it raises
# ValueError when the path does not hang off the other one — and ever
# since the product stopped being the instance, no path of the instance
# hangs off the product. It went exactly like that: `aegis dev seed
# diff` against an outside instance died with a traceback on the very
# line that was going to explain that the conf was missing.
#
# The rule is narrow on purpose: it does not say «the message has to be
# pretty», it says the construction of the message cannot fail.
CULPRITS="$(python3 - "$AEGIS_ROOT" <<'PY' 2>/dev/null
import ast, pathlib, sys

root = pathlib.Path(sys.argv[1])
ERRORS = {"morir", "die", "Error"}
bad = []

def name_of(f):
    if isinstance(f, ast.Name):
        return f.id
    if isinstance(f, ast.Attribute):
        return f.attr
    return None

for p in sorted(list((root / "libexec").rglob("*")) + list((root / "lib").rglob("*.py"))):
    if not p.is_file():
        continue
    try:
        text = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    if not (p.suffix == ".py" or text.startswith("#!") and "python" in text.split("\n", 1)[0]):
        continue
    try:
        tree = ast.parse(text)
    except SyntaxError:
        continue                      # check 1 takes care of that
    for node in ast.walk(tree):
        args = None
        if isinstance(node, ast.Call) and name_of(node.func) in ERRORS:
            args = node.args + [k.value for k in node.keywords]
        elif isinstance(node, ast.Raise) and node.exc is not None:
            args = [node.exc]
        if not args:
            continue
        for a in args:
            for sub in ast.walk(a):
                if (isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute)
                        and sub.func.attr == "relative_to"):
                    bad.append(f"{p.relative_to(root)}:{node.lineno}")

print(" ".join(sorted(set(bad))))
PY
)"
RC=$?
if [[ $RC -ne 0 ]]; then
    skip "could not read the python tree (python3 missing, or it does not parse)"
elif [[ -n "$CULPRITS" ]]; then
    fail "the error message is built with something that can blow up (relative_to): $CULPRITS"
else
    pass "no error path builds its message with an operation that can raise an exception"
fi
}
