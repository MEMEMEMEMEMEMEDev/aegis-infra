# title: nobody uses the secrets tmpfs before opening it, and the libraries say so
# origin: new in v3 — 2026-09-01, after a 401 was reported as a missing job
check() {
# `secrets_workdir` creates the per-phase tmpfs that ALL transient
# material lives in, and installs the trap that shreds it. Anything
# reading $SECRETS_TMP before that call is reading an unset variable.
#
# What makes this class expensive is not the failure, it is the
# DISTANCE between the failure and its report. Measured on 2026-09-01:
# phase 87 fired the ai-gateway build in 87.1a and did not open the
# tmpfs until 87.3. lib/jenkins.sh built the credential path out of an
# empty string, `cat ''` found nothing, Jenkins answered 401 to an
# anonymous request, and the phase announced «the Jenkins API is down
# or the job does not exist» — about a job that existed, with its main
# branch indexed. Three layers between cause and symptom, and every
# one of them pointed somewhere else.
#
# So two things, and the second is what keeps the distance short:
#
#   1. ORDER. In every phase, the first call to a helper that needs the
#      tmpfs comes after secrets_workdir. The set of such helpers is
#      DERIVED from lib/ — the functions that read $SECRETS_TMP, plus
#      everything that calls one of those, to a fixed point — because a
#      hand-written list is exactly what drifted here: the header of
#      lib/jenkins.sh named its consumers as phases 50, 60, 70 and 80
#      while 85 and 87 had already arrived.
#   2. THE PRECONDITION IS STATED. A library that reads $SECRETS_TMP
#      says so with ${SECRETS_TMP:?...}, so the message names the
#      missing setup instead of letting it surface as somebody else's
#      401 three frames away.
[[ -d "$AEGIS_ROOT/lib" ]] || { fail "there is no lib/: $AEGIS_ROOT/lib"; return; }

D163=""
python3 - "$AEGIS_ROOT" <<'PY' || D163="$D163 (see the detail above);"
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
libs = sorted((root / "lib").glob("*.sh"))
if not libs:
    print("lib/ holds no shell library: this check lost the subject it derives from",
          file=sys.stderr)
    sys.exit(1)

DEF = re.compile(r'^(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{')

# Comments are stripped EVERYWHERE, libraries included. The first
# version of this check did it only in the phases, and the prose of
# gate_diag — «the diagnosis may use functions from the libs
# (jenkins_get, etc.)» — was read as a call: a helper accused of a
# dependency its comment merely explains. The same trap check 161 had
# to be corrected for, on the same day. A `#` only opens a comment at
# the start of a line or after whitespace, so ${var#pat} survives.
COMMENT = re.compile(r'(^|\s)#.*$')
def code_of(line):
    return COMMENT.sub(r'\1', line)

# ── derive: which helpers need the tmpfs ───────────────────────────
bodies = {}
for f in libs:
    name, buf = None, []
    for line in f.read_text(encoding="utf-8").splitlines():
        m = DEF.match(line)
        if m:
            name, buf = m.group(1), []
            continue
        if name is not None:
            if line.startswith("}"):
                bodies[name] = "\n".join(buf)
                name = None
            else:
                buf.append(code_of(line))

# secrets_* own the variable: they are the setup and teardown, never
# the consumers, and marking them would accuse the fix itself.
needs = {n for n, b in bodies.items()
         if "SECRETS_TMP" in b and not n.startswith("secrets_")}
changed = True
while changed:                      # to a fixed point: a caller of a
    changed = False                 # consumer is itself a consumer
    for n, b in bodies.items():
        if n in needs or n.startswith("secrets_"):
            continue
        if any(re.search(r'(^|[^\w-])' + re.escape(k) + r'($|[^\w-])', b) for k in needs):
            needs.add(n); changed = True

bad = []
# ── (1) order, phase by phase ──────────────────────────────────────
for f in sorted((root / "init" / "phases").glob("*.sh")):
    open_at, first_use, used = None, None, None
    for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
        code = code_of(line)
        if not code.strip():
            continue
        if open_at is None and re.search(r'(^|[^\w-])secrets_workdir($|[^\w-])', code):
            open_at = i
        if first_use is None:
            for k in needs:
                if re.search(r'(^|[^\w-])' + re.escape(k) + r'($|[^\w-])', code):
                    first_use, used = i, k
                    break
    if first_use is None:
        continue                     # this phase touches no tmpfs helper
    if open_at is None:
        bad.append(f"{f.name}: calls {used}() at line {first_use} and never opens the tmpfs")
    elif open_at > first_use:
        bad.append(f"{f.name}: calls {used}() at line {first_use}, and opens the tmpfs "
                   f"at line {open_at} — {open_at - first_use} lines TOO LATE")

# ── (2) the libraries state the precondition ───────────────────────
for f in libs:
    src = f.read_text(encoding="utf-8")
    if f.name.startswith("secrets"):
        continue                     # it owns the variable
    if "SECRETS_TMP" in src and "SECRETS_TMP:?" not in src:
        bad.append(f"lib/{f.name}: reads $SECRETS_TMP and never states the precondition "
                   f"with ${{SECRETS_TMP:?...}} — with no tmpfs it builds a path out of "
                   f"the empty string and the error surfaces somewhere else")

if bad:
    print(f"derived {len(needs)} helpers that need the tmpfs; the offenders:", file=sys.stderr)
    for b in bad:
        print("   " + b, file=sys.stderr)
    sys.exit(1)
print(f"    {len(needs)} helpers need the tmpfs · every phase that calls one opens it first")
PY

if [[ -n "$D163" ]]; then fail "a phase uses the secrets tmpfs before opening it:$D163"
else pass "every phase opens the secrets tmpfs before the first helper that needs it, and every library that reads it states that precondition by name"; fi
}
