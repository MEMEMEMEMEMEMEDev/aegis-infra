# teeth of check 177 — the jobs the ci command fires are the ones the
# job-dsl declares.
#
# Every mutation asserts its own anchor, so one whose target moved is
# reported BROKEN instead of quietly not biting: an inert mutation and a
# blind check are different faults and need different fixes (the lesson
# the harness learned on 2026-08-25).

# THE STATE THE ARTIFACT WAS IN on 2026-09-01: the four platform jobs
# written out by hand and used as the acceptance set, so
# `aegis ci build engine-gpu` answered «engine-gpu is not a job of the
# chain» about a job this very artifact creates.
red_1() {
    python3 - "$AEGIS_ROOT/libexec/aegis-ci" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
out = s.replace('    values="$(ci_values_file)"',
                '    CI_JOB_NAMES=(mirror-images ci-images base-images image-watch)\n'
                '    CI_JOB_KINDS=(pipeline pipeline pipeline pipeline)\n'
                '    CI_VALUES="(the list lives in this file)"\n'
                '    return 0\n'
                '    values="$(ci_values_file)"', 1)
assert out != s, "the anchor of red_1 is gone"
open(p, "w", encoding="utf-8").write(out)
PYEOF
}

# the multibranch built as its FOLDER. A folder has no build of its own
# — its branch does — so the trigger lands on an item Jenkins cannot
# build, and the job looks broken instead of misaddressed.
red_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-ci" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
out = s.replace('''    if [[ "$2" == multibranch ]]; then printf '%s/%s' "$1" "${3:-main}"
    else printf '%s' "$1"; fi''',
                '''    printf '%s' "$1"''', 1)
assert out != s, "the anchor of red_2 is gone"
open(p, "w", encoding="utf-8").write(out)
PYEOF
}

# the nesting written by hand instead of asked of the library. Jenkins
# repeats /job/ at every level, and /job/blog-mb/main is the 404 that
# phase 87 reported as «the job does not exist» about a job that was
# there with its branch indexed.
red_3() {
    python3 - "$AEGIS_ROOT/libexec/aegis-ci" <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
out = re.sub(r'\$\(_jenkins_job "(\$[A-Za-z_{][^"]*)"\)', r'\1', s)
assert out != s, "the anchor of red_3 is gone"
open(p, "w", encoding="utf-8").write(out)
PYEOF
}

# the refusal goes back to offering a CONSTANT. It still says no to a
# name that is not a job; what it stops doing is telling the operator
# the names that grew — which is how eight jobs stayed invisible.
red_4() {
    python3 - "$AEGIS_ROOT/libexec/aegis-ci" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
out = s.replace('which declares: $(ci_job_list)"',
                'which declares: mirror-images ci-images base-images image-watch"', 1)
assert out != s, "the anchor of red_4 is gone"
open(p, "w", encoding="utf-8").write(out)
PYEOF
}

# the reader dies. It has to take the command —and this check— with it:
# an empty set makes every name the operator types look invalid, and
# that is a verdict about the reader dressed up as one about the
# artifact.
red_5() {
    python3 - "$AEGIS_ROOT/libexec/aegis-ci" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
out = s.replace("import re, sys, yaml\n",
                "import re, sys, yaml\nraise SystemExit('the reader is broken')\n", 1)
assert out != s, "the anchor of red_5 is gone"
open(p, "w", encoding="utf-8").write(out)
PYEOF
}

# a job the job-dsl gains gets no ceiling. jenkins_wait_build reads an
# empty timeout as zero and gives up on its first lap, which arrives at
# the operator looking like a build that failed instantly.
red_6() {
    python3 - "$AEGIS_ROOT/libexec/aegis-ci" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
out = s.replace("        *)             echo 1800 ;;   # a job nobody has measured still gets a ceiling\n", "", 1)
assert out != s, "the anchor of red_6 is gone"
open(p, "w", encoding="utf-8").write(out)
PYEOF
}

# the order outlives its job: a name in CHAIN_ORDER the job-dsl no
# longer declares would be fired by the default run and answered 404 —
# the same drift, in the one list that could not be derived away.
red_7() {
    python3 - "$AEGIS_ROOT/libexec/aegis-ci" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
out = s.replace("CHAIN_ORDER=(mirror-images ci-images base-images image-watch)",
                "CHAIN_ORDER=(mirror-images ci-images base-images image-watch tofu-images)", 1)
assert out != s, "the anchor of red_7 is gone"
open(p, "w", encoding="utf-8").write(out)
PYEOF
}

# control: THE PROSE. libexec/aegis-ci tells this bug's story in its own
# header, error message included, so the job names are in the file. A
# check that reads that paragraph as the list it forbids accuses the
# text documenting the fix — eight times in one day, which is why the
# scan strips comments before looking at anything.
control_1() {
    cat >> "$AEGIS_ROOT/libexec/aegis-ci" <<'EOF'

# note, for whoever reads this next: on 2026-09-01 this file answered
# «engine-gpu is not a job of the chain: mirror-images ci-images
# base-images image-watch» — and mirror-images, ci-images, base-images,
# image-watch, engine-cpu, engine-gpu, hello-aegis-mb and ai-gateway-mb
# were all jobs of the same instance that morning. The names above are
# a quotation, not a list.
EOF
}

# control: THE ARTIFACT GROWS. A new job in the job-dsl is exactly what
# happened when the AI lanes arrived, and it is the change that used to
# leave this command behind. With the set derived it stays green with
# nothing else touched.
control_2() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml" <<'PYEOF'
import re, sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").readlines()
start = next(i for i, l in enumerate(lines) if re.match(r'^ {6}aegis-jobs: \|\s*$', l))
end = next((i for i in range(start + 1, len(lines))
            if lines[i].strip() and not lines[i].startswith(" " * 7)), len(lines))
lines.insert(end, "          - script: >\n"
                  "              pipelineJob('engine-npu') {\n"
                  "                displayName('engine-npu (AI: one more lane)')\n"
                  "              }\n")
open(p, "w", encoding="utf-8").writelines(lines)
PYEOF
}

# control: A COMMENT INSIDE THE JOB-DSL that spells out a pipelineJob.
# Those `#` lines are comments of the inner YAML, so prose there is not
# a job on either side of the comparison. If this turns red, one of the
# two readers stopped parsing and started grepping.
control_3() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml" <<'PYEOF'
import re, sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").readlines()
start = next(i for i, l in enumerate(lines) if re.match(r'^ {6}aegis-jobs: \|\s*$', l))
end = next((i for i in range(start + 1, len(lines))
            if lines[i].strip() and not lines[i].startswith(" " * 7)), len(lines))
lines.insert(end, "          # retired on 2026-08-30: pipelineJob('tofu-images') built the\n"
                  "          # edge's tooling before aegis-ci-tofu was mirrored instead.\n")
open(p, "w", encoding="utf-8").writelines(lines)
PYEOF
}
