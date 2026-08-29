# teeth for check 149 (the service sizes, and the generator that serves them)
#
# The mutations are the three ways this can really break: a step that
# disappears, a step that is half written, and a generator that stops
# saying no. Each was applied over a copy of the tree and the check went
# red; both controls stayed green.
PLANS="seed/platform/plans.yaml"
ORG="lib/aegis/org.py"

# A whole size disappears — a merge, a tidy-up, a rename half done. The
# contracts that ask for it do not live in this repo, so this check is
# the only place it can be noticed.
red_1() {
    python3 - "$AEGIS_ROOT/$PLANS" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
# FROM the `tamano:` section and not from the whole file: `grande` is
# also the name of a QUOTA plan, and the first version of this tooth
# deleted that one instead — the mutation applied, the check stayed
# green, and it looked like the check did not bite.
start = re.search(r"(?m)^tamano:$", t)
assert start, "plans.yaml has no `tamano:` section"
m = re.compile(r"(?m)^  grande:\n(?:^    .*\n)+").search(t, start.end())
assert m, "the `grande` size is not where this tooth expects it"
open(p, "w", encoding="utf-8").write(t[:m.start()] + t[m.end():])
PY
}

# A size that says what it reserves and not what it caps. The
# LimitRange and the admission patch would be rendered with a hole, and
# a container with no ceiling is what the quota exists to prevent.
red_2() {
    python3 - "$AEGIS_ROOT/$PLANS" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "    limits.cpu: \"1\"\n    limits.memory: 1Gi\n"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, "    limits.cpu: \"1\"\n", 1))
PY
}

# The generator goes on rejecting an unknown size, but for another
# reason. A rejection with the wrong words comes out green against a
# check that only asks whether it rejected — the mistake this house has
# already made four times.
red_3() {
    python3 - "$AEGIS_ROOT/$ORG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = 'f"service {n!r}: tamano {label!r} does not exist. There is: "'
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(
    t.replace(old, 'f"service {n!r}: tamano {label!r} is not available. There is: "', 1))
PY
}

# And the generator stops saying no at all: a contract with an invented
# size validates, renders a service with no size, and the failure lands
# on the apiserver hours later naming millicores.
red_4() {
    python3 - "$AEGIS_ROOT/$ORG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "            if label not in sizes:\n"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, "            if False:\n", 1))
PY
}

# control: a comment is not a size
control_1() {
    printf '\n# a legitimate note about how these steps were chosen\n' \
        >> "$AEGIS_ROOT/$PLANS"
}

# control: RE-TUNING a number is precisely what this file exists for.
# The check must not turn a plans.yaml edit into a forbidden act — that
# would invert the whole inversion.
control_2() {
    python3 - "$AEGIS_ROOT/$PLANS" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "    limits.cpu: \"2\"\n    limits.memory: 2Gi\n"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(
    t.replace(old, "    limits.cpu: \"3\"\n    limits.memory: 3Gi\n", 1))
PY
}
