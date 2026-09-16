# teeth for check 123 (the console reads documents, never prose)
#
# Each red is the same shortcut that broke `aegis app apply` once: run a
# command, look at what it printed. It works, the first time, on a quiet
# machine — which is precisely why it has to be impossible.

C123="$AEGIS_ROOT/lib/aegis/console.py"
X123="$AEGIS_ROOT/libexec/aegis-console"
V123="$AEGIS_ROOT/lib/aegis/screens.py"

# the door that hands back text instead of a document
red_1() { printf '\n\ndef refresh(cmd):\n    from aegis import cli\n    rc, out, err = cli.run(cmd)\n    return out\n' >> "$C123"; }

# the same, going around cli entirely
red_2() { printf '\n\ndef refresh2(cmd):\n    import subprocess\n    return subprocess.run(["aegis", cmd], capture_output=True).stdout\n' >> "$C123"; }

# and the oldest shape of all: matching the narration's mark to decide
# what happened. This is verbatim the mistake the register filed as A3.
red_3() { printf '\n\ndef looked(line):\n    return "\\u2713" in line\n' >> "$C123"; }

# the same, in the capture tool rather than the renderer: the rule is
# about the console, not about one of its files
red_4() { printf '\n\ndef _evaluated(text):\n    return "COULD NOT EVALUATE" not in text\n' >> "$X123"; }

# ── controls: real changes that must NOT move the verdict ────────────

# the console keeps reaching commands the only way it may
control_1() { printf '\n\ndef refresh_ok(cmd):\n    from aegis import cli\n    rc, doc = cli.run_json(cmd)\n    return doc\n' >> "$C123"; }

# prose that NAMES the forbidden shortcut, next to the code that avoids
# it: the mistake this repo made eight times in one day
control_2() { printf '\n# history: this module used to be tempted to read the narration and\n# look for the tick the round prints. It does not: it reads documents.\n' >> "$C123"; }

# a subprocess that has nothing to do with aegis: git, for the commit
# the capture records. It must not bite.
control_3() { printf '\n\ndef _branch():\n    import subprocess\n    return subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True).stdout\n' >> "$X123"; }

# the screens start reading the narration
red_5() { printf '\n\ndef _looked(line):\n    from . import cli\n    rc, out, err = cli.run(line)\n    return out\n' >> "$V123"; }
# and a comment on the screens is not reading anything
control_4() { printf '\n# note: the screens are pure. They read documents that were handed to them.\n' >> "$V123"; }
