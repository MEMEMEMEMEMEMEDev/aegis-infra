"""Check 120 — no case of the corpus carries a value that identifies
this instance.

Same derivation as check 086: read the live aegis.conf and keep the
values that DIFFER from aegis-init.conf.example — a value equal to the
default identifies nobody. Nothing else is forgiven: see the note in
libexec/aegis-console for the two cleverer rules that were tried and
why blunt won.

Prints one line per problem. The last line always says what the scope
was, so a green can never hide that half of it could not be measured.
"""
import os
import re
import sys

ROOT = sys.argv[1]
CASES = os.path.join(ROOT, "console", "cases")
EXAMPLE = os.path.join(ROOT, "init", "aegis-init.conf.example")
HOME = os.environ.get("AEGIS_HOME") or os.path.join(os.path.expanduser("~"), "aegis")
CONF = os.environ.get("AEGIS_CONF") or os.path.join(HOME, "aegis.conf")


def read(path):
    out = {}
    try:
        for line in open(path, encoding="utf-8"):
            m = re.match(r"^\s*([A-Z_]+)=(.*)$", line)
            if m:
                out[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    except OSError:
        return None
    return out


def _too_short_to_mask(value):
    """A value of three characters or less cannot be scrubbed without
    mangling unrelated text, and cannot identify anybody either."""
    return len(value) < 4


live, example = read(CONF), read(EXAMPLE) or {}
identifying = {}
if live is not None:
    for key, value in live.items():
        if value and value != example.get(key) and not _too_short_to_mask(value):
            identifying[key] = value

# The operator's home is always identifying and never lives in a conf.
home_dir = os.path.expanduser("~")
if home_dir not in ("/", "/root"):
    identifying["$HOME"] = home_dir

files = []
for base, _, names in os.walk(CASES):
    files.extend(os.path.join(base, n) for n in names)

for path in sorted(files):
    try:
        text = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    rel = os.path.relpath(path, ROOT)
    for key, value in identifying.items():
        if value in text:
            print(f"{rel} carries this instance's {key}: the corpus travels to a public "
                  f"repository and that value names its operator")

# ── the second kind of identity ──────────────────────────────────────
# A repository name is in no aegis.conf, so the sweep above cannot see
# it. Found on 2026-09-13: the first capture of `repos list` put
# forty-three of this account's repositories into a case in one go, and
# thirty-two of them were somebody's private work that happens to live
# in the same account — an android app, a game server, an old
# assignment. The corpus is published.
#
# What a contract DECLARES is another matter: those names are part of
# what this platform runs and what its own documents describe. What
# nothing deploys has no business in a case, and the capture replaces it
# by position so the shape survives.
#
# The rule is checkable inside a case, with no network and no account:
# a repository the case itself says nothing serves has to carry a
# generic name.
import json as _json                                    # noqa: E402
import re as _re                                        # noqa: E402

GENERIC = _re.compile(r"^(repo-\d+|__[a-z0-9_]+__)$")
named = 0
for path in sorted(f for f in files if f.endswith(".json")):
    try:
        doc = _json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    for step in (doc or {}).get("steps") or []:
        name = step.get("step", "")
        if not name.startswith("repo:") or step.get("sirve"):
            continue
        repo = name.split(":", 1)[1]
        named += 1
        if not GENERIC.match(repo):
            print(f"{os.path.relpath(path, ROOT)} names the repository {repo!r}, which "
                  f"the case itself says nothing deploys: a repository no contract "
                  f"declares is somebody's private work that happens to live in the same "
                  f"account, and this corpus is published")

if live is None:
    print(f"SCOPE: without {os.path.relpath(CONF, home_dir) if CONF.startswith(home_dir) else CONF} "
          f"only $HOME was contrasted — the values of the conf could not be read")
else:
    print(f"SCOPE: {len(identifying)} identifying value(s), {len(files)} file(s) swept, "
          f"{named} undeployed repository name(s) checked for a generic form")
