"""Check 274 — no variable of a platform pipeline is declared twice in one scope chain.

MEASURED 2026-10-02 on alpha-arch: image-watch #3 died before running a
step — «WorkflowScript: 740: The current scope already contains a variable
of the name mrc». The fix of 9468a84 declared `def mrc` inside the serving
loop, where an enclosing block already had one. Groovy refuses a name an
enclosing scope already holds (it does not shadow), and it says so only
when Jenkins compiles the script, at the start of a run: the declarative
linter of the home Jenkins had validated the file, because it checks the
pipeline's structure and not the script inside `script {}`.

This check does what that compile does for this one rule, on every
Jenkinsfile the seed ships: strings and the shell blocks inside them are
blanked first (their braces are not Groovy's), the braces give the scope
tree, and a `def NAME` (or a `for (NAME in …)`) whose NAME is already
declared in an ENCLOSING scope is reported with both lines. Siblings are
fine: two blocks side by side may each declare their own `n`.
"""
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1])
SEED = os.path.join(ROOT, "seed")
findings = []


def blank_strings(src):
    """Every string literal and comment replaced by spaces, newlines kept,
    so line numbers and braces outside strings survive."""
    out, i, n = [], 0, len(src)
    while i < n:
        for q in ("'''", '"""'):
            if src.startswith(q, i):
                j = src.find(q, i + 3)
                j = n if j < 0 else j + 3
                out.append(re.sub(r"[^\n]", " ", src[i:j]))
                i = j
                break
        else:
            c = src[i]
            if src.startswith("//", i):
                j = src.find("\n", i)
                j = n if j < 0 else j
                out.append(" " * (j - i))
                i = j
            elif src.startswith("/*", i):
                j = src.find("*/", i + 2)
                j = n if j < 0 else j + 2
                out.append(re.sub(r"[^\n]", " ", src[i:j]))
                i = j
            elif c in "'\"":
                j = i + 1
                while j < n and src[j] != c and src[j] != "\n":
                    j += 2 if src[j] == "\\" else 1
                out.append(" " * (min(j, n - 1) + 1 - i))
                i = j + 1
            elif c == "/" and re.match(r"/[^/*\s][^/\n]*/", src[i:]) and re.search(r"[=(~,!]\s*$|==~\s*$|split\($", "".join(out)[-12:]):
                m = re.match(r"/(?:\\.|[^/\\\n])*/", src[i:])
                k = len(m.group(0)) if m else 1
                out.append(" " * k)
                i += k
            else:
                out.append(c)
                i += 1
    return "".join(out)


DECL = re.compile(r"\bdef\s+([A-Za-z_]\w*)\s*[=;\n]|\bfor\s*\(\s*(?:def\s+|int\s+|String\s+)?([A-Za-z_]\w*)\s+in\b|\b(?:int|String|boolean|long)\s+([A-Za-z_]\w*)\s*=")
checked = 0
for dirpath, _dirs, files in os.walk(SEED):
    for fn in files:
        if not fn.startswith("Jenkinsfile"):
            continue
        path = os.path.join(dirpath, fn)
        src = open(path, encoding="utf-8").read()
        code = blank_strings(src)
        checked += 1
        # scope tree: a stack of dicts name -> line
        stack = [{}]
        line = 1
        i = 0
        # a `for (x in …) {` declares x in the block it opens
        pending = []
        for m in re.finditer(r"[{}\n]|" + DECL.pattern, code):
            tok = m.group(0)
            if tok == "\n":
                line += 1
                continue
            if tok == "{":
                scope = {}
                for name, ln in pending:
                    scope[name] = ln
                pending = []
                stack.append(scope)
                continue
            if tok == "}":
                if len(stack) > 1:
                    stack.pop()
                continue
            name = m.group(1) or m.group(2) or m.group(3)
            if not name:
                continue
            ln = line + tok.count("\n") * 0
            outer = None
            for sc in stack:
                if name in sc:
                    outer = sc[name]
            if outer is not None:
                findings.append(f"{os.path.relpath(path, ROOT)}:{ln}: `{name}` is declared again; an enclosing scope declares it at line {outer} — Groovy refuses it when Jenkins compiles the run")
            if m.group(2):
                pending.append((name, ln))      # belongs to the block the for opens
            else:
                stack[-1][name] = ln
            line += tok.count("\n")

for x in findings:
    print(x)
print(f"SCOPE: {checked} Jenkinsfile(s) of the seed, strings and shell blocks blanked, scopes read from the braces")
