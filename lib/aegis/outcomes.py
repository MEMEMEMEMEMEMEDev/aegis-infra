"""The three outcomes, as an exit contract.

House doctrine says a command ends in one of three ways, and that
confusing them is the disease rather than the symptom:

    0  DONE or ALREADY SO    it was measured and it is right
    1  WRONG / MISSING       it was measured and something is off
    2  COULD NOT EVALUATE    the instrument never reached the subject
    3  INVALID USAGE         bad flags or arguments

The 2 is the one almost no tool has, and the one most sorely missed:
without it, "I could not measure" disguises itself as green ("found no
failures") or as red ("it is broken"). Both lies are expensive and the
first is worse, because nobody investigates a green.

And there is a second contract, for when the reader is not a person:
every step emits a line

    aegis: <step>  <done|already|wrong|not-evaluable>  [key=value ...]

and with --json the narration is replaced by a document. Consumers read
THAT. In v2, `aegis-app` decided whether the webhook had been created by
looking for the words "webhook creado" in `aegis-webhook`'s output
(aegis-app:713): a change of wording broke the program. That is A3 in the
register, and it is impossible here because there is no prose to grep.
"""
import json
import sys

DONE = "done"
ALREADY = "already"
WRONG = "wrong"
NOT_EVALUABLE = "not-evaluable"

# One single place where the exit-code table lives: this module reads
# it, python's --help (cli.py) reads it, and bash's (lib/common.sh,
# cli_help) reads it. Written twice, it would be twice to remember.
RC = {DONE: 0, ALREADY: 0, WRONG: 1, NOT_EVALUABLE: 2}
RC_USAGE = 3


def _table():
    """The table lives in share/exit-codes.txt and BOTH languages read
    it: this module and cli_help() in lib/common.sh. Written twice it
    would be twice to remember to change, and the copy nobody changes is
    the one the operator ends up reading."""
    from . import paths
    p = paths.aegis_root() / "share" / "exit-codes.txt"
    if not p.is_file():
        raise RuntimeError(f"missing {p}: the product is incomplete")
    return p.read_text().rstrip("\n")


TABLE = _table()


class Steps:
    """The list of steps in a run, and its overall outcome.

    The overall rc is the WORST of the steps, with one rule that is not
    obvious: "could not evaluate" outweighs "it is wrong". If nine of ten
    things are fine and one could not be measured, the honest outcome is
    not "one is wrong": it is "I do not know". A red gets investigated; an
    "I do not know" dressed as a red wastes the time somewhere else.
    """

    def __init__(self, json_mode=False):
        self.steps = []
        self.json_mode = json_mode

    def step(self, name, state, **data):
        if state not in RC:
            raise ValueError(f"unknown state: {state!r}")
        self.steps.append({"step": name, "state": state, **data})
        if not self.json_mode:
            extra = "".join(f" {k}={v}" for k, v in data.items())
            print(f"aegis: {name}  {state}{extra}")
        return self

    def done(self, name, **d):           return self.step(name, DONE, **d)
    def already(self, name, **d):        return self.step(name, ALREADY, **d)
    def wrong(self, name, **d):          return self.step(name, WRONG, **d)
    def not_evaluable(self, name, **d):  return self.step(name, NOT_EVALUABLE, **d)

    @property
    def rc(self):
        if not self.steps:
            # Zero steps is NOT success. A command that did nothing and
            # exits 0 is silence under another name.
            return RC[NOT_EVALUABLE]
        worst = 0
        for s in self.steps:
            r = RC[s["state"]]
            if r == 2:
                return 2
            worst = max(worst, r)
        return worst

    def finish(self):
        if self.json_mode:
            json.dump({"steps": self.steps, "rc": self.rc}, sys.stdout, ensure_ascii=False)
            print()
        sys.exit(self.rc)
