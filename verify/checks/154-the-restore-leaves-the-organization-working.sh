# title: `data restore` leaves the organization working, and what it weighs can be asked for
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
# And that verification goes over the LOOPBACK, which is the whole
# property. Over the unix socket it would prove nothing: the image's
# pg_hba trusts local connections, so a wrong password gets in all the
# same and the test is green by construction. Dropping `-h 127.0.0.1` is
# the most likely mutation of the real world —somebody simplifying an
# exec— and it empties the property that gives this check its name
# without turning anything red. Measured on 2026-08-29: with the flag
# removed the check went on passing, which is why the line is here.
want("127.0.0.1" in code_of("role_can_log_in"),
     "role_can_log_in() does not open the connection over the loopback: "
     "over the socket the pg_hba of the image trusts the local "
     "connection, a wrong password enters the same, and the proof is "
     "green by construction")

# And it is not repaired in silence. `errors="replace"` turns an invalid
# byte into U+FFFD, the ALTER ROLE installs THAT string, and the proof
# above compares the mutilated password against itself: green, with the
# application —which receives the raw bytes in its environment variable—
# locked out of its own database. That is exactly the failure mode this
# check exists for, reached by another road.
lax = [w for w in ("errors='replace'", 'errors="replace"')
       if w in code_of("realign_role")]
want(not lax,
     "realign_role() decodes the credential with errors=replace: an "
     "invalid byte becomes U+FFFD, the role gets a mutilated password "
     "and the proof compares it against itself")

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

# And the headers that size is read from arrive UNFLATTENED. Header names
# are case-insensitive and Garage —hyper— answers in lowercase, so over a
# plain dict `Content-Length` goes missing from a header that is right
# there: `got` comes out -1 for EVERY object and the restore declares
# itself failed after having uploaded the whole bucket. Measured over the
# raw `content-length: 17`: the message gives 17, dict(message) gives -1.
flat = []
for n in ast.walk(funcs.get("s3") or ast.parse("")):
    if isinstance(n, ast.Return) and isinstance(n.value, ast.Tuple) \
       and len(n.value.elts) == 3:
        h = n.value.elts[2]
        if not (isinstance(h, ast.Attribute) and h.attr == "headers"):
            flat.append(f"line {n.lineno}: returns {ast.unparse(h)}")
want(not flat,
     f"s3() transforms the response's headers instead of returning them "
     f"({'; '.join(flat[:2])}): the lookup stops being case-insensitive, "
     f"and what is read through it is the size of what was just uploaded")

# ── 2b. the ORDER, which is the half that no exit code shows ────────
# Two orders were wrong in the first version of this half and neither of
# them fails loudly: they leave a state that looks finished.
#
# Nothing is written before the WHOLE bundle has been checked against the
# manifest. Hashing inside the write loop means object N's bad sha256
# dies with objects 1..N-1 already in the bucket — half a restore, which
# is the state this command exists to avoid.
mixed = [f"line {l.lineno}" for l in ast.walk(funcs.get("restore_bucket") or ast.parse(""))
         if isinstance(l, ast.For)
         and "sha256" in ast.unparse(l) and "'PUT'" in ast.unparse(l)]
want(not mixed,
     f"restore_bucket() verifies the sha256 in the same loop that writes "
     f"({', '.join(mixed[:2])}): a bundle that does not reproduce itself "
     f"would be uploaded halfway")

# And the objects go back INSIDE the window that keeps the consumers
# down. The manifest carries the databases first, so a loop that walks
# the pieces in order opens the window, closes it, and only then uploads
# the objects: the application is already serving rows that point at
# objects still travelling.
window = ""
for n in ast.walk(funcs.get("restore") or ast.parse("")):
    if isinstance(n, ast.Try) and any("scale_consumers_up" in ast.unparse(x)
                                      for x in n.finalbody):
        window = "\n".join(ast.unparse(x) for x in n.body)
want("restore_bucket" in window,
     "restore() puts the objects back OUTSIDE the window that holds the "
     "consumers down: the application returns over rows that point at "
     "objects that have not arrived, which is a 404 in front of a user")

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

# ── 3b. and nothing else travels raw into the pod's shell ───────────
# What the pod runs is a `sh -c` script. The database name that goes into
# it does NOT come from a contract: it comes from the live server, where
# the tenant —POSTGRES_USER is the superuser of its own instance— can
# CREATE DATABASE with the name it likes, backtick and `$(...)` included.
# `sql_literal` protects the SQL and not the shell, and json.dumps quotes
# with DOUBLE quotes, inside which the shell still expands. So every
# interpolation of a command script has to come out of `shq` (or of
# `sql_identifier`, for a name that is SQL and not an argument).
raw_shell = []
for n in ast.walk(tree):
    if not isinstance(n, ast.JoinedStr):
        continue
    text = ast.unparse(n)
    if "$POSTGRES_USER" not in text and "exec psql" not in text:
        continue
    for piece in n.values:
        if not isinstance(piece, ast.FormattedValue):
            continue
        quoted = isinstance(piece.value, ast.Call) and \
            getattr(piece.value.func, "id", "") in ("shq", "sql_identifier")
        if not quoted:
            raw_shell.append(f"line {piece.lineno}: {ast.unparse(piece.value)}")
