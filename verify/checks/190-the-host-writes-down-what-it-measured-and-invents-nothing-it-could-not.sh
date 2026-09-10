# title: the machine is measured in one place, written down, and never invented where it could not be read
# origin: new in v3 — measured on 2026-09-09, the day a freeze had no trace because nothing recorded the host
check() {
# Until 2026-09-09 the product read the machine's RAM in exactly one
# line, `aegis preflight`, compared it against 7 GiB, printed it, and
# threw it away. Nothing downstream could size anything to the host,
# because there was nowhere the host was written down. That is how two
# AI engines carrying 18 GiB of declared limits came to be deployed on
# a 30 GiB workstation with a graphical session; and when the session
# froze, the instance had no series to show for it — the numbers in the
# post-mortem had to be reconstructed from cAdvisor's root cgroup,
# which happens to be there and was never meant to be the record.
#
# Four properties keep that from coming back, and the fourth is the one
# that matters most:
#
#   1 · ONE MEASURER. The machine's RAM is read in a single file. Two
#     readers is two thresholds and, eventually, two answers — the
#     shape the disk requirement is in right now (25 GiB here, 20 in
#     the init's own gate, for the same thing).
#   2 · IT IS WRITTEN DOWN, atomically. A half-written host.json is
#     worse than none: what is derived from it are reservations, and a
#     truncated number is a plausible one.
#   3 · THE READER DOES NOT RE-MEASURE. `aegis preflight` consumes the
#     measurement instead of taking its own; a reader with its own
#     probe is a second measurer wearing a different hat.
#   4 · NOTHING IS INVENTED. A probe that fails returns null and the
#     fact is named in `undetermined`. No `or 0`, no default, no
#     helpful zero. This is `vram_limit_mib`'s rule generalised: an
#     unmeasured threshold is not a permissive one, it is an absent
#     one, and a budget derived from a RAM total nobody read looks
#     exactly like one derived from a real machine.
HOST="$LIBEXEC/aegis-host"
PRE="$LIBEXEC/aegis-preflight"
[[ -f "$HOST" ]] || { fail "libexec/aegis-host is not there: $HOST"; return; }
[[ -f "$PRE"  ]] || { fail "libexec/aegis-preflight is not there: $PRE"; return; }

D190=""

# ── 1 · one measurer ─────────────────────────────────────────────────
# PROSE IS STRIPPED FIRST, and both kinds of it. A file EXPLAINING that
# it no longer reads /proc/meminfo must not count as a file that reads
# it — six repetitions of that mistake are on this project's record,
# and the seventh happened here: `lib/aegis/host.py` names the path
# inside a DOCSTRING, which `#`-stripping does not touch. A bash
# comment stripper is not enough for a python file.
READERS="$(python3 - "$LIBEXEC" "$LIBS" "$PHASES" "$AEGIS_ROOT/bin" <<'PY'
import pathlib, re, sys

def code(p):
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    if p.suffix == ".py" or s.startswith("#!/usr/bin/env python"):
        s = re.sub(r'"""(?:.|\n)*?"""', "", s)
        s = re.sub(r"'''(?:.|\n)*?'''", "", s)
    return "\n".join(l.split("#", 1)[0] for l in s.splitlines())

# A MENTION IS NOT A USE — verify/lib.sh says so, and checks 22, 25,
# 66 and 71 paid for the lesson. A message that TELLS the operator to
# re-run on a machine where /proc/meminfo is readable names the path
# without reading it; counting that as a second measurer is the same
# mistake in a different costume. So the path has to appear next to
# something that actually opens a file.
READS = re.compile(r"_read\(|open\(|read_text|\bawk\b|\bgrep\b|\bsed\b|\bcat\b|<\s*/proc")

seen = []
for d in sys.argv[1:]:
    root = pathlib.Path(d)
    if not root.is_dir():
        continue
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        for line in code(p).splitlines():
            if re.search(r"MemTotal|/proc/meminfo", line) and READS.search(line):
                seen.append(p.name)
                break
print(" ".join(sorted(set(seen))))
PY
)"
READERS=" $READERS"
NREAD=$(printf '%s' "$READERS" | wc -w)
if [[ "$NREAD" -eq 0 ]]; then
    D190="$D190 nothing in the product reads the machine's RAM: with no measurer there is no host profile, and every budget derived from one is derived from nothing;"
