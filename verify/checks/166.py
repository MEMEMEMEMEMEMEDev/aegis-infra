# scanner of check 166 — a `def` name that collides with a word Groovy
# reserves. Kept beside the check as its own file because the check's
# own prose contains the offending words, and a heredoc inside a
# heredoc is how that prose got misread in the first place.
import os, pathlib, re, sys

reserved = set(os.environ["KEYWORDS"].split())
# A `//` opens a comment at the start of a line or after whitespace,
# so the `//` of a URL survives. The paragraph explaining this very
# bug contains the words that trip it, and the first version of the
# check read its own documentation as the defect — the third time in
# one day, and the same trap corrected in checks 161, 163 and 165.
comment = re.compile(r'(^|\s)//.*$')
decl = re.compile(r'\bdef\s+([A-Za-z_][A-Za-z0-9_]*)')

for f in sorted(pathlib.Path(sys.argv[1]).rglob("Jenkinsfile*")):
    if not f.is_file():
        continue
    for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
        for name in decl.findall(comment.sub(r'\1', line)):
            if name in reserved:
                print(f"{f}: declares «def {name}»")
