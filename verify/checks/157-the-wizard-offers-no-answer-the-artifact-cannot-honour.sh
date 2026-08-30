# title: the wizard offers no answer the artifact cannot honour
# origin: new in v3 — measured on 2026-08-29, the day AI=gpu stopped being a promise
check() {
# The wizard is a CONTRACT with the operator: every value it offers is
# a value some phase knows how to carry out. It was broken for weeks
# and nobody could see it from inside the code — the assistant offered
# `AI=gpu`, phase 87 did not exist, and choosing it produced a silent
# skip and a platform with no AI. The operator found out by reading
# the phases, which is not a way to find things out.
#
# The property is derived from three places that already have to be
# right, and never from a list here:
#
#   1. a validator `_v_x()` written as a chain of `== literal` is an
#      ENUMERATION: those are the values the wizard will accept.
#   2. `ask VAR "default" _v_x` binds that enumeration to a variable
#      and gives it a default.
#   3. whoever reads VAR — a phase or a command — has to name each of
#      those values somewhere, or there is a branch the operator can
#      choose and the artifact cannot serve.
#
# It also measures the default, which is the answer an operator gives
# by pressing Enter: a default the validator itself rejects is a
# wizard that cannot be walked through without typing.
#
# What it deliberately does NOT do is judge how a value is handled.
# `no` is served by skipping with a reason written, and that is a
# correct way to serve it. The check draws the line where it can
# measure without guessing: the value has to be NAMED by a consumer.
# A consumer that names it and does nothing is beyond a static reading
# — and it is the shape the teeth of the phases themselves cover.
CFG="$AEGIS_ROOT/lib/config.sh"
[[ -f "$CFG" ]] || { fail "lib/config.sh is not there: $CFG"; return; }
OUT="$(python3 - "$AEGIS_ROOT" <<'PY'
import os, re, sys, pathlib
R = pathlib.Path(sys.argv[1])
cfg = (R / "lib" / "config.sh").read_text()

# 1. the enumerating validators
enums = {}
for m in re.finditer(r'^(_v_[a-z0-9_]+)\(\)\s*\{(.*?)\}\s*$', cfg, re.M):
    name, body = m.group(1), m.group(2)
    vals = re.findall(r'"\$1"\s*==\s*([A-Za-z0-9_.-]+)', body)
    # a chain of == over literals, and NOTHING else: a validator that
    # also calls out to python or matches a regex is not an
    # enumeration and must not be read as one.
    if vals and not re.search(r'=~|python3|\[\[ -|\$\(', body):
        enums[name] = vals

# 2. the ask() calls that use one
asks = []
for m in re.finditer(r'^\s*ask\s+([A-Z][A-Z0-9_]*)\s+"([^"]*)"\s+(_v_[a-z0-9_]+)', cfg, re.M):
    var, default, val = m.groups()
    if val in enums:
        asks.append((var, default, val))

if not asks:
    print("FAILno wizard question was found bound to an enumerating validator — "
          "the check lost its subject and is NOT calling that a pass")
    raise SystemExit

# 3. the consumers: every file of the artifact that names the variable,
#    minus config.sh itself and the example conf, which are where the
#    question lives rather than where it is served.
places = [R / "init" / "phases", R / "libexec", R / "lib"]
files = [f for d in places if d.is_dir()
         for f in sorted(d.rglob("*")) if f.is_file()
         and f.name not in ("config.sh",)]
bad, n = [], 0
for var, default, val in asks:
    n += 1
    if default not in enums[val]:
        bad.append("%s: the wizard's default %r is not one of the values %s accepts (%s) "
                   "— pressing Enter would be rejected by the wizard itself"
                   % (var, default, val, "/".join(enums[val])))
    word = re.compile(r'(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])' % re.escape(var))
    consumers = [f for f in files if word.search(f.read_text(errors="replace"))]
    if not consumers:
        bad.append("%s is asked for and NOBODY reads it: the operator answers a "
                   "question that changes nothing" % var)
        continue
    joined = "\n".join(f.read_text(errors="replace") for f in consumers)
    for v in enums[val]:
        if not re.search(r'(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])' % re.escape(v), joined):
            bad.append("%s=%s is offered by the wizard and NAMED BY NO CONSUMER of %s: "
                       "the operator can choose it and no phase carries it out. This is "
                       "exactly the shape of AI=gpu before phase 87 existed"
                       % (var, v, var))
print("    %d wizard questions with an enumerated answer, over %d files that read them"
      % (n, len(files)))
for b in bad:
    print("FAIL" + b)
PY
)" || { fail "the reading of the wizard could not be completed"; return; }
printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "the wizard offers something the artifact does not serve: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "every value the wizard accepts is named by a consumer of its variable, and every default is a value the wizard itself accepts"
fi
}
