"""aegis — the package the python commands share.

It exists for a measured reason: in v2 six commands loaded `aegis-org`
with SourceFileLoader to reuse its validation and its derivations
(docs/cli/inconsistencies.md C1). Loading an EXECUTABLE by path as if it
were a module has three consequences, and all three were paid for:

  · check 4 passed identically with the file ABSENT (A2 in the register):
    the surrounding `except ImportError` treated "it is not there" as
    "this does not apply";
  · a `grep` does not find that dependency — C1/C2 call it "invisible":
    the day the file moves, nothing warns;
  · and the executable, on being loaded, ran its whole preamble.

Now it is a real package: `from aegis import org`. If the package is
missing, the import fails and the check goes red, which is the correct
outcome — absence is not a legitimate case.
"""
