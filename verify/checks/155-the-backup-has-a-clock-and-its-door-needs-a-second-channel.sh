# title: the backup has a clock, and the door under an hour needs a channel this machine does not hold
# origin: new in v3 — the off-site destination, 2026-08-29
check() {
# A backup nobody schedules is a backup somebody remembers. Measured on
# 2026-08-29 on the live instance: the newest bundle was three days old
# and had been made by hand. The clock closes that.
#
# And a clock that can be wound arbitrarily fast opens something else.
# Every run opens a port-forward per bucket, runs a pg_dumpall and a
# pg_dump per database AGAINST THE LIVE SERVER of every tenant,
# downloads every object and pushes the whole bundle to a third party.
# Under an hour that stops being a backup and becomes a load — on the
# tenants' postgres, on a household uplink, and on a free tier counted
# in operations as well as in bytes.
#
# So under an hour the command asks for a code that arrives on the
# operator's PHONE. The property is not «it asks for a confirmation»:
# it is that the confirmation CANNOT BE PRODUCED BY WHOEVER HOLDS THE
# TERMINAL. That is a thing made of four pieces, and removing any one
# of them leaves something that still looks like a door:
#
#   · the gate runs BEFORE the drop-in is written, not after;
#   · with no operator (non-interactive) it REFUSES — «assume yes» here
#     would make the whole door a comment;
#   · with no second channel it REFUSES — it does not fall back to a
#     confirmation typed at the same keyboard, which would be theatre;
#   · the code is never printed, never recorded and never written to a
#     file on this machine. A code the terminal can read is a code the
#     terminal can answer.
#
# The last one is why this check reads the python with `ast`: the code
# has to be traced through every call it reaches, and grep cannot tell
# `ntfy_publish(f"…{code}")` from `print(f"…{code}")`.
#
# It also measures the unit itself, and one systemd detail that is
# exactly the kind that passes review: a drop-in ADDS to a list-valued
# setting, so `OnUnitActiveSec=6h` on its own leaves the shipped 24h in
# place and the timer fires on BOTH. Resetting the list first is the
# only way to replace it, and forgetting it produces a timer that looks
# configured and runs twice.
D155=""
ROOT="$AEGIS_ROOT" python3 - <<'PY' || D155=" (the detail is above);"
import ast, os, pathlib, re, sys

root = pathlib.Path(os.environ["ROOT"])
bad, measured = [], 0


def want(condition, complaint):
    global measured
    measured += 1
    if not condition:
        bad.append(f"    {complaint}")


# ── 1. the unit and its clock ───────────────────────────────────────
SYSD = root / "share" / "systemd"
timer = SYSD / "aegis-backup.timer"
service = SYSD / "aegis-backup.service"
want(timer.is_file(), "share/systemd/aegis-backup.timer does not exist: the "
                      "backup has no clock, and one that is remembered is "
                      "one that stops the week the operator is busy")
want(service.is_file(), "share/systemd/aegis-backup.service does not exist: "
                        "the timer has nothing to trigger")
tt = timer.read_text(errors="replace") if timer.is_file() else ""
st = service.read_text(errors="replace") if service.is_file() else ""
tlines = [l.strip() for l in tt.splitlines() if not l.lstrip().startswith("#")]
slines = [l.strip() for l in st.splitlines() if not l.lstrip().startswith("#")]

cad = [l.split("=", 1)[1].strip() for l in tlines if l.startswith("OnUnitActiveSec=")]
want([c for c in cad if c],
     "the timer declares no OnUnitActiveSec: it has no cadence, so nothing "
     "fires and nothing says so")
want(cad and cad[0] == "24h",
     f"the shipped cadence is {cad[0] if cad else 'nothing'} and not 24h: the "
     f"default is the one every instance gets, and it is the number the "
     f"protocol and the command's floor and ceiling are written around")
want(any(l.startswith("Persistent=true") for l in tlines),
     "the timer is not Persistent: on a desktop that sleeps at night the "
     "missed run is never caught up, and a machine can go days without a "
     "backup with the timer looking healthy the whole time")
want(any(l.startswith("OnBootSec=") for l in tlines),
     "the timer has no OnBootSec: at minute zero the cluster is still "
     "coming up and the capture aborts saying the contracts and the "
     "cluster disagree — a red that means «too early», which is the worst "
     "kind")
# The capture is the operator's, not root's: it needs the age key that
# opens every bundle this platform ever wrote. A unit that names a User
# or that stops reading %h is one that has stopped being theirs.
want(not any(l.startswith("User=") for l in slines),
     "the service declares a User: this is a USER unit, and running the "
     "capture as anybody else means handing them the age key — the one "
     "irreducible — to save writing --user")
want("%h" in st,
     "the service does not read anything out of %h: it has stopped being "
     "the operator's own unit, and with it the reason it may hold the age key")
exe = [l.split("=", 1)[1].strip() for l in slines if l.startswith("ExecStart=")]
want(exe, "the service has no ExecStart")
want(exe and exe[0].startswith("/") and " data backup" in exe[0],
     f"ExecStart does not run the capture through an absolute path "
     f"({exe[0] if exe else 'nothing'}): systemd does not read the session's "
     f"PATH, so a bare name is a unit that never starts")

# ── 2. the floor, the ceiling, and the order ────────────────────────
target = root / "libexec" / "aegis-data"
src = target.read_text(errors="replace")
tree = ast.parse(src)
funcs = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}


