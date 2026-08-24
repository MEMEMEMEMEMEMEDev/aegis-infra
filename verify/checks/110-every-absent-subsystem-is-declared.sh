# title: every subsystem the seed does NOT ship has its protocol written
# origin: new in v3 — P-03 (2026-08-24): AI travels documented, not wired
check() {
# A subsystem absent BY DECISION and one absent BY OVERSIGHT look
# exactly the same from outside: a folder that is not there. That is the
# canonical shape of the missing line, and it is the only thing that
# makes the decision to ship aegis without AI dangerous.
#
# The rule, then: if the product knows how to write into a directory the
# artifact does not ship, there has to be a document that says how it is
# brought in. Not a loose comment — a protocol, in docs/protocols/, that
# NAMES the path. Whoever takes out the next subsystem pays the same
# toll.
#
# The list of directories is NOT written here: it is DERIVED from the
# generator, which is the one that knows where it writes. A hand-written
# list goes stale the day somebody adds a stage, and it fails on the
# side that does not warn.
[[ -f "$LIBS/aegis/org.py" ]] || { skip "lib/aegis/org.py does not exist: I cannot derive the destinations"; return; }
[[ -d "$SEED/platform" ]] || { skip "seed/platform does not exist"; return; }

D110="$(python3 - "$LIBS/aegis/org.py" "$SEED/platform" <<'PY'
import ast, os, re, sys

source, seed = sys.argv[1], sys.argv[2]
tree = ast.parse(open(source, encoding="utf-8").read())

# The destinations the generator knows about, taken from its constants:
# os.path.join(RAIZ, "k8s", "base", "ai-system", "x.yaml") -> k8s/base/ai-system
destinations = set()
for n in tree.body:
    if not (isinstance(n, ast.Assign) and len(n.targets) == 1
            and isinstance(n.targets[0], ast.Name)):
        continue
    v = n.value
    if not (isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute)
            and v.func.attr == "join"):
        continue
    parts = [a.value for a in v.args[1:] if isinstance(a, ast.Constant)]
    if len(parts) != len(v.args) - 1 or len(parts) < 2:
        continue
    # if the last part looks like a file, the destination is its folder
    rel = os.path.join(*(parts[:-1] if "." in parts[-1] else parts))
    if rel:
        destinations.add(rel)

# The DECLARATIONS of deliberate absence. It is not enough for some
# document to mention the path in passing —this check's first version
# settled for that, and its own tooth reported it: deleting the whole
# protocol left it green because ANOTHER document named the folder in
# passing. An explicit declaration is required:
#
#     <!-- aegis-absent: k8s/base/ai-system -->
#
# and it has to live in the document that explains how it is brought
# back.
protocols = os.path.join(seed, "docs", "protocols")
declared = {}          # path -> file that declares it
if os.path.isdir(protocols):
    for base, _, files in os.walk(protocols):
        for a in sorted(files):
            if not a.endswith(".md"):
                continue
            path = os.path.join(base, a)
            for m in re.finditer(r"aegis-absent:\s*([^\s>]+)",
                                 open(path, encoding="utf-8",
                                      errors="replace").read()):
                declared[m.group(1).rstrip("/")] = os.path.relpath(path, seed)

failures, n_absent = [], 0
for rel in sorted(destinations):
    if os.path.isdir(os.path.join(seed, rel)):
        continue
    n_absent += 1
    if rel not in declared:
        failures.append(f"the seed does not ship '{rel}/' and no document "
                        f"declares it with `aegis-absent: {rel}`: an absent "
                        f"subsystem left undeclared is indistinguishable from an oversight")

# And the other way round, by the same standard as `aegis dev seed`'s
# exclusion policy: a declaration naming something PRESENT is an aged
# lie, and a lie in the place where the truth is looked up is worse than
# having nothing written at all.
for rel, where in sorted(declared.items()):
    if os.path.isdir(os.path.join(seed, rel)):
        failures.append(f"{where} declares '{rel}/' absent and the seed DOES "
                        f"ship it: the declaration aged and now it lies")

print(f"    {len(destinations)} generator destinations · {n_absent} absent · "
      f"{len(declared)} declarations", file=sys.stderr)
print("; ".join(failures))
PY
)"
if [[ -n "$D110" ]]; then fail "absent subsystem left undeclared: $D110"
else pass "every generator destination the seed does not ship has a protocol that names it"; fi
}
