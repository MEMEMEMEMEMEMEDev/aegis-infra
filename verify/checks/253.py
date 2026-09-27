"""Check 253 — under pipefail, nothing pipes a stream into `grep -q`.

MEASURED 2026-09-24 in lab-arch and lab-debian13 (the experimental's
H-05): `jenkins_build_retry` read the console of a failed build as
`jenkins_get …/consoleText | grep -qiE "$AEGIS_NET_SIGS"`. `grep -q`
exits at the first match; if the producer is still writing it dies of
SIGPIPE (141), and `pipefail` turns the match into «no match». Same
console, two passes: rc 141 and rc 0. The retry said «FAILURE with NO
network signature» with `TOOMANYREQUESTS` in the console, and a
transient failure became a red gate — half of the time.

The class is the pipe, not the producer: whether a producer writes once
or in bursts is not something a reader can see in the line, and a
command that writes one line today writes a page tomorrow. Reproduced
on the operator's machine (2026-09-27): a signature followed by 400 KB,
piped into `grep -q` under pipefail, missed 200 times of 200; read
through a process substitution, 0 of 200. So in code that runs under
pipefail the matcher reads `grep -q … < <(producer)`: the producer is
not part of the pipeline, its SIGPIPE is nobody's exit status, and the
input is the same bytes (a herestring would add a newline and turn an
empty output into one empty line — `grep -v` matches that).

`gate_diag` text is eval'd in this shell, but it only speaks: a miss
there is a quieter log line, never a verdict, and it stays out of scope.

What runs under pipefail: every file that sets it, and lib/ (sourced by
them). A command string handed to `bash -c` runs in a fresh shell
WITHOUT pipefail (SHELLOPTS is not exported), so text inside quotes is
not code here; `$( … )` inside double quotes is.
"""
import os
import re
import sys

ROOT = sys.argv[1]


def code_only(src):
    """The file with everything that is not code at THIS shell's level
    blanked: comments, quoted strings (except $(…) inside double
    quotes), heredoc bodies. Newlines are kept, so line numbers hold."""
    out = []
    i, n = 0, len(src)
    stack = ["code"]          # code | dq ; each "code" pushed by $( keeps its paren depth
    depth = [0]
    heredocs = []             # delimiters pending at the end of this line
    at_word = True
    while i < n:
        c = src[i]
        top = stack[-1]
        if c == "\n":
            out.append("\n")
            i += 1
            at_word = True
            if heredocs and top == "code":
                for delim, strip in heredocs:
                    while i < n:
                        j = src.find("\n", i)
                        j = n if j == -1 else j
                        line = src[i:j]
                        out.append("\n" if j < n else "")
                        i = j + 1
                        if (line.lstrip("\t") if strip else line) == delim:
                            break
                heredocs = []
            continue
        if top == "dq":
            if c == "\\":
                if i + 1 < n and src[i + 1] != "\n":
                    out.append("  "); i += 2
                else:
                    out.append(" "); i += 1
                continue
            if c == '"':
                stack.pop(); depth.pop()
                out.append(" "); i += 1; at_word = False
                continue
            if src.startswith("$(", i) and not src.startswith("$((", i):
                stack.append("code"); depth.append(0)
                out.append("$("); i += 2; at_word = True
                continue
            out.append(" "); i += 1
            continue
        # code
        if c == "\\":
            out.append(src[i:i + 2]); i += 2; at_word = False
            continue
        if c == "'":
            j = src.find("'", i + 1)
            j = n - 1 if j == -1 else j
            out.append(re.sub(r"[^\n]", " ", src[i:j + 1])); i = j + 1; at_word = False
            continue
        if src.startswith("$'", i):
            j = i + 2
            while j < n and src[j] != "'":
                j += 2 if src[j] == "\\" else 1
            out.append(re.sub(r"[^\n]", " ", src[i:j + 1])); i = j + 1; at_word = False
            continue
        if c == '"':
            stack.append("dq"); depth.append(0)
            out.append(" "); i += 1
            continue
        if c == "#" and at_word:
            j = src.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i)); i = j
            continue
        m = re.match(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2", src[i:])
        if m and not src.startswith("<<<", i):
            heredocs.append((m.group(3), m.group(1) == "-"))
            out.append(m.group(0)); i += len(m.group(0)); at_word = False
            continue
        if src.startswith("$(", i):
            stack.append("code"); depth.append(0)
            out.append("$("); i += 2; at_word = True
            continue
        if c == "(":
            depth[-1] += 1
        elif c == ")":
            if depth[-1] == 0 and len(stack) > 1:
                stack.pop(); depth.pop()
                out.append(")"); i += 1; at_word = False
                continue
            depth[-1] -= 1
        out.append(c); i += 1
        at_word = c in " \t;&|(){}"
    return "".join(out)


PIPE_Q = re.compile(r"(?<![|])\|&?(?![|])(?:[ \t]|\\\n)*grep(?:[ \t]+-[A-Za-z]*q[A-Za-z]*|[ \t]+--quiet)\b")
PIPEFAIL = re.compile(r"^\s*set\s+-[A-Za-z]*o\s+pipefail|^\s*set\s+-o\s+pipefail|^\s*set\s+-euo\s+pipefail", re.M)


def is_shell(path):
    if path.endswith(".sh"):
        return True
    try:
        with open(path, encoding="utf-8") as f:
            return re.match(r"#!\s*/(usr/)?bin/(env\s+)?(ba)?sh\b", f.readline()) is not None
    except (UnicodeDecodeError, OSError):
        return False


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
    if not (rel.startswith("lib/") or PIPEFAIL.search(code)):
        continue
    scanned += 1
    for m in PIPE_Q.finditer(code):
        line = code.count("\n", 0, m.start()) + 1
        text = src.splitlines()[line - 1].strip()
        print(f"{rel}:{line}: {text[:110]}")
        hits += 1

print(f"SCOPE: {scanned} shell file(s) under pipefail (lib/ and every file that sets it), "
      f"code only — comments, quoted `bash -c` strings and heredocs are not this shell's pipes")