def code_of(name):
    fn = funcs.get(name)
    if fn is None:
        return ""
    body = fn.body[1:] if ast.get_docstring(fn) else fn.body
    return "\n".join(ast.unparse(x) for x in body)


want(re.search(r"^CADENCE_FLOOR_S\s*=\s*3600\s*$", src, re.M),
     "the floor is not one hour: under that a capture stops being a backup "
     "and becomes a load on every tenant's live postgres")
want(re.search(r"^CADENCE_CEILING_S\s*=\s*24\s*\*\s*3600\s*$", src, re.M),
     "the ceiling is not a day: a cadence that does not fit in a day is a "
     "backup you find out about later than the disaster")

setter = funcs.get("remote_cadence")
want(setter is not None, "no command changes the cadence")
if setter is not None:
    body = code_of("remote_cadence")
    want("cadence_gate" in body,
         "remote_cadence() never calls the gate: the door under an hour "
         "does not exist, whatever the comments say")
    # THE ORDER. A gate that runs after the drop-in is written has already
    # let the change through.
    gate_at, write_at = body.find("cadence_gate"), body.find("cadence_dropin(")
    want(gate_at != -1 and (write_at == -1 or gate_at < write_at),
         "remote_cadence() writes the drop-in BEFORE asking the gate: by "
         "the time the code is requested the cadence has already changed")
    # And the gate is REACHED by the comparison against the floor, not by
    # some other branch. A guard that compares against nothing is a guard.
    guarded = False
    for n in ast.walk(setter):
        if isinstance(n, ast.If) and "CADENCE_FLOOR_S" in ast.unparse(n.test) \
           and "cadence_gate" in ast.unparse(n.body):
            guarded = True
    want(guarded,
         "the gate is not hung off the comparison against the floor: either "
         "it runs always (and the ceiling case asks for a phone it does not "
         "need) or it never runs")