elif [[ "$NREAD" -gt 1 ]]; then
    D190="$D190 the machine's RAM is read in $NREAD places ($READERS): two measurers become two thresholds and then two answers, which is the state the disk requirement is in;"
elif [[ "$READERS" != " aegis-host" ]]; then
    D190="$D190 the machine's RAM is measured by$READERS and not by aegis-host: the fact has to be written down by the command that owns host.json, or it is measured and lost again;"
fi

# ── 2, 3, 4 · the shape of the measuring and of its first reader ─────
OUT="$(python3 - "$HOST" "$PRE" <<'PY'
import re, sys

host = open(sys.argv[1], encoding="utf-8").read()
pre = open(sys.argv[2], encoding="utf-8").read()

def fn_body(name, text):
    m = re.search(r'^def %s\(.*?\):\n(.*?)(?=\n(?:def|class)\s|\Z)'
                  % re.escape(name), text, re.M | re.S)
    return m.group(1) if m else None

def strip_py_comments(b):
    out = []
    for line in b.splitlines():
        s = line.split("#", 1)[0]
        out.append(s)
    return "\n".join(out)

# strip the docstrings too, so prose about "or 0" is not code
host_code = re.sub(r'"""(?:.|\n)*?"""', '', host)

meas = fn_body("measure", host_code)
if meas is None:
    print("FAILaegis-host has no measure() to inspect: the command that owns the "
          "host profile does not define the verb that produces it")
    raise SystemExit

# 4 · the honesty ledger, derived from the facts and not hand-written
if not re.search(r'undetermined\s*=.*is None', meas, re.S):
    print("FAILmeasure() does not derive `undetermined` from the facts that came "
          "back None: without that ledger a null is indistinguishable from a zero, "
          "and a consumer cannot tell 'nobody looked' from 'there is none'")
if '"undetermined"' not in meas and "'undetermined'" not in meas:
    print("FAILthe document measure() writes carries no `undetermined` key: the "
          "record would claim a complete measurement it does not have")

# 4b · no probe substitutes a number for a failed reading
for m in re.finditer(r'^def (probe_\w+|_meminfo_kb)\(.*?\):\n(.*?)(?=\n(?:def|class)\s|\Z)',
                     host_code, re.M | re.S):
    name, body = m.group(1), strip_py_comments(m.group(2))
    bad = re.search(r'\bor\s+-?\d+\b', body) or re.search(r'return\s+-?\d+\s*$', body, re.M)
    if bad and "return 0" not in body[:0]:
        # a literal numeric fallback inside a probe is exactly the
        # substitution this check exists to forbid
        print("FAIL%s falls back to a literal number (%s): a probe that could not "
              "measure has to return null, or the fact arrives downstream looking "
              "measured" % (name, bad.group(0).strip()))

# 2 · atomic write
wa = fn_body("_write_atomic", host_code)
if wa is None:
    print("FAILaegis-host does not define _write_atomic: host.json is what "
          "reservations are derived from, and a half-written one is a plausible "
          "wrong number rather than an obvious missing file")
elif "os.replace" not in wa:
    print("FAILthe host profile is not written through os.replace: without the "
          "rename the file can be read half-written, and what is read out of it "
          "are the kubelet's reservation and the desktop's floor")

# 3 · the first reader consumes the measurement, it does not retake it
pre_code = "\n".join(l.split("#", 1)[0] for l in pre.splitlines())
if not re.search(r'aegis-host["\s]+measure', pre_code):
    print("FAILaegis-preflight does not invoke `aegis host measure`: its resources "
          "section is where the machine used to be measured and forgotten, and it "
          "has to be a reader now, not a second measurer")
if re.search(r'awk[^\n]*MemTotal', pre_code):
    print("FAILaegis-preflight still reads MemTotal with its own awk: that is the "
          "measure-and-discard line this whole area exists to remove")
PY
)" || { fail "the reading of aegis-host / aegis-preflight could not be completed"; return; }

printf '%s\n' "$OUT" | grep -v '^FAIL'
D190="$D190$(printf '%s\n' "$OUT" | sed -n 's/^FAIL/ /p' | tr '\n' ';')"

printf '    %s file(s) read the machine RAM · measure(), its ledger, its write and its first reader inspected\n' "$NREAD"
if [[ -n "${D190// /}" ]]; then
    fail "the host profile:$D190"
else
    pass "the machine is measured in one place, written down atomically, consumed rather than re-measured, and never invented"
fi
}
