"""Check 223 — a base rebuild names its members and tells nobody unless asked.

MEASURED 2026-09-13 on the house instance, standing up the first PHP
base. Ten iterations on base-images/php/Containerfile. Each one fired
the base-images job with MEMBERS empty, which meant «all of them», so
nginx and node were rebuilt too; each build carries BUILD_NUMBER in its
tag, so every run was a new digest; and the propagate stage had no
door, so every run rewrote the FROM of every one of the eleven consumer
repositories and queued two builds per repo. 168 builds and 1 042
agent-minutes in six hours, for one member.

Two facts the pipeline cannot learn on its own are now said by the
caller, and this check keeps every caller honest:

  · MEMBERS is REQUIRED. An empty value is an error in the pipeline,
    never «every member». Whoever wants every member names every
    member: `aegis ci build` reads the tree and prints the list; so
    does phase 80.
  · PROPAGATE is a boolean, born FALSE, declared in the Jenkinsfile and
    in the job-dsl alike. Only three callers mean it and all three say
    so: image-watch (a CVE fix is worth nothing until the consumers
    stand on it), phase 80 (the provisioner's line in services.yaml is
    written by propagation), and `aegis ci build --propagate`.

Descriptions are checked too: the job-dsl kept saying «MEMBERS empty =
every member» after the plan stopped it, and a description is what a
human reads before pressing the button.
"""
import os
import re
import sys

ROOT = sys.argv[1]
P = os.path.join(ROOT, "seed", "platform")
findings = []


def nc(path):
    """The file without its comment lines (Groovy //, shell/YAML #)."""
    with open(path, encoding="utf-8") as f:
        return "\n".join(ln for ln in f.read().splitlines()
                         if not re.match(r"^\s*(//|#)", ln))


