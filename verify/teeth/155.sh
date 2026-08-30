# teeth for check 155 (the clock and its door)
# generated on 2026-08-29 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# The mutations are the shapes the door could plausibly be worn down
# into — none of them is cosmetic, and every one of them leaves
# something that still looks like a door.

# The floor stops being an hour. Anything passes, and the
# capture becomes a load on every tenant's live postgres.
red_1() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'CADENCE_FLOOR_S = 3600'
new = 'CADENCE_FLOOR_S = 0'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# The gate is no longer called: the door under an hour does not
# exist, whatever the comments above it still say.
red_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    if seconds < CADENCE_FLOOR_S:\n        entry = cadence_gate(set_to, seconds)\n        ok(f"confirmed on the second channel by {entry[\'quien\']} at "\n           f"{entry[\'cuando\']} — recorded in the instance\'s trail")\n    else:\n        cadence_record(set_to, seconds, "terminal")'
new = '    cadence_record(set_to, seconds, "terminal")'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# The drop-in is written BEFORE the gate runs. By the time the
# code is asked for, the cadence has already changed.
red_3() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    if seconds < CADENCE_FLOOR_S:\n        entry = cadence_gate(set_to, seconds)'
new = '    path0 = cadence_dropin_path()\n    os.makedirs(os.path.dirname(path0), exist_ok=True)\n    with open(path0, "w", encoding="utf-8") as f0:\n        f0.write(cadence_dropin(set_to))\n    if seconds < CADENCE_FLOOR_S:\n        entry = cadence_gate(set_to, seconds)'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# With no operator it assumes yes. That single line turns the
# whole door into a comment, and it is the change somebody makes to
# get a script through.
red_4() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    if os.environ.get("AEGIS_NONINTERACTIVE") or not sys.stdin.isatty():\n        die(f"a cadence under {CADENCE_FLOOR_S // 60} minutes needs a "'
new = '    if os.environ.get("AEGIS_NONINTERACTIVE") or not sys.stdin.isatty():\n        return cadence_record(text, seconds, "non-interactive")\n    if False:\n        die(f"a cadence under {CADENCE_FLOOR_S // 60} minutes needs a "'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# With no second channel it falls back to a confirmation typed
# at the same keyboard: the door asking the terminal to vouch for
# itself.
red_5() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    except cli.CouldNotEvaluate as e:\n        die(f"a cadence under {CADENCE_FLOOR_S // 60} minutes needs a second "'
new = '    except cli.CouldNotEvaluate as e:\n        if input("  ntfy is not there. type y to confirm anyway: ") == "y":\n            return cadence_record(text, seconds, "terminal")\n        die(f"a cadence under {CADENCE_FLOOR_S // 60} minutes needs a second "'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# The code is shown on the terminal «so the operator can check
# it arrived». A code the terminal can read is a code the terminal can
# answer, and the whole property is gone.
red_6() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    print(f"  a code went to the phone on the {NTFY_TOPIC} topic. It is not "'
new = '    print(f"  the code sent was {code}", file=sys.stderr)\n    print(f"  a code went to the phone on the {NTFY_TOPIC} topic. It is not "'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# The code goes into the record «for the audit». It sits in a
# file the next reader can reuse.
red_7() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '        "canal": channel,'
new = '        "canal": channel,\n        "codigo": code,'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# The drop-in loses the empty assignment. In systemd a drop-in
# ADDS to a list-valued setting, so the shipped 24h stays and the timer
# fires on BOTH: configured-looking, and running twice.
red_8() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '            f"[Timer]\\n"\n            f"OnUnitActiveSec=\\n"'
new = '            f"[Timer]\\n"'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# The timer loses its cadence: nothing fires, and nothing says so.
red_9() {
    python3 - "$AEGIS_ROOT/share/systemd/aegis-backup.timer" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'OnUnitActiveSec=24h'
new = '# OnUnitActiveSec=24h'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# The timer stops catching up a missed run. On a desktop that
# sleeps at night the machine can go days without a backup with the
# timer looking healthy the whole time.
red_10() {
    python3 - "$AEGIS_ROOT/share/systemd/aegis-backup.timer" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'Persistent=true'
new = 'Persistent=false'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# The unit becomes root's. That hands root the age key that
# opens every bundle this platform ever wrote, to save writing --user.
red_11() {
    python3 - "$AEGIS_ROOT/share/systemd/aegis-backup.service" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '[Service]\nType=oneshot'
new = '[Service]\nUser=root\nType=oneshot'
assert t.count(old) == 1, f'anchor x{t.count(old)}'
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# control: narrating the degradation is not performing it. A comment
# describing the «type y to confirm» that this door refuses to be must
# stay green.
control_1() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    if os.environ.get("AEGIS_NONINTERACTIVE") or not sys.stdin.isatty():'
new = ('    # Not: `if input("type y to confirm") == "y": return`. That was the\n'
       '    # shape this refuses to have — a confirmation the terminal can\n'
       '    # give itself.\n'
       '    if os.environ.get("AEGIS_NONINTERACTIVE") or not sys.stdin.isatty():')
assert t.count(old) == 1
open(p, 'w').write(t.replace(old, new, 1))
PY
}

# control: a THIRD refusal added beside the two — the gate getting
# stricter is not the gate breaking, and the check must not read it as
# one.
control_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-data" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    cost = cadence_cost(seconds)'
new = ('    if os.environ.get("SSH_CONNECTION"):\n'
       '        die("not over ssh: the phone and the keyboard have to be in "\n'
       '            "the same pair of hands, and over ssh nobody can tell")\n'
       '    cost = cadence_cost(seconds)')
assert t.count(old) == 1
open(p, 'w').write(t.replace(old, new, 1))
PY
}
