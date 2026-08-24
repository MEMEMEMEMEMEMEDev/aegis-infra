# title: no generator stage writes where the artifact has no folder
# origin: new in v3 — reproduced on 2026-08-24 against the bare seed
check() {
# The bug, with a reproduction: a valid contract WITHOUT an `ai:` block
# made `aegis org apply` die with
#
#     FileNotFoundError: .../k8s/base/ai-system/routes.yaml
#
# and not at the start — AFTER writing the organization's six
# manifests. A half-written tree, a traceback, and the blame looking
# like the contract's.
#
# The cause was not the AI: it was that a stage of the generator took
# for granted a directory the artifact may not ship. With the decision
# that the AI subsystem does not travel in the seed, «it is not there»
# stopped being an anomaly and became the normal shape of a
# freshly-cloned tree — and the same hole waits for any subsystem taken
# out later.
#
# That is why the check measures the CLASS and not the case: for each
# `apply_*` stage it resolves which file it writes to, asks whether
# that directory exists in the SEED, and if it does not exist it demands
# one of two things —create it with `os.makedirs`, or ask and exit with
# a reason before writing. What is not accepted is writing blind.
[[ -f "$LIBS/aegis/org.py" ]] || { skip "lib/aegis/org.py does not exist"; return; }
[[ -d "$SEED/platform" ]] || { skip "seed/platform does not exist: no artifact to measure against"; return; }

D109="$(python3 - "$LIBS/aegis/org.py" "$SEED/platform" <<'PY'
import ast, os, sys

source, seed = sys.argv[1], sys.argv[2]
tree = ast.parse(open(source, encoding="utf-8").read())

# The path constants, resolved from their assignment: os.path.join(
# PLATFORM_ROOT, "k8s", …) -> ("k8s", …). PLATFORM_ROOT is the instance,
# so the parts that follow are the relative path inside the tree.
constants = {}
for n in tree.body:
    if not (isinstance(n, ast.Assign) and len(n.targets) == 1
            and isinstance(n.targets[0], ast.Name)):
        continue
    v = n.value
    if not (isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute)
            and v.func.attr == "join"):
        continue
    parts = [a.value for a in v.args[1:] if isinstance(a, ast.Constant)]
    if len(parts) == len(v.args) - 1 and parts:
        constants[n.targets[0].id] = parts

def writes(fn):
    """(node, constant_name) for every open(CONST, 'w') in the function."""
    for n in ast.walk(fn):
        if not (isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                and n.func.id == "open" and len(n.args) >= 2):
            continue
        mode = n.args[1]
        if not (isinstance(mode, ast.Constant) and "w" in str(mode.value)):
            continue
        if isinstance(n.args[0], ast.Name) and n.args[0].id in constants:
            yield n, n.args[0].id

# What counts as ASKING about the directory. This check's first version
# accepted «any early return», and its own tooth reported it: `if old
# == new: return 0` was already in every stage, so the guard seemed to
# exist without existing. A check that settles for the shape instead of
# the meaning protects nothing.
QUESTIONS = {"isdir", "exists", "is_dir", "makedirs"}

def asks_about_the_tree(node):
    """Does this node consult whether something exists on the filesystem?"""
    return any(isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
               and n.func.attr in QUESTIONS for n in ast.walk(node))

# The guards can be one level of indirection away: the stage calls a
# helper and the helper is the one that looks at the disk. They are
# derived from the module, not listed by hand.
helpers = {f.name for f in tree.body
           if isinstance(f, ast.FunctionDef) and asks_about_the_tree(f)}

failures, n_stages, n_guarded = [], 0, 0
for fn in tree.body:
    if not (isinstance(fn, ast.FunctionDef) and fn.name.startswith("apply_")):
        continue
    n_stages += 1
    for node, const in writes(fn):
        rel = os.path.join(*constants[const][:-1]) if len(constants[const]) > 1 else ""
        if not rel or os.path.isdir(os.path.join(seed, rel)):
            continue                       # the artifact DOES ship the folder
        # The stage has to, BEFORE writing: look at the disk itself, or
        # call somebody who looks and be able to turn back that way (a
        # `return` that depends on that call).
        guarded = False
        for n in fn.body:
            if n.lineno >= node.lineno:
                break
            if asks_about_the_tree(n):
                guarded = True
                break
            calls_helper = any(isinstance(c, ast.Call) and isinstance(c.func, ast.Name)
                               and c.func.id in helpers for c in ast.walk(n))
            if calls_helper:
                guarded = True
                break
        if guarded:
            n_guarded += 1
        else:
            failures.append(f"{fn.name}() writes {const} into '{rel}/', which the "
                            f"seed does NOT ship, without creating the directory nor "
                            f"asking first (line {node.lineno})")

print(f"    {n_stages} stages · {n_guarded} writes to an absent subsystem, "
      f"all with a guard or makedirs", file=sys.stderr)
print("; ".join(failures))
PY
)"
if [[ -n "$D109" ]]; then fail "the generator writes blind: $D109"
else pass "every stage that writes into a directory the seed does not ship either creates it or asks and exits with a reason"; fi
}
