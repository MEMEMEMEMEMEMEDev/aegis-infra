# teeth for check 109 (no stage writes into an absent subsystem)
#
# The correct mutation is the REGRESSION, not something like it: take
# the guard off the stage and leave it as it was on 2026-08-24, when
# `aegis org apply` died with FileNotFoundError after having written
# six manifests.
#
# RE-AIMED on 2026-08-29. Until that day the absence was free: the seed
# shipped no AI subsystem, so taking the guard off a stage was enough
# to make it write blind. The subsystem came INTO the seed, the folder
# started existing, and a stage with no guard stopped being a defect —
# these two reds went on applying and the check went on being right,
# which reads exactly like a tooth that bites and is not. The full run
# said «1/3 bite» in both profiles.
#
# So the absence is now MADE, and that is truer to what the check
# measures: it asks whether the directory exists in the SEED, and the
# regression is a stage that writes into one that does not. The guard
# itself is not vestigial — it reads the INSTANCE's tree, where the
# folder can still be missing, and its second outcome (a contract
# promising `ai:` where there is no AI) is the reason it exists.
_no_ai_subsystem_in_seed() { rm -rf "$AEGIS_ROOT/seed/platform/k8s/base/ai-system"; }

red_1() {
    _no_ai_subsystem_in_seed
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('def apply_routes(write):\n'
              '    rc = _without_ai_subsystem("routes")\n'
              '    if rc is not None:\n'
              '        return rc\n',
              'def apply_routes(write):\n')
open(p, "w").write(s)
PY
}

# the other stage, because there are two and the check has to see both
red_2() {
    _no_ai_subsystem_in_seed
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('def apply_ai_registry(write):\n'
              '    rc = _without_ai_subsystem("AI registry")\n'
              '    if rc is not None:\n'
              '        return rc\n',
              'def apply_ai_registry(write):\n')
open(p, "w").write(s)
PY
}

# a NEW stage that writes blind into a subsystem that is not there: the
# check has to bite whatever comes, not only the two it already knows.
# That is the difference between watching the class and watching the case.
red_3() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


FUTURE_K8S = os.path.join(PLATFORM_ROOT, "k8s", "base", "future-subsystem", "something.yaml")


def apply_future(write):
    if write:
        open(FUTURE_K8S, "w", encoding="utf-8").write("x")
    return 0
PY
}

# control: a new stage that writes where the artifact DOES have a
# folder needs no guard at all, and turning red on that would be biting
# too much.
control_1() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


LEGITIMATE_K8S = os.path.join(PLATFORM_ROOT, "k8s", "bootstrap", "legitimate.yaml")


def apply_legitimate(write):
    if write:
        open(LEGITIMATE_K8S, "w", encoding="utf-8").write("x")
    return 0
PY
}
