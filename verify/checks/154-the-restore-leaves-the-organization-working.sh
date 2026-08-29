# title: `data restore` leaves the organization working: the role in step, the objects back, no password in argv
# origin: new in v3 — the rehearsal on a foreign instance, 2026-08-27
check() {
# A restore that finishes and reports success is not a restore. The
# rehearsal of 2026-08-27 measured the two ways this one lied:
#
#   1. THE ROLE. The globals dump reinstalls the SCRAM hash from the
#      capture, so on a NEW instance —which generated its own
#      credential— the database ends up expecting one password and the
#      pod presenting another. The restore said VERIFIED and the
#      organization did not come up until somebody typed an ALTER ROLE
#      by hand.
#   2. THE OBJECTS. The bucket half printed «not implemented» and
#      stopped, with the objects INSIDE the bundle. The database came
#      back and the bucket did not: the rows point at objects that are
#      not there, and the application serves 404s over data the operator
#      believes restored.
#
# And the repair of (1) brought its own risk: an ALTER ROLE carries a
# password, and a password in argv is public (`/proc/PID/cmdline`) — the
# same class check 075 watches over curl. So the third property is
# measured here too, at the file level and not at the line level.
#
# It reads the file with `ast` and not with grep, for a reason that
# matters to the teeth: a COMMENT and a DOCSTRING may narrate the hole
# that was closed —that narration is worth more than the code— while a
# printed MESSAGE may not go back to saying «not implemented». grep
# cannot tell those apart; the parser does not even see the comments.
D154=""
ROOT="$AEGIS_ROOT" python3 - <<'PY' || D154=" (the detail is above);"
import ast, os, pathlib, sys

root = pathlib.Path(os.environ["ROOT"])
target = root / "libexec" / "aegis-data"
src = target.read_text(errors="replace")
tree = ast.parse(src)
funcs = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
bad, measured = [], 0


def called_by(name):
    fn = funcs.get(name)
    if fn is None:
        return set()
    return {c.func.id for c in ast.walk(fn)
            if isinstance(c, ast.Call) and isinstance(c.func, ast.Name)}


def code_of(name):
    """The function WITHOUT its docstring: what it does, not what it tells."""
    fn = funcs.get(name)
    if fn is None:
        return ""
    body = fn.body[1:] if ast.get_docstring(fn) else fn.body
    return "\n".join(ast.unparse(x) for x in body)


def want(condition, complaint):
    global measured
    measured += 1
    if not condition:
        bad.append(f"    {complaint}")


# ── 1. the role is realigned, and the realignment is PROVEN ─────────
want("realign_role" in called_by("restore"),
     "restore() does not realign the role: on a new instance the "
     "application stays locked out of its own database")
want("ALTER ROLE" in code_of("realign_role"),
     "realign_role() does not issue an ALTER ROLE")
want("stdin_data" in code_of("realign_role"),
     "realign_role() does not send the statement over stdin")
want("role_can_log_in" in called_by("realign_role"),
     "realign_role() does not verify that the credential opens the "
     "database: that the command did not complain is not proof")

# ── 2. the objects come back, and what came back is measured ────────
want("restore_bucket" in called_by("restore"),
     "restore() does not restore the objects of the bucket")
want('"PUT"' in code_of("restore_bucket") or "'PUT'" in code_of("restore_bucket"),
     "restore_bucket() does not write anything (no PUT to S3)")
want("Content-Length" in code_of("restore_bucket"),
     "restore_bucket() does not verify the SIZE of what it uploaded")
want("bucket_listing" in called_by("restore_bucket"),
     "restore_bucket() does not list the bucket afterwards: without the "
     "listing, an object that never got as far as a PUT leaves no trace")

# A message that gives up. Docstrings are excluded on purpose: they
# narrate the hole, and narrating it is not reopening it.
docstrings = set()
for n in ast.walk(tree):
    if isinstance(n, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        first = n.body[0] if n.body else None
        if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) \
           and isinstance(first.value.value, str):
            docstrings.add(id(first.value))
give_up = [n.value for n in ast.walk(tree)
           if isinstance(n, ast.Constant) and isinstance(n.value, str)
           and id(n) not in docstrings
           and ("not implemented" in n.value.lower()
                or "no implement" in n.value.lower())]
want(not give_up,
     f"a message still says it is not implemented: {give_up[:1]}")

# ── 3. no password travels in argv ──────────────────────────────────
# argv is world-readable in /proc, so the statement that SETS a password
# may only travel as stdin. Two ways of getting it wrong are measured:
# the literal in the command, and the interpolation of the variable that
# holds it.
FORBIDDEN = ("ALTER ROLE", "WITH PASSWORD", "PGPASSWORD=")
CARRIERS = ("pass", "pw", "credential", "credencial")
argv_hits = []
for call in ast.walk(tree):
    if not isinstance(call, ast.Call):
        continue
    name = getattr(call.func, "id", None) or getattr(call.func, "attr", None)
    if name not in ("kubectl", "run") or not call.args:
        continue
    argv = call.args[0]
    if not isinstance(argv, (ast.List, ast.Tuple)):
        continue
    for element in argv.elts:
        literal = " ".join(x.value for x in ast.walk(element)
                           if isinstance(x, ast.Constant) and isinstance(x.value, str))
        for mark in FORBIDDEN:
            if mark in literal:
                argv_hits.append(f"line {element.lineno}: «{mark}» in argv")
        for piece in ast.walk(element):
            if not isinstance(piece, ast.FormattedValue):
                continue
            for ref in ast.walk(piece.value):
                ident = getattr(ref, "id", None) or getattr(ref, "attr", None) or ""
                if any(c in ident.lower() for c in CARRIERS):
                    argv_hits.append(f"line {element.lineno}: argv interpolates «{ident}»")
want(not argv_hits, f"a credential travels in argv: {'; '.join(sorted(set(argv_hits))[:3])}")

print(f"    {measured} properties measured over libexec/{target.name}", file=sys.stderr)
for m in bad:
    print(m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D154" ]]; then fail "the restore does not leave the organization working:$D154"
else pass "restore realigns the role and proves it, puts the objects back and measures them, and no password travels in argv"; fi
}
