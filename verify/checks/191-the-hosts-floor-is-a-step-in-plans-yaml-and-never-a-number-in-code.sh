# title: what aegis leaves the machine is a step in plans.yaml, and no reader keeps its own copy of a threshold
# origin: new in v3 — measured on 2026-09-09, the day one requirement was found written down in three places with two values
check() {
# `plans.yaml` opens with THE NUMBERS LIVE HERE AND NOWHERE ELSE, and
# the reason is arithmetic: the day the hardware changes, this is one
# file and not thirty. The `anfitrion:` section brings the machine
# itself under that rule — how much RAM and VRAM aegis leaves alone,
# what the host's own daemons need, and how much free disk the product
# requires before it will install.
#
# The requirement that section absorbed is the worked example of why
# the rule exists. Free disk on / was demanded in three places with two
# values: `aegis preflight` wanted 25 GiB, the init's own gate wanted
# 20, and both READMEs published 25. One of them was wrong, none of
# them could be checked against the others, and the disagreement had
# been sitting there long enough that no one could say which number was
# the real one.
#
# Four things are measured here:
#
#   1 · the section is COMPLETE — every step declares both halves of a
#     floor, the reservations are there, and so is the disk
#     requirement. A step that says what to leave in RAM and not in
#     VRAM is half a floor, and the missing half derives as nothing.
#   2 · the steps are DERIVED from the file, never listed in code. A
#     hardcoded list of step names is a second place to edit, which is
#     the same defect one level up.
#   3 · no floor number is INLINED in the code that derives it.
#   4 · the two readers of the disk requirement ASK for it rather than
#     keeping a copy, and neither compares against a literal.
PLANS="$P/plans.yaml"
[[ -f "$PLANS" ]] || { fail "plans.yaml is not there: $PLANS"; return; }

OUT="$(python3 - "$PLANS" "$LIBS/aegis/host.py" "$LIBEXEC/aegis-host" \
                "$LIBEXEC/aegis-preflight" "$PHASES/00-preflight.sh" <<'PY'
import re, sys, yaml

plans_path, hostlib, hostcmd, preflight, phase00 = sys.argv[1:6]

try:
    plans = yaml.safe_load(open(plans_path, encoding="utf-8")) or {}
except yaml.YAMLError as e:
    print(f"FAILplans.yaml could not be parsed ({e!r}): with no sections readable "
          "every rule below would look satisfied, and that is a verdict about "
          "the reader")
    raise SystemExit

# ── 1 · the section is complete ──────────────────────────────────────
a = plans.get("anfitrion")
if not a:
    print("FAILplans.yaml carries no `anfitrion:` section: the ceiling over every "
          "other ceiling is missing, and every floor derived from it would have "
          "to be invented")
    raise SystemExit

# WHICH KEYS ARE NOT STEPS is derived from the module that owns the
# section, never listed here. A copy of that list in this file is the
# pair that drifts: the day `anfitrion:` grows another non-step key,
# the check would read it as a step with no floor and go red at the
# artifact for being correct.
src = open(hostlib, encoding="utf-8").read()
m = re.search(r'^NON_STEPS\s*=\s*\(([^)]*)\)', src, re.M)
if not m:
    print("FAILNON_STEPS could not be read from lib/aegis/host.py: without it "
          "this check cannot tell a step from a setting, and every verdict "
          "below would be about the reader")
    raise SystemExit
non_steps = tuple(re.findall(r'"([^"]+)"', m.group(1)))

steps = {k: v for k, v in a.items()
         if k not in non_steps and isinstance(v, dict)}
if not steps:
    print("FAIL`anfitrion:` declares no step: there is nothing to leave the "
          "machine and nothing to derive a reservation from")
for name, body in sorted(steps.items()):
    for key in ("ram", "vram"):
        if key not in (body or {}):
            print("FAILthe anfitrion step %r does not declare `%s`: a step that "
                  "covers one kind of memory and not the other is half a floor, "
                  "and the missing half derives as nothing" % (name, key))

res = a.get("reservas") or {}
for key in ("sistema", "desalojo"):
    if key not in res:
        print("FAIL`anfitrion.reservas` does not declare `%s`: it is added to the "
              "floor to make the node's reservation, and without it the "
              "reservation comes out too small while looking derived" % key)

if not a.get("disco_minimo"):
    print("FAIL`anfitrion.disco_minimo` is not declared: it is the single home of "
          "a requirement that used to live in three places with two values")

# The mapping from what was MEASURED to which step that implies. It
# lives in the file for the same reason the steps do; in code it would
# be the one line that still hardcodes a step name.
por = a.get("por_omision") or {}
if not por:
    print("FAIL`anfitrion.por_omision` is not declared: a fresh install would "
          "have a measurement and no way to turn it into a floor, and the "
          "mapping would have to be guessed in code")
for kind, step in sorted(por.items()):
    if step not in steps:
        print("FAIL`anfitrion.por_omision.%s` names the step %r, which is not "
              "declared: the derivation points at a floor that does not exist"
              % (kind, step))

# ── 2, 3 · the code derives, and holds no numbers ────────────────────
def code(path):
    """The file without comments and without docstrings. Prose that
    EXPLAINS a number must not read as a number — six repetitions of
    that mistake are on this project's record."""
    s = open(path, encoding="utf-8").read()
    s = re.sub(r'"""(?:.|\n)*?"""', "", s)
    return "\n".join(l.split("#", 1)[0] for l in s.splitlines())

lib = code(hostlib)
cmd = code(hostcmd)

if not re.search(r'def steps_of\(', lib):
    print("FAILlib/aegis/host.py does not derive the list of steps: without a walk "
          "over the section, the step names live in code as well and there are "
          "two places to edit")
for f, label in ((lib, "lib/aegis/host.py"), (cmd, "libexec/aegis-host")):
    for m in re.finditer(r'["\']?\b(\d+)(Gi|Mi)\b["\']?', f):
        print("FAIL%s writes the memory quantity %s down in code: the floors are "
              "steps in plans.yaml, and a number here is the copy that drifts"
              % (label, m.group(0)))
    hard = re.findall(r'\b(?:compartido|dedicado|exprimido)\b', f)
    if len(hard) > 1:
        print("FAIL%s names the anfitrion steps %d times in code: they are derived "
              "from plans.yaml, and a list here is a second place to edit"
              % (label, len(hard)))

# ── 4 · the readers of the disk requirement ask for it ───────────────
for path, label in ((preflight, "libexec/aegis-preflight"),
                    (phase00, "init/phases/00-preflight.sh")):
    body = code(path)
    if "requires" not in body or "aegis-host" not in body:
        print("FAIL%s does not ask `aegis host requires` for the free-disk "
              "threshold: a reader with its own copy is how one requirement came "
              "to have two values" % label)
    for m in re.finditer(r'-ge\s+["\']?(\d{2,})\b', body):
        print("FAIL%s compares free disk against the literal %s: the threshold "
              "belongs to plans.yaml, and a number here is the second opinion "
              "this check exists to remove" % (label, m.group(1)))

print("    %d anfitrion step(s) · reservations and disk requirement declared · "
      "2 readers asking rather than copying" % len(steps))
PY
)" || { fail "the reading of plans.yaml and its readers could not be completed"; return; }

printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "the host's floor: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "the floors are steps in plans.yaml, derived and not listed, and no reader keeps its own copy of a threshold"
fi
}
