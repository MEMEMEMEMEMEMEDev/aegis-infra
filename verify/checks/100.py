"""Check 100 — every command the menu offers is in the README, and every one the README names exists.

Measured on 2026-09-12: `aegis traffic`, `aegis capacity`, `aegis
builds`, `aegis tenant` and `aegis console` had been written, tested,
given checks and teeth, and run against a live instance — and they
appeared **nowhere** in either README. Five commands that existed only
in their own docstrings.

That is the quietest way for a product to shrink. Nothing fails: the
command works, `aegis --help` lists it, the checks are green. It simply
is not part of what anybody who did not write it can find. The README is
the only place a stranger looks, and a capability that is not there does
not exist for them.

BOTH DIRECTIONS, which is this repository's idiom for a claim with two
homes:

  · a command the menu offers and the README does not name — written
    and unfindable;
  · a command the README names and the menu does not offer — a promise
    with nothing behind it, which is the worse of the two, because it
    reads as a description of something real.

The menu is not a list kept here: it is derived from the very metadata
`bin/aegis` reads to print it, `aegis-group` and `aegis-hidden`. A
command hidden from the menu is hidden from this check too — the
maintainer's tools are not part of what the product offers.
"""
import os
import re
import sys

ROOT = sys.argv[1]
LIBEXEC = os.path.join(ROOT, "libexec")
README = os.path.join(ROOT, "README.md")

if not os.path.isfile(README):
    print("SCOPE: there is no README.md: this check has no subject")
    sys.exit(0)


def meta(path, key):
    with open(path, encoding="utf-8", errors="replace") as fh:
        head = [next(fh, "") for _ in range(40)]
    for line in head:
        m = re.match(rf"^#\s*{key}:\s*(.*)$", line.strip())
        if m:
            return m.group(1).strip()
    return ""


# What `aegis --help` prints, derived the same way bin/aegis derives it.
offered = set()
for name in sorted(os.listdir(LIBEXEC)):
    path = os.path.join(LIBEXEC, name)
    if not (name.startswith("aegis-") and os.path.isfile(path)):
        continue
    if meta(path, "aegis-hidden") == "true":
        continue
    if not meta(path, "aegis-group"):
        continue
    offered.add(name[len("aegis-"):])

with open(README, encoding="utf-8") as fh:
    readme = fh.read()

# Only what is between backticks counts, the same rule check 106 uses:
# the prose says «aegis takes care of…» and that is not a command.
cited = set()
for chunk in re.findall(r"`([^`\n]+)`", readme):
    m = re.match(r"^\s*(?:\$\s*)?aegis\s+([a-z][a-z-]*)", chunk)
    if m:
        cited.add(m.group(1))

findings = []
if not offered:
    print("no command declares a group: the menu itself is empty")
    print("SCOPE: nothing to compare")
    sys.exit(0)

missing = sorted(offered - cited)
if missing:
    findings.append(
        f"the menu offers {missing} and the README names none of them: written, tested "
        f"and unfindable — the README is the only place a stranger looks, and a "
        f"capability that is not there does not exist for them")

# The README may legitimately name a subcommand of something, an option,
# or a command in a sentence about the past. What it may not do is
# present as available a command nobody can run.
ghosts = sorted(c for c in cited
                if c not in offered
                and os.path.exists(os.path.join(LIBEXEC, f"aegis-{c}")) is False)
if ghosts:
    findings.append(
        f"the README names {ghosts}, which no command provides: the reader types it, "
        f"nothing happens, and the natural conclusion is «I got it wrong» rather than "
        f"«the document is stale»")

# And the menu's own grouping has to reach the reader: the table of
# groups is how somebody finds a command they cannot name yet.
groups = {}
for name in sorted(offered):
    g = meta(os.path.join(LIBEXEC, f"aegis-{name}"), "aegis-group")
    groups.setdefault(g, []).append(name)
for group, names in sorted(groups.items()):
    row = re.search(rf"^\|\s*{re.escape(group)}\s*\|(.+)\|\s*$", readme, re.M)
    if not row:
        findings.append(f"the README's table of groups has no row for `{group}`: its "
                        f"{len(names)} command(s) have no place a reader would look")
        continue
    absent = [n for n in names if f"aegis {n}`" not in row.group(1)]
    if absent:
        findings.append(f"the group `{group}` lists {absent} in the menu and not in the "
                        f"README's row for it")

for f in findings:
    print(f)
print(f"SCOPE: {len(offered)} command(s) offered by the menu, {len(cited)} cited in the "
      f"README, {len(groups)} group(s) compared row by row")