def raw(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


JF = os.path.join(P, "base-images", "Jenkinsfile")
DSL = os.path.join(P, "k8s", "base", "platform", "jenkins", "values.yaml")
WATCH = os.path.join(P, "image-watch", "Jenkinsfile")
PH80 = os.path.join(ROOT, "init", "phases", "80-supply-chain.sh")
CI = os.path.join(ROOT, "libexec", "aegis-ci")
for f in (JF, DSL, WATCH, PH80, CI):
    if not os.path.isfile(f):
        print(f"SCOPE: {os.path.relpath(f, ROOT)} is missing")
        sys.exit(0)

jf, dsl = nc(JF), raw(DSL)

# ── 1. the two declarations are the same two parameters ─────────────
m = re.search(r"parameters\s*\{(.*?)\n\s*\}", jf, re.S)
jf_params = {}
if m:
    for kind, name, default in re.findall(
            r"(string|booleanParam)\(\s*name:\s*'([A-Z_]+)'\s*,\s*defaultValue:\s*([^,\n]+)", m.group(1)):
        jf_params[name] = (kind, default.strip().strip("'\""))
else:
    findings.append("the base-images Jenkinsfile declares no parameters {} block")

block = re.search(r"pipelineJob\('base-images'\)\s*\{(.*?)\n\s*definition\s*\{", dsl, re.S)
dsl_params = {}
dsl_block = ""
if block:
    dsl_block = block.group(1)
    for name, default in re.findall(r"stringParam\('([A-Z_]+)',\s*'([^']*)'", dsl_block):
        dsl_params[name] = ("string", default)
    for name, default in re.findall(r"booleanParam\('([A-Z_]+)',\s*(true|false)", dsl_block):
        dsl_params[name] = ("booleanParam", default)
else:
    findings.append("the job-dsl has no pipelineJob('base-images') block to compare against")

if jf_params and dsl_params and jf_params != dsl_params:
    findings.append(f"the Jenkinsfile and the job-dsl do not declare the same parameters: "
                    f"pipeline {jf_params!r}, job-dsl {dsl_params!r} — a manual «Build with "
                    f"Parameters» would show something the DSL does not say")
for name, kind, default in (("MEMBERS", "string", ""), ("PROPAGATE", "booleanParam", "false")):
    for who, params in (("Jenkinsfile", jf_params), ("job-dsl", dsl_params)):
        if params and name not in params:
            findings.append(f"the {who} does not declare {name}")
        elif params and params[name] != (kind, default):
            findings.append(f"the {who} declares {name} as {params[name]!r}, not ({kind!r}, {default!r}): "
                            f"{'consumers would be told by default' if name == 'PROPAGATE' else 'the member list must be a string'}")

# ── 2. MEMBERS empty is an error, never «all of them» ───────────────
stage = re.search(r"stage\('members'\)\s*\{(.*?)\n    stage\('", jf, re.S)
body = stage.group(1) if stage else ""
if not stage:
    findings.append("there is no stage('members') to read")
else:
    if re.search(r"\bmembers\s*=\s*all\b", body):
        findings.append("stage('members') still falls back to every member (`members = all`): an empty "
                        "MEMBERS rebuilds the whole set, which is the cascade")
    gate = re.search(r"if\s*\(\s*!\s*asked\s*\)\s*\{[^\n]*\n((?:[^\n]*\n){1,12})", body)
    if not gate or not re.search(r"^\s*error\b", gate.group(1), re.M):
        findings.append("an empty MEMBERS does not stop the pipeline: there is no `if (!asked)` that "
                        "raises error")

# ── 3. propagate has a door, and it is closed before any clone ──────
prop = re.search(r"stage\('propagate'\)\s*\{(.*?)\n    stage\('", jf, re.S)
pbody = prop.group(1) if prop else ""
if not prop:
    findings.append("there is no stage('propagate') to read")
else:
    door = re.search(r"if\s*\(\s*!\s*params\.PROPAGATE\s*\)\s*\{[^\n]*\n((?:[^\n]*\n){1,12})", pbody)
    if not door or not re.search(r"^\s*return\b", door.group(1), re.M):
        findings.append("stage('propagate') has no door on params.PROPAGATE that returns: every "
                        "member built rewrites every consumer, asked or not")
    else:
        i_door = pbody.index("params.PROPAGATE")
        i_read = pbody.find("consumers.txt")
        if i_read != -1 and i_read < i_door:
            findings.append("the PROPAGATE door comes after the consumers are read: the clones "
                            "are paid for before anyone asks whether to propagate")

# ── 4. the three callers say both ───────────────────────────────────
watch = nc(WATCH)
call = re.search(r"build\s+job:\s*'base-images'(.*?)wait:", watch, re.S)
if not call:
    findings.append("image-watch no longer fires base-images with a parameters list")
else:
    if not re.search(r"string\(name:\s*'MEMBERS'", call.group(1)):
        findings.append("image-watch fires base-images without naming MEMBERS")
    if not re.search(r"booleanParam\(name:\s*'PROPAGATE',\s*value:\s*true\)", call.group(1)):
        findings.append("image-watch fires base-images without PROPAGATE=true: a base rebuilt for a "
                        "CVE would be built, signed and forgotten")

ph = re.sub(r"\\\n\s*", " ", nc(PH80))          # join `\`-continued lines first
fire = re.search(r"jenkins_build_retry\s+base-images\b[^\n]*", ph)
if not fire:
    findings.append("phase 80 no longer fires base-images through jenkins_build_retry")
else:
    line = fire.group(0)
    if "MEMBERS=" not in line:
        findings.append("phase 80 fires base-images without MEMBERS: the pipeline refuses an empty one, "
                        "and the phase would gate red on its own first run")
    if "PROPAGATE=true" not in line:
        findings.append("phase 80 fires base-images without PROPAGATE=true: the provisioner's line in "
                        "services.yaml is written by propagation, and nothing else writes it")

ci = nc(CI)
# THE QUERY LINE, not the file: the log line beside it also says
# «PROPAGATE=», and a tooth that dropped the parameter from the query
# left the word in the log. Measured on the first teeth run.
query = re.search(r'^\s*q="MEMBERS=[^\n]*"\s*$', ci, re.M)
if not query:
    findings.append("aegis ci build never builds a MEMBERS query for base-images: the pipeline "
                    "refuses an empty one, so the chain would stop there")
elif "PROPAGATE=" not in query.group(0):
    findings.append("aegis ci build sends MEMBERS and never PROPAGATE: --propagate has nothing to say")
if not re.search(r"^\s*--propagate\)", ci, re.M):
    findings.append("aegis ci build has no --propagate flag")
if "ci_members_of_tree()" not in ci:
    findings.append("aegis ci build cannot spell «every member» as a list: with the pipeline refusing "
                    "an empty MEMBERS, the chain would stop at base-images")

# ── 5. the candidate RUNS before it is signed ───────────────────────
# The tar proves the image was built right; only a pod proves it starts.
# The step has to sit after the push (the kubelet pulls from the
# registry) and before cosign (unsigned, a failed candidate is inert for
# every tenant), and the pod it creates has to carry the tenant's four
# restrictions — a test under laxer rules passes images a tenant
# rejects.
build = re.search(r"stage\('build'\)\s*\{(.*?)\n    stage\('", jf, re.S)
bbody = build.group(1) if build else ""
if not build:
    findings.append("there is no stage('build') to read")
else:
    i_push = bbody.find("crane push")
    i_run = bbody.find("runtime-test.yaml")
    i_sign = bbody.find("cosign sign")
    if i_run == -1:
        findings.append("the build stage never runs the candidate as a pod: the first place a base "
                        "starts is a tenant's pod, after the signature and the propagation")
    else:
        if not (i_push != -1 and i_push < i_run):
            findings.append("the run step comes before the push: the kubelet has nothing to pull")
        if not (i_sign != -1 and i_run < i_sign):
            findings.append("the candidate is signed before it is run: a base that dies at start-up "
                            "would already carry the signature every tenant trusts")
        run = bbody[i_run:i_sign if i_sign != -1 else None]
        for want, why in (('"runAsNonRoot":true', "a tenant pod runs as non-root"),
                          ('"readOnlyRootFilesystem":true', "a tenant's root filesystem is read-only"),
                          ('"seccompProfile":{"type":"RuntimeDefault"}', "a tenant pod carries seccomp RuntimeDefault"),
                          ('"capabilities":{"drop":["ALL"]}', "a tenant pod drops every capability"),
                          ('"allowPrivilegeEscalation":false', "a tenant pod cannot escalate")):
            if want not in run:
                findings.append(f"the test pod is laxer than a tenant's: {why}, and the pod spec does not say {want}")
        if '"readinessProbe"' not in run or '"tcpSocket"' not in run:
            findings.append("the test pod has no TCP readiness probe: «it started» is not «it answers»")
        if "DELETE" not in run:
            findings.append("the test pod is never deleted: every build leaves one behind")
    if "serviceAccountName: base-images-agent" not in jf:
        findings.append("the agent pod does not run as base-images-agent: the API would refuse the test "
                        "pod, or the agent would carry a broader account than it needs")

RBAC = os.path.join(P, "k8s", "base", "platform", "jenkins-secrets", "rbac-base-images-agent.yaml")
KUST = os.path.join(P, "k8s", "base", "platform", "jenkins-secrets", "kustomization.yaml")
if not os.path.isfile(RBAC):
    findings.append("rbac-base-images-agent.yaml is missing: nothing grants the agent the one pod it needs")
else:
    rb = raw(RBAC)
    if "resources: [pods]" not in rb or "verbs: [create, get, list, watch, delete]" not in rb:
        findings.append("the agent's Role does not grant exactly pods create/get/list/watch/delete")
    if re.search(r"resources:\s*\[[^\]]*(secrets|pods/exec|deployments)", rb):
        findings.append("the agent's Role reaches past pods (secrets, exec or deployments): more than a "
                        "test pod needs")
    if os.path.isfile(KUST) and "rbac-base-images-agent.yaml" not in nc(KUST):
        findings.append("the kustomization does not list rbac-base-images-agent.yaml: the Role never reaches "
                        "the cluster")

# ── 6. the words match the code ─────────────────────────────────────
jf_descriptions = " ".join(re.findall(r"description:\s*'([^']*)'", m.group(1))) if m else ""
for who, text in (("the job-dsl", dsl_block), ("the Jenkinsfile", jf_descriptions)):
    if re.search(r"empty\s*=\s*(all of them|every member)", text, re.I):
        findings.append(f"{who} still says «empty = all/every member» in a description: a human reads "
                        f"that before pressing the button, and the code refuses it")

for f in findings:
    print(f)
print("SCOPE: 2 declarations compared, 3 stages read, 3 callers read, the test pod's spec and its Role read, 2 descriptions read")
