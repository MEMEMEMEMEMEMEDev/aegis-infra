"""Check 273 — tofu never prints a value of the state through the wrapper.

MEASURED 2026-09-30 on alpha-arch: `aegis destroy` without --yes printed
the tunnel's secret. hashicorp/random does not mark random_id's values
sensitive, so `plan -destroy` showed `b64_std = "…" -> null`; and a
random_id's ID is the secret itself, so every `Creation complete … [id=…]`
of phase 25's apply had written it into the install log as well.

tofu-apply.sh is the one door every tofu call goes through (A14). For
plan / apply / destroy it filters what tofu prints.

AND MEASURED 2026-10-02, re-reading before the series: the first filter
did not work on a real tofu. OpenTofu colours what it prints even into a
pipe (`ESC[32m+ESC[0m input = "…"`), the filter matched plain lines, and
this check had passed against a fake tofu that printed no colour. So the
fake now behaves like the binary — it colours unless it is given
`-no-color` — and, when this machine has `tofu`, the wrapper is also run
over the REAL one (a `terraform_data` resource: built in, no network).

What is asserted, for plan, apply and destroy:
  · no value of the state on the screen, with a tofu that honours
    `-no-color` and with one that colours anyway;
  · `-no-color` sits right after the subcommand (after a positional plan
    file it would be read as a second positional);
  · addresses, the summary and the error still show;
  · the exit code is tofu's (plan -detailed-exitcode's 2 included);
  · tofu's prompt («Enter a value: », no newline) reaches the screen
    BEFORE tofu is answered — a filter that holds it leaves an apply by
    hand waiting, mute;
  · `output -raw` is NOT filtered (phase 25 captures it);
  · AEGIS_TOFU_SHOW_VALUES=1 is the one way to see the values.
"""
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(sys.argv[1])
WRAPPER = os.path.join(ROOT, "seed", "platform", "tofu", "tofu-apply.sh")
SECRET = "q8Zr1hX3SECRETvalueOFtheTUNNEL"
findings = []

# A tofu that prints what the real one prints: coloured, unless -no-color
# is among its arguments (FAKE_ALWAYS_COLOUR=1: coloured whatever it is
# told, for the filter's own stripping). It records its arguments, and
# with FAKE_PROMPT=1 it asks and waits, as an apply by hand does.
FAKE = r'''#!/bin/sh
printf '%s\n' "$@" > "$FAKE_ARGS"
for a in "$@"; do case "$a" in -*) ;; *) sub="$a"; break ;; esac; done
case "$sub" in
  output) printf '%s' "SECRETVALUE"; exit 0 ;;
esac
G="$(printf '\033[32m')"; R="$(printf '\033[31m')"; B="$(printf '\033[1m')"; Z="$(printf '\033[0m')"
case " $* " in *" -no-color "*) [ "${FAKE_ALWAYS_COLOUR:-0}" = 1 ] || { G=""; R=""; B=""; Z=""; } ;; esac
cat <<PLAN
  ${B}# module.tunnel.random_id.tunnel_secret${Z} will be destroyed
  ${R}-${Z}${Z} resource "random_id" "tunnel_secret" {
      ${R}-${Z}${Z} b64_std     = "SECRETVALUE=" ${Z}-> null
      ${R}-${Z}${Z} id          = "SECRETVALUE" ${Z}-> null
    }
  ${B}# module.tunnel.cloudflare_dns_record.cname["grafana"]${Z} will be updated in-place
  ${G}~${Z}${Z} resource "cloudflare_dns_record" "cname" {
        id      = "SECRETVALUE-id"
        tags    = <<-EOT
            SECRETVALUE-heredoc
        EOT
    }
${B}Plan:${Z} 0 to add, 1 to change, 1 to destroy.
module.tunnel.random_id.tunnel_secret: Destroying... [id=SECRETVALUE]
PLAN
# the errors go to stderr, as the binary's do, and may name a value too
cat >&2 <<ERR
│ ${R}Error: ${Z}tunnel has active connections
│   with module.tunnel.random_id.tunnel_secret [id=SECRETVALUE],
ERR
if [ "${FAKE_PROMPT:-0}" = 1 ]; then
  printf '  %sEnter a value:%s ' "$B" "$Z"
  read -r answer
  printf '\nanswered %s\n' "$answer"
fi
[ "$sub" = plan ] && exit 2
exit 0
'''.replace("SECRETVALUE", SECRET)

