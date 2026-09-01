# scanner of check 169 — the transient-network list has to speak the
# language of every downloader the seed actually uses.
#
# The table is EXTERNAL truth: what each tool prints when the network
# drops mid-transfer. It is written down for the same reason the Groovy
# keyword list of check 166 is — it belongs to those tools, not to this
# artifact, and it does not drift with our code.
import os, pathlib, re, sys

seed = pathlib.Path(sys.argv[1])
sigs = os.environ["SIGS"]

# tool -> (how the seed invokes it, one signature it prints on a
# network fault). One is enough: the list is an alternation, and the
# point is that the tool's language is represented at all.
TOOLS = {
    "pip":     (r'pip\s+install',            ["ReadTimeoutError", "Read timed out", "IncompleteRead"]),
    "npm":     (r'\bnpm\s+(ci|install)\b',   ["ETIMEDOUT", "ECONNRESET", "network timeout"]),
    "apt":     (r'apt-get\s+(install|update)', ["Temporary failure", "temporary failure", "Connection failed"]),
    "apk":     (r'apk\s+add',                ["temporary error", "Permission denied", "network error"]),
    "curl":    (r'\bcurl\s',                 ["Could not resolve", "could not resolve", "connection reset"]),
    "go/git":  (r'\bgo\s+(mod|install)\b|\bgit\s+clone\b', ["dial tcp", "failed to get git"]),
}

HASH = re.compile(r'(^|\s)#.*$')
def code_of(text):
    return "\n".join(HASH.sub(r'\1', l) for l in text.splitlines())

used = set()
for cf in sorted(seed.rglob("Containerfile*")):
    if not cf.is_file():
        continue
    body = code_of(cf.read_text(encoding="utf-8", errors="replace"))
    for tool, (pattern, _) in TOOLS.items():
        if re.search(pattern, body):
            used.add(tool)

for tool in sorted(used):
    _, candidates = TOOLS[tool]
    if not any(c.lower() in sigs.lower() for c in candidates):
        print(f"the seed downloads with {tool} and the transient-network list knows none of "
              f"its words ({', '.join(candidates)}): a timeout there reads as a defect, and the "
              f"build is not retried")
print(f"__USED__ {' '.join(sorted(used)) or 'nothing'}", file=sys.stderr)