want(not raw_shell,
     f"a command script interpolates without quoting for the shell "
     f"({'; '.join(sorted(set(raw_shell))[:3])}): a database name with a "
     f"backtick becomes a command substitution inside the pod")

# ── 4. what an organization weighs can be asked for from outside ────
# The instance's storage class is local-path: it does not measure or
# limit the disk a PVC really uses, so nobody outside the pod could say
# how much an organization weighs. A number that cannot be obtained is a
# number nobody watches, and the first sign of a full disk is postgres
# refusing to write.
want("sizes" in funcs and "metrics" in funcs,
     "there is no function that measures what an organization's data weighs")
want("pg_database_size" in code_of("sizes"),
     "sizes() does not ask postgres for the size of its databases")
want("bucket_listing" in called_by("sizes"),
     "sizes() does not measure the bucket")
want("file=sys.stderr" in code_of("measure"),
     "measure() does not send its prose to stderr: stdout carries the "
     "series and nothing else, so it can be piped where they are collected")

# And what did not answer is NAMED. A database whose size could not be
# read is left out of the total —counting it as zero would make a failed
# measurement look like an empty database— so the total is a floor, and a
# floor that nobody declares is a figure passing for the weight. Each one
# goes out as -1 in its own series; here it is measured that the command
# also says it in words to the person reading.
floor = [n for n in ast.walk(funcs.get("measure") or ast.parse(""))
         if isinstance(n, ast.Compare) and "bytes" in ast.unparse(n)]
want(floor,
     "measure() does not separate the databases that did not answer "
     "their size: they are out of the total, so without naming them the "
     "figure is a floor passing for the weight")

# The names, against the convention the rest of the platform already
# speaks: the `aegis_` prefix, the unit at the end, the identity in
# labels. A series without the prefix is one that nobody's dashboard
# finds.
import re
series = set()
for n in ast.walk(funcs.get("metrics") or ast.parse("")):
    if isinstance(n, ast.Constant) and isinstance(n.value, str):
        series.update(re.findall(r'[A-Za-z_][A-Za-z0-9_]*_(?:bytes|objects|timestamp_seconds)',
                                 n.value))
want(len(series) >= 3, f"metrics() emits {len(series)} series: too few to be the measurement")
stray = sorted(s for s in series if not s.startswith("aegis_"))
want(not stray, f"series outside the convention (they do not start with aegis_): {stray}")

# And every label value is ESCAPED where it is written. `org`, `service`
# and `bucket` are validated by lib/aegis/org.py, `database` is not: it
# comes from the live server, where the tenant is superuser of its own
# instance and names it. A quote there does not spoil one series, it
# makes the LINE malformed — and /api/v1/import/prometheus rejects the
# whole batch, so one organization's database would silence the
# measurement of all of them.
bare = []
for n in ast.walk(funcs.get("metrics") or ast.parse("")):
    if not isinstance(n, ast.JoinedStr):
        continue
    prev = ""
    for piece in n.values:
        if isinstance(piece, ast.Constant):
            prev = piece.value if isinstance(piece.value, str) else ""
        elif isinstance(piece, ast.FormattedValue):
            if prev.endswith('="'):
                escaped = isinstance(piece.value, ast.Call) and \
                    getattr(piece.value.func, "id", "") == "label_value"
                if not escaped:
                    bare.append(f"line {piece.lineno}: {ast.unparse(piece.value)}")
            prev = ""
want(not bare,
     f"metrics() writes a label value without escaping it "
     f"({'; '.join(bare[:2])}): a database name with a quote or a line "
     f"break makes the line malformed and the collector rejects the batch")

m_ = re.search(r'^# aegis-subcommands:[ \t]*(.*)$', src, re.M)
want(m_ is not None and "size" in m_.group(1).split(),
     "the command does not declare the subcommand that measures: the menu "
     "and check 106 read exactly that line")

print(f"    {measured} properties measured over libexec/{target.name}", file=sys.stderr)
for m in bad:
    print(m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D154" ]]; then fail "the restore does not leave the organization working:$D154"
else pass "restore realigns the role and proves it, puts the objects back and measures them, no password travels in argv, and the weight of the data comes out as aegis_ series"; fi
}