scope = []
with tempfile.TemporaryDirectory() as tmp:
    tofu_dir = os.path.join(tmp, "platform", "tofu")
    env_dir = os.path.join(tofu_dir, "envs", "t")
    os.makedirs(env_dir)
    shutil.copy(WRAPPER, os.path.join(tofu_dir, "tofu-apply.sh"))
    with open(os.path.join(env_dir, "variables.tf"), "w") as f:
        f.write('variable "cloudflare_api_token" {\n  type = string\n}\n')
    bindir = os.path.join(tmp, "bin")
    os.makedirs(bindir)
    with open(os.path.join(bindir, "tofu"), "w") as f:
        f.write(FAKE)
    os.chmod(os.path.join(bindir, "tofu"), 0o755)
    args_file = os.path.join(tmp, "args")
    base = {"HOME": tmp, "TF_VAR_cloudflare_api_token": "t",
            "AEGIS_INIT_CONF": os.path.join(tmp, "none"), "FAKE_ARGS": args_file}
    fake_env = dict(base, PATH=bindir + os.pathsep + os.environ["PATH"])
    cmd = ["bash", os.path.join(tofu_dir, "tofu-apply.sh"), "-chdir=envs/t"]

    def run(*args, extra=None):
        return subprocess.run(cmd + list(args), capture_output=True, text=True,
                              env=dict(fake_env, **(extra or {})), timeout=60)

    for mode, extra in (("a tofu that honours -no-color", {}),
                        ("a tofu that colours anyway", {"FAKE_ALWAYS_COLOUR": "1"})):
        for sub in (["plan", "-detailed-exitcode"], ["apply", "-auto-approve"], ["destroy", "-auto-approve"]):
            p = run(*sub, extra=extra)
            out = p.stdout + p.stderr
            if SECRET in out:
                findings.append(f"[{mode}] `{sub[0]}` printed a value of the state")
            if "module.tunnel.random_id.tunnel_secret will be destroyed" not in out or "Plan: 0 to add" not in out:
                findings.append(f"[{mode}] `{sub[0]}` hid the addresses or the summary: the operator cannot read what it does")
            if "Error: tunnel has active connections" not in out:
                findings.append(f"[{mode}] `{sub[0]}` hid tofu's error (aegis destroy retries on its words)")
            elif "Error: tunnel has active connections" in p.stdout:
                findings.append(f"[{mode}] `{sub[0]}` moved tofu's error to stdout: a caller that silences stdout loses it")
            if "will be destroyed" in p.stderr:
                findings.append(f"[{mode}] `{sub[0]}` moved the plan to stderr: stdout is where tofu prints it")
            want = 2 if sub[0] == "plan" else 0
            if p.returncode != want:
                findings.append(f"[{mode}] `{sub[0]}` exited {p.returncode}, not tofu's {want}: the filter ate the exit code")
            given = open(args_file).read().split("\n")
            at = given.index(sub[0]) if sub[0] in given else -1
            if at < 0 or given[at + 1:at + 2] != ["-no-color"]:
                findings.append(f"[{mode}] `{sub[0]}` was not given -no-color right after the subcommand: a real tofu colours its lines and the values pass (measured 2026-10-02)")
        scope.append(mode)

    p = run("output", "-raw", "tunnel_token")
    if p.stdout != SECRET:
        findings.append(f"`output -raw` is filtered or decorated: phase 25's capture would read {p.stdout[:20]!r}")
    if "-no-color" in open(args_file).read().split("\n"):
        findings.append("`output` is given -no-color: only what is filtered is touched")
    p = run("plan", extra={"AEGIS_TOFU_SHOW_VALUES": "1"})
    if SECRET not in p.stdout + p.stderr:
        findings.append("AEGIS_TOFU_SHOW_VALUES=1 does not show the values: debugging by hand has no way in")

    # The prompt has to be on the screen BEFORE the answer is given.
    pr = subprocess.Popen(cmd + ["apply"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, env=dict(fake_env, FAKE_PROMPT="1"))
    seen, deadline = b"", time.time() + 20
    while time.time() < deadline and b"Enter a value:" not in seen:
        if select.select([pr.stdout], [], [], 0.5)[0]:
            chunk = os.read(pr.stdout.fileno(), 65536)
            if not chunk:
                break
            seen += chunk
    asked = b"Enter a value:" in seen
    try:
        rest, _ = pr.communicate(b"no\n", timeout=30)
    except subprocess.TimeoutExpired:
        pr.kill()
        rest = b""
    if not asked:
        findings.append("tofu's prompt («Enter a value:») does not reach the screen until tofu is answered: an apply by hand waits mute")
    if SECRET.encode() in seen + rest:
        findings.append("the interactive apply printed a value of the state")
    scope.append("the prompt of an apply by hand")

    # THE BINARY DECIDES: the real tofu, when this machine has one.
    real = shutil.which("tofu")
    if real:
        renv = os.path.join(tofu_dir, "envs", "r")
        os.makedirs(renv)
        with open(os.path.join(renv, "variables.tf"), "w") as f:
            f.write('variable "cloudflare_api_token" {\n  type = string\n}\n')
        with open(os.path.join(renv, "main.tf"), "w") as f:
            f.write('resource "terraform_data" "x" {\n  input = "%s"\n}\n'
                    'resource "terraform_data" "h" {\n  input = <<-EOT\n    %s-heredoc\n  EOT\n}\n' % (SECRET, SECRET))
        real_env = dict(base, PATH=os.environ["PATH"], TF_IN_AUTOMATION="1", CHECKPOINT_DISABLE="1")
        rcmd = ["bash", os.path.join(tofu_dir, "tofu-apply.sh"), "-chdir=envs/r"]
        # tofu resolves -chdir against the caller's directory, as the
        # product's callers do (`cd $PLATFORM_DIR/tofu`).
        i = subprocess.run(rcmd + ["init", "-input=false"], capture_output=True, text=True, env=real_env, timeout=120, cwd=tofu_dir)
        if i.returncode != 0:
            scope.append("the real tofu could not init here (not measured)")
        else:
            p = subprocess.run(rcmd + ["plan", "-input=false", "-detailed-exitcode"],
                               capture_output=True, text=True, env=real_env, timeout=120, cwd=tofu_dir)
            out = p.stdout + p.stderr
            if SECRET in out:
                findings.append("the REAL tofu's plan shows a value of the state through the wrapper")
            if "\x1b[" in out:
                findings.append("the REAL tofu's plan reaches the screen with escape codes: -no-color did not arrive")
            if "terraform_data.x will be created" not in out or "(not shown)" not in out:
                findings.append("the REAL tofu's plan lost its addresses, or nothing was redacted: the filter does not recognise what tofu prints")
            if p.returncode != 2:
                findings.append(f"the REAL tofu's plan -detailed-exitcode exited {p.returncode}, not 2")
            v = subprocess.run([real, "version"], capture_output=True, text=True, timeout=30).stdout.splitlines()[:1]
            scope.append(f"the real {' '.join(v) or 'tofu'} over a terraform_data plan")
    else:
        scope.append("no tofu on this machine (the real one not measured)")

for x in findings:
    print(x)
print(f"SCOPE: the wrapper run over {'; '.join(scope)}; output -raw and the escape hatch")
