"""Check 256 — an assignment that reads with grep says why when grep finds nothing.

MEASURED 2026-09-28 on a user's instance (their H-05), reproduced in the code
2026-09-30: `aegis image request <img> --allow CVE --until … --reason …`
ended rc 1 with no word, ten times in a row, when the image asked for was
the only one that failed in mirror-images. libexec/aegis-image:856 read
`others="$(grep -vxF "$dst" <<< "$culprits" | tr '\\n' ' ')"`: with no
other culprit grep -v prints nothing and exits 1, pipefail keeps the 1,
and a PLAIN assignment carries its command substitution's status to
`set -e` — which ended the script before the report, the exception and
the retry the command's own --help promises.

The class: under errexit, `NAME="$( … grep … )"` with no way out for
«grep found nothing». No match is often the ordinary answer (no other
culprit, no hash yet, an older file), and the line after the assignment
is usually the code that would have said so — phase 25's
`gate "parse-main-tf"` never ran when main.tf had no tunnel_name. The way
out is explicit: `|| true` inside when empty is an answer the next line
handles, or `|| die "…"` after it when empty means broken. `local x=$(…)`
hides the status and is another matter; it stays out of scope.

What runs under errexit: lib/ (sourced by every script) and every file
that sets -e. Code only (check 253's reader): comments, quoted strings
and heredoc bodies are not this shell's commands; `$( … )` is followed
to its closing parenthesis, across lines.
"""
import importlib.util
import os
import re
import sys

ROOT = sys.argv[1]
spec = importlib.util.spec_from_file_location("c253", os.path.join(ROOT, "verify", "checks", "253.py"))
c253 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c253)
code_only, is_shell = c253.code_only, c253.is_shell

ERREXIT = re.compile(r"^\s*set\s+-[A-Za-z]*e", re.M)
ASSIGN = re.compile(r"(?m)^[ \t]*(?:export[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=[ \t]?\$\(")
GREP = re.compile(r"(?:^|[|;&(`]|\s)grep(?:\s|$)")
WAY_OUT_IN = re.compile(r"\|\|\s*(?:(?:true|echo|printf|return|exit|die)\b|:(?=[\s);]|$))")
WAY_OUT_AFTER = re.compile(r"^[ \t]*\S?[ \t]*(?:\|\||&&|;[ \t]*\|\|)")


def inner_of(code, start):
    """The text of the $( … ) whose `$(` ends at `start`, and where it closes."""
    depth, i = 1, start
    while i < len(code):
        c = code[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return code[start:i], i
        i += 1
    return code[start:], len(code)


files = []
for top in ("lib", "init", "libexec", "bin"):
    for dp, dn, fn in os.walk(os.path.join(ROOT, top)):
        for f in fn:
            p = os.path.join(dp, f)
            if os.path.isfile(p) and is_shell(p):
                files.append(p)

scanned = hits = 0
for p in sorted(files):
    with open(p, encoding="utf-8") as f:
        src = f.read()
    rel = os.path.relpath(p, ROOT)
    code = code_only(src)
    if not (rel.startswith("lib/") or ERREXIT.search(code)):
        continue
    scanned += 1
    for m in ASSIGN.finditer(code):
        inner, close = inner_of(code, m.end())
        # only the outermost level decides; an inner $( ) of its own is its business
        if not GREP.search(inner) or WAY_OUT_IN.search(inner):
            continue
        rest = code[close + 1:code.find("\n", close) if code.find("\n", close) != -1 else len(code)]
        if WAY_OUT_AFTER.search(rest):
            continue
        line = code.count("\n", 0, m.start()) + 1
        print(f"{rel}:{line}: {src.splitlines()[line - 1].strip()[:110]}")
        hits += 1

print(f"SCOPE: {scanned} shell file(s) under errexit (lib/ and every file that sets -e), code only")