# ── 3. the two refusals, and that neither degrades ──────────────────
gate = funcs.get("cadence_gate")
want(gate is not None, "there is no gate: the cadence has no floor in practice")
if gate is not None:
    gate_src = ast.unparse(gate)
    no_operator = False
    for n in ast.walk(gate):
        if isinstance(n, ast.If) and ("AEGIS_NONINTERACTIVE" in ast.unparse(n.test)
                                      or "isatty" in ast.unparse(n.test)):
            if "die(" in ast.unparse(n.body):
                no_operator = True
    want(no_operator,
         "the gate does not refuse when there is no operator: with "
         "AEGIS_NONINTERACTIVE, or with stdin not a terminal, there is "
         "nobody to read a phone, and answering «assume yes» there turns "
         "the whole door into a comment")
    # The second channel failing has to END the operation. A handler that
    # falls back to a prompt is the door asking the terminal to vouch for
    # itself.
    fell_back = []
    for n in ast.walk(gate):
        if not isinstance(n, ast.Try):
            continue
        if "ntfy_publish" not in ast.unparse(n.body):
            continue
        for h in n.handlers:
            text = ast.unparse(h)
            if "die(" not in text:
                fell_back.append("the handler does not stop")
            if "input(" in text:
                fell_back.append("the handler asks at the terminal instead")
    want("ntfy_publish" in gate_src and not fell_back,
         f"with no second channel the gate degrades ({'; '.join(fell_back) or 'it never publishes'}): "
         f"a confirmation typed at the same keyboard is theatre, and a brake "
         f"that yields when its mechanism is missing was never a brake")

    # ── 4. the code never becomes readable on this machine ──────────
    code_var = None
    for n in ast.walk(gate):
        if isinstance(n, ast.Assign) and "randbelow" in ast.unparse(n.value):
            code_var = n.targets[0].id
    want(code_var is not None,
         "the code is not generated with the random source meant for "
         "secrets: a predictable code is one the terminal can produce")
    if code_var:
        leaks = []
        for n in ast.walk(gate):
            if not isinstance(n, ast.Call):
                continue
            callee = getattr(n.func, "id", None) or getattr(n.func, "attr", None)
            if callee in ("ntfy_publish",):
                continue
            # The NAME and not the word. The prompt this gate prints
            # says «type: entendido <code>», and the first version of
            # this check read that sentence as the variable escaping —
            # it turned red over a message that names nothing. What
            # leaks is a reference, so a reference is what is looked
            # for, inside the arguments only.
            refs = [x for a in (n.args + [k.value for k in n.keywords])
                    for x in ast.walk(a)
                    if isinstance(x, ast.Name) and x.id == code_var]
            if refs and callee is not None:
                leaks.append(f"{callee}()")
        want(not leaks,
             f"the code reaches {sorted(set(leaks))}: it is only worth "
             f"something while it cannot be read on this machine — printed, "
             f"logged or written to a file, the terminal can answer its own "
             f"question")
        want(re.search(rf"\b{code_var}\b", code_of("cadence_record")) is None,
             "the code goes into the record: the trail says WHO confirmed "
             "and WHEN, and a code sitting in a file is a code the next "
             "reader can reuse")

# ── 5. who confirmed, and when ──────────────────────────────────────
rec = code_of("cadence_record")
want(rec, "nothing records who changed the cadence: a decision with no name "
          "and no date behind it is one nobody can ask about")
for field in ("cuando", "quien"):
    want(f'"{field}"' in rec or f"'{field}'" in rec,
         f"the record does not carry '{field}'")
want('"a"' in rec or "'a'" in rec,
     "the record is not opened in append mode: a trail that can be "
     "overwritten is not a trail (same rule as gates.jsonl)")

# ── 6. the drop-in REPLACES the cadence instead of adding to it ─────
drop = code_of("cadence_dropin")
want("OnUnitActiveSec=\\n" in drop or "OnUnitActiveSec=\n" in drop,
     "the drop-in does not reset the list before setting its value: in "
     "systemd a drop-in ADDS to a list-valued setting, so the shipped 24h "
     "stays in place and the timer fires on BOTH cadences — a timer that "
     "looks configured and runs twice")

print(f"    {measured} properties measured over the clock and its door",
      file=sys.stderr)
for m in bad:
    print(m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D155" ]]; then fail "the clock and its door:$D155"
else pass "the timer ships a 24h cadence, catches up a missed run and waits for the cluster; the capture stays the operator's; the floor is an hour and the gate runs before the drop-in is written; with no operator and with no second channel it refuses instead of degrading; the code never becomes readable on this machine, and what is recorded is who and when"; fi
}
