"""Check 217 — a `%` in a unit file belongs to systemd, not to the shell.

WITH A DATE ON IT: 2026-09-20. `aegis-update-notice.service` piped the
measurement into curl with `printf "%s" "$m"`. In a unit file `%` opens
a SPECIFIER, and `%s` is the user's login shell, so what reached /bin/sh
was:

    printf "/bin/bash" "$m"

which prints nine characters and drops the measurement. curl posted
them, VictoriaMetrics answered 204, and the unit finished 0/SUCCESS. The
timer said «26 series: 33 behind», the panel stayed empty, and nothing
anywhere went red. That is the exact shape this product exists to
prevent, in the timer of the command that measures it.

THE RULE. Every `%` inside a directive of a shipped unit is either
escaped (`%%`) or one of the specifiers this artifact uses ON PURPOSE.
Anything else is a silent rewrite of somebody's command line.

The allowed list lives here rather than in the units, because it is a
POLICY and not a fact about them: `%h` is the operator's home, which
three units legitimately need for `ConditionPathExists`. A specifier
that earns its place later is added here, deliberately, by whoever adds
it.

Comments are stripped first. The unit that caused this now explains the
trap in its own comment, `%s` and all, and a check that read prose as
code would go red on the explanation — that mistake is filed six times
in this repo already.
"""
import os
import pathlib
import re
import sys

ROOT = sys.argv[1]
UNITS = pathlib.Path(ROOT) / "share" / "systemd"
findings = []

if not UNITS.is_dir():
    print("SCOPE: this artifact ships no systemd units")
    sys.exit(0)

#: Specifiers this artifact uses deliberately. Nothing else may appear
#: unescaped.
ALLOWED = {"h"}
#: What systemd would swallow. From systemd.unit(5); it is written out
#: so the message can say WHAT the `%` would have become.
MEANS = {
    "a": "the architecture", "b": "the boot id", "B": "the OS build id",
    "C": "the cache directory", "d": "the credentials directory",
    "e": "the escaped instance", "E": "the configuration directory",
    "f": "the unescaped filename", "g": "the group name", "G": "the group id",
    "h": "the home directory", "H": "the hostname", "i": "the instance",
    "I": "the unescaped instance", "j": "the final component of the name",
    "J": "its unescaped form", "l": "the short hostname", "L": "the log directory",
    "m": "the machine id", "M": "the os image id", "n": "the full unit name",
    "N": "the unit name without its suffix", "o": "the OS id",
    "p": "the prefix name", "P": "its unescaped form", "q": "the pretty hostname",
    "s": "THE USER'S LOGIN SHELL", "S": "the state directory",
    "t": "the runtime directory", "T": "the temporary directory",
    "u": "the user name", "U": "the user id", "v": "the kernel release",
    "V": "the larger temporary directory", "w": "the OS version id",
    "W": "the OS variant id", "y": "the unit file path",
    "Y": "its directory", "%": "an escaped per cent",
}

units = sorted(p for p in UNITS.iterdir()
               if p.suffix in (".service", ".timer", ".socket", ".mount", ".path"))
if not units:
    findings.append("share/systemd/ holds no unit: either they moved or this check has "
                    "no subject, and it should not be quietly green about either")

scanned = 0
for unit in units:
    for n, raw in enumerate(unit.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        # Prose is not code. The unit that caused this spells the trap
        # out in its own comment.
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        scanned += 1
        i = 0
        while i < len(value):
            if value[i] != "%":
                i += 1
                continue
            nxt = value[i + 1] if i + 1 < len(value) else ""
            if nxt == "%":
                i += 2            # escaped on purpose
                continue
            if nxt in ALLOWED:
                i += 2
                continue
            if nxt in MEANS:
                findings.append(
                    f"{unit.name}:{n} {key}= carries «%{nxt}», which systemd replaces "
                    f"with {MEANS[nxt]} before anything runs. If the per cent was meant "
                    f"for the shell, write «%%{nxt}»; if the specifier was meant, add "
                    f"{nxt!r} to this check's allowed list on purpose")
            else:
                findings.append(
                    f"{unit.name}:{n} {key}= carries a bare «%» followed by {nxt!r}. "
                    f"systemd refuses to start a unit with an unknown specifier, so this "
                    f"one would not run at all")
            i += 2

for f in findings:
    print(f)
print(f"SCOPE: {len(units)} unit(s), {scanned} directive(s), "
      f"{len(ALLOWED)} specifier(s) allowed on purpose")
