# title: every command cited in the documents exists
# origin: V-106 (03 §8) — new in v3
check() {
# H3 of the register: `organizacion.md:342` documented `aegis org
# rotar`, which does not exist. The operator types it, nothing happens,
# and the natural conclusion is «I got it wrong» — not «the document is
# stale».
#
# The documents the operator EXECUTES are code in another syntax (Class
# G). If they are not verified, they age exactly like code but without
# anything turning red.
#
# SCOPE: only what is between backticks or inside a code block. The
# prose says «aegis takes care of…» and that is not an invocation. And
# docs/cli/ and plan/ are skipped, because they are the RECORD of the
# decision: there the old→new table has to be able to name the old one.
D106=""
ROOT="$AEGIS_ROOT" python3 - <<'PY' || D106=" (see the detail above);"
import os, pathlib, re, sys

root = pathlib.Path(os.environ["ROOT"])
libexec = root / "libexec"
commands = {f.name[len("aegis-"):] for f in libexec.glob("aegis-*") if f.is_file()}
# the subcommands each command declares (the ones that do)
subs = {}
for f in libexec.glob("aegis-*"):
    if not f.is_file():
        continue
    header = "\n".join(f.read_text(errors="replace").split("\n")[:40])
    m = re.search(r'^# aegis-subcommands:[ \t]*(.*)$', header, re.M)
    if m and m.group(1).strip():
        subs[f.name[len("aegis-"):]] = set(m.group(1).split())

# The RECORD documents stay out: plan/ and docs/cli/ carry the old→new
# table (rewriting the old column would destroy it), and ENCARGO.md is
# the mandate — it describes what was ASKED FOR, including what does not
# exist yet (`aegis domain set` is T-04's task). A document that
# declares an intention is not a document you type.
RECORD = ("plan/", "docs/cli/", "ENCARGO.md", "Problema-")
docs = [p for p in root.rglob("*.md")
        if not any(r in str(p.relative_to(root)) for r in RECORD)
        and ".git" not in str(p)]
bad, n = [], 0
for d in docs:
    t = d.read_text(errors="replace")
    # inline (`aegis x y`) and in a block (``` ... ```)
    chunks = re.findall(r'`([^`\n]+)`', t)
    for block in re.findall(r'```[a-z]*\n(.*?)```', t, re.S):
        chunks += block.split("\n")
    for tr in chunks:
        m = re.match(r'^\s*(?:\$\s*)?aegis\s+([a-z][a-z-]*)(?:\s+([a-z][a-z-]*))?', tr)
        if not m:
            continue
        n += 1
        cmd, sub = m.group(1), m.group(2)
        if cmd not in commands:
            bad.append(f"    {d.relative_to(root)}: «aegis {cmd}» does not exist")
        elif sub and cmd in subs and sub not in subs[cmd] and not sub.startswith("-"):
            bad.append(f"    {d.relative_to(root)}: «aegis {cmd} {sub}» — {cmd} does not declare that subcommand")
print(f"    {n} invocations cited in {len(docs)} documents", file=sys.stderr)
for m_ in sorted(set(bad)):
    print(m_, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D106" ]]; then fail "documents citing nonexistent commands:$D106"
else pass "every command cited in the documents exists (prose does not count: only code and backticks)"; fi
}
