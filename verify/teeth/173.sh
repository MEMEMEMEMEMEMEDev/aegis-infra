# teeth of check 173 — a tenant AppProject is applied AFTER it is
# derived, not only at an init that had no tenants.
#
# Every red_ below is a state the tree WAS in, or the next shape of the
# same mistake. The controls are the ones this repo pays for most often:
# prose that names the defect, sitting next to the code that fixes it.

ORG="$AEGIS_ROOT/lib/aegis/org.py"
PH35="$AEGIS_ROOT/init/phases/35-gitops.sh"

# THE STATE OF THE TREE UNTIL 2026-09-02, and the one that cost the
# install: the step was announced only when the FILE CHANGED. Run
# `aegis org apply` twice —a typo, one more service— and the second run
# printed a quiet «=» while the cluster still had no project. Moving the
# record after the early return puts that back.
red_1() {
    python3 - "$ORG" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
call = "    _record_appprojects_step(new, old)\n"
assert t.count(call) == 1, "the record call moved: re-aim this tooth"
t = t.replace(call, "", 1)
# put it back where it only runs when something changed
anchor = '        open(APPPROJECTS_K8S, "w", encoding="utf-8").write(new)\n'
assert t.count(anchor) == 1
t = t.replace(anchor, anchor + "        _record_appprojects_step(new, old)\n", 1)
open(p, "w", encoding="utf-8").write(t)
PY
}

# The handover stops naming WHICH projects. The operator reads a generic
# reminder and cannot tell whether it concerns the organization just
# registered or one from three months ago — which is how a reminder
# becomes wallpaper.
red_2() {
    python3 - "$ORG" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
old = """        for n in names:
            mark = f"{yellow}!{off} new" if n in fresh else f"{grey}={off}   "
            print(f"  {mark}  {n}")
"""
assert t.count(old) == 1, "the naming loop moved: re-aim this tooth"
open(p, "w", encoding="utf-8").write(t.replace(old, "", 1))
PY
}

# The path goes back to being a literal typed into the message. Today it
# still points at the right file; the day the file moves, the constant
# moves with it and the message does not.
red_3() {
    sed -i "s|kubectl apply -f {step\['file'\]}|kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml|" \
        "$ORG"
}

# The handover is derived and never printed: main() stops calling it.
# The step exists in the code and reaches nobody, which is the same as
# not existing.
red_4() {
    python3 - "$ORG" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
call = "\n    report_pending_cluster()\n"   # the 4-space one: the run's own
assert t.count(call) == 1, "re-aim this tooth"
t = t.replace(call, "\n", 1)
open(p, "w", encoding="utf-8").write(t)
PY
}

# The step goes back INSIDE the stage that writes the file. `projects` is
# the fourth of twelve stages and the eight after it push it off the
# screen — the arrangement the operator was reading past.
red_5() {
    python3 - "$ORG" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
old = '''        open(APPPROJECTS_K8S, "w", encoding="utf-8").write(new)
'''
assert t.count(old) == 1
new = old + '''        print(f"    kubectl apply -f {APPPROJECTS_REL}")
'''
t = t.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(t)
PY
}

# The other side of the same rule: with zero organizations there is
# nothing to apply, and a notice that is always on says as much as no
# notice at all (Disease E). Recording unconditionally turns the empty
# instance into a permanent warning.
red_6() {
    python3 - "$ORG" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
old = """    names = _appproject_names(new)
    if not names:
        return
"""
assert t.count(old) == 1, "re-aim this tooth"
new = """    names = _appproject_names(new) or ["aegis-tenant-none"]
"""
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# And the half that has to keep working: phase 35 stops applying the
# derived file. An init over a tree that ALREADY carries contracts —a
# re-init, a restore, a lab copy— would leave every organization at
# "project not found" from the first minute.
red_7() {
    python3 - "$PH35" <<'PY'
import sys
p = sys.argv[1]
out = []
for line in open(p, encoding="utf-8"):
    if line.lstrip().startswith("#"):
        out.append(line); continue
    if "kubectl apply" in line and "appprojects-tenants.yaml" in line:
        continue
    out.append(line)
open(p, "w", encoding="utf-8").writelines(out)
PY
}

# control: THE PROSE. A comment in phase 35 that spells out the very
# command the operator has to run, next to the code. If this turns the
# check red, the check is reading the paragraph and not the phase — the
# mistake this repo made eight times in one day.
control_1() {
    printf '\n# note: after the init, an organization reaches the cluster with\n#   kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml\n# and that is not done here: it is handed over by `aegis org apply`.\n' \
        >> "$PH35"
}

# control: the same, on the generator's side, and worded as the defect —
# «the step is announced only when the file changes» — which is exactly
# the sentence a check hunting for that defect would trip over.
control_2() {
    printf '\n# history: until 2026-09-02 the step was announced only when the file\n# changed, and no function of this module printed kubectl apply -f for\n# the second run. That is the bug, written down so nobody repeats it.\n' \
        >> "$ORG"
}

# control: the derived artifact's own header is prose too. Rewording it
# changes what the generator writes into the file, and must not change
# the verdict: this check reads the AppProject DOCUMENTS, not the banner
# above them.
control_3() {
    sed -i 's/# AND SO NOBODY APPLIES THEM ON ITS OWN\./# AND NOBODY ELSE APPLIES THEM, EVER./' "$ORG"
}

# control: one more organization. The generator derives two projects
# instead of one and the check has to stay green — it measures the shape
# of the handover, not a count.
control_4() {
    printf 'organizacion: another\nrepo: git@github.com:__GH_OWNER__/another.git\n' \
        > "$AEGIS_ROOT/seed/platform/orgs/another.yaml"
}
