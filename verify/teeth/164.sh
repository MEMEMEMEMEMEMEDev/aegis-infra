# teeth of check 164 — a nested Jenkins item is addressed the way
# Jenkins addresses it.

# THE STATE THE ARTIFACT WAS IN until 2026-09-01: the paths were built
# out of the raw name and the caller had to remember the /job/ in the
# middle. One forgotten interpolation is one silent 404.
red_1() {
    python3 - "$AEGIS_ROOT/lib/jenkins.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('/job/$(_jenkins_job "$job")/', '/job/$job/', 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

# the translation gone: every call site is back to writing the nesting
# by hand, which is the arrangement that failed.
red_2() {
    python3 - "$AEGIS_ROOT/lib/jenkins.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("_jenkins_job()", "_jenkins_ruta()", 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

# present and INERT: it exists, it is called everywhere, and it hands
# back what it was given. Structure alone would call this healthy —
# which is why the check runs it.
red_3() {
    python3 - "$AEGIS_ROOT/lib/jenkins.sh" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'_jenkins_job\(\) \{.*?\n\}',
           '_jenkins_job() {\n    printf \'%s\' "$1"\n}', s, count=1, flags=re.S)
open(p, "w", encoding="utf-8").write(s)
PY
}

# NOT idempotent: a path that was already correct comes out as
# a/job/job/b, and the five call sites that were right break the day
# this lands. The regression this check exists to make impossible.
red_4() {
    python3 - "$AEGIS_ROOT/lib/jenkins.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('[[ -n "$seg" && "$seg" != "job" ]] || continue',
              '[[ -n "$seg" ]] || continue', 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: PROSE showing the wrong shape is how the bug gets explained.
# A check that reads its own documentation as the defect is the trap
# checks 161 and 163 were both corrected for.
control_1() {
    printf '\n# note: never /job/$job/ for a nested item — see _jenkins_job.\n' \
        >> "$AEGIS_ROOT/lib/jenkins.sh"
}

# control: a phase naming the branch in the natural form is correct
# now — that is the whole point of the library doing the translation.
control_2() {
    sed -i 's|_job="ai-gateway-mb/main"|_job="ai-gateway-mb/job/main"|' \
        "$AEGIS_ROOT/init/phases/87-ai.sh"
}
