"""What the command line has in common: the parser, and HOW one command
invokes another.

`run()` is doctrine rule 5.1 turned into a function. The bug that
justifies it is dated: `aegis-check:766,785` invoked `aegis-edge` and
`aegis-webhook` by relative path, and its exit `case` had no branch for
127. With the command absent, the round reported "no failures" — the
worst possible outcome: green for not having been able to look.
"""
import os
import shutil
import subprocess

from . import paths
from .outcomes import TABLE


def libexec() -> str:
    return str(paths.aegis_root() / "libexec")


def cmd(sub="") -> str:
    """The name the operator actually invoked the CLI with.

    The word "aegis" is never written literally into a message: it comes
    from here, which reads AEGIS_CMD (exported by bin/aegis from
    argv[0]). This is the class-level answer to the ~155 Class E strings
    — they are not translated one by one, they are derived from one.
    Check V-103 watches it.
    """
    base = os.environ.get("AEGIS_CMD", "aegis")
    return f"{base} {sub}".strip()


def parser(prog, description, protocol=None, **kw):
    """argparse with the house epilogue: the exit-code table (one single
    table, the one in outcomes.py) and where the protocol is written."""
    import argparse
    epi = TABLE
    if protocol:
        epi += f"\n\nthe full protocol: {protocol}"
    return argparse.ArgumentParser(
        prog=cmd(prog), description=description, epilog=epi,
        formatter_class=argparse.RawDescriptionHelpFormatter, **kw)


class CouldNotEvaluate(Exception):
    """The instrument never reached the subject. rc 2, never 0 and never 1."""


def run(command, *args, capture=True, stdin_text=None):
    """Invoke another aegis command and return (rc, stdout, stderr).

    Three states that v2 collapsed into one (rule 5.5):
      · the command DOES NOT EXIST      -> CouldNotEvaluate ("does not exist")
      · it exists and would not run     -> CouldNotEvaluate ("not executable")
      · it exists, ran, and returned rc  -> returned as is
    Neither of the first two may end up as "no failures".
    """
    target = os.path.join(libexec(), f"aegis-{command}")
    if not os.path.exists(target):
        raise CouldNotEvaluate(
            f"the command {cmd(command)} does not exist in {libexec()} "
            f"— this is not 'no failures': it is 'could not look'")
    if not os.access(target, os.X_OK):
        raise CouldNotEvaluate(f"{target} exists but is not executable (chmod +x)")
    r = subprocess.run([target, *args], capture_output=capture, text=True,
                       input=stdin_text)
    # 126/127 straight from exec: the interpreter was missing, or the
    # file was not executable. That is not a verdict from the command.
    if r.returncode in (126, 127):
        raise CouldNotEvaluate(
            f"{cmd(command)} could not be executed (rc {r.returncode}: "
            f"is the shebang's interpreter missing?)")
    return r.returncode, (r.stdout or ""), (r.stderr or "")


def run_json(command, *args):
    """Like run(), but reading the CONTRACT instead of the prose.

    Adds --json and returns the document. This is what replaces
    `"webhook creado" in r.stdout` (A3): the consumer reads states, not
    sentences."""
    import json
    rc, out, err = run(command, *args, "--json")
    try:
        return rc, json.loads(out)
    except (ValueError, json.JSONDecodeError):
        raise CouldNotEvaluate(
            f"{cmd(command)} --json did not return a readable document "
            f"(does it not implement the exit contract yet?)")
