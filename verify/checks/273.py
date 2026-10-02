"""Check 273 — tofu never prints a value of the state through the wrapper.

MEASURED 2026-09-30 on alpha-arch: `aegis destroy` without --yes printed
the tunnel's secret. hashicorp/random does not mark random_id's values
sensitive, so `plan -destroy` showed `b64_std = "…" -> null`; and a
random_id's ID is the secret itself, so every `Creation complete … [id=…]`
of phase 25's apply had written it into the install log as well.

tofu-apply.sh is the one door every tofu call goes through (A14). For
plan / apply / destroy it now filters what tofu prints. This sidecar
copies the wrapper next to a throw-away env, puts a FAKE `tofu` first on
PATH that prints a real-shaped plan carrying a secret (attribute values,
a heredoc, `[id=…]`, an error), runs the wrapper in CI mode (tokens
exported, nothing decrypted) and asserts:
  · no secret on the screen for plan, apply and destroy, under every awk
    this machine has as `awk` (the distro's mawk included when present);
  · addresses, the summary and the error still show;
  · the exit code is tofu's (plan -detailed-exitcode's 2 included);
  · `output -raw` is NOT filtered (phase 25 captures it);
  · AEGIS_TOFU_SHOW_VALUES=1 is the one way to see the values.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
WRAPPER = os.path.join(ROOT, "seed", "platform", "tofu", "tofu-apply.sh")
SECRET = "q8Zr1hX3SECRETvalueOFtheTUNNEL"
findings = []

FAKE = r'''#!/bin/sh
for a in "$@"; do case "$a" in -*) ;; *) sub="$a"; break ;; esac; done
case "$sub" in
  output) printf '%s' "SECRETVALUE"; exit 0 ;;
esac
cat <<PLAN
  # module.tunnel.random_id.tunnel_secret will be destroyed
  - resource "random_id" "tunnel_secret" {
      - b64_std     = "SECRETVALUE=" -> null
      - id          = "SECRETVALUE" -> null
    }
  # module.tunnel.cloudflare_dns_record.cname["grafana"] will be updated in-place
  ~ resource "cloudflare_dns_record" "cname" {
        id      = "SECRETVALUE-id"
        tags    = <<-EOT
            SECRETVALUE-heredoc
        EOT
    }
Plan: 0 to add, 1 to change, 1 to destroy.
module.tunnel.random_id.tunnel_secret: Destroying... [id=SECRETVALUE]
│ Error: tunnel has active connections
PLAN
[ "$sub" = plan ] && exit 2
exit 0
'''.replace("SECRETVALUE", SECRET)

awks = ["awk"] + [a for a in ("mawk", "gawk") if shutil.which(a)]
scope_runs = 0
with tempfile.TemporaryDirectory() as tmp:
    tofu_dir = os.path.join(tmp, "platform", "tofu")
    env_dir = os.path.join(tofu_dir, "envs", "t")
    os.makedirs(env_dir)
    shutil.copy(WRAPPER, os.path.join(tofu_dir, "tofu-apply.sh"))
    with open(os.path.join(env_dir, "variables.tf"), "w") as f:
        f.write('variable "cloudflare_api_token" {\n  type = string\n}\n')
    for a in awks:
        bindir = os.path.join(tmp, f"bin-{a}")
        os.makedirs(bindir)
        with open(os.path.join(bindir, "tofu"), "w") as f:
            f.write(FAKE)
        os.chmod(os.path.join(bindir, "tofu"), 0o755)
        if a != "awk":
            os.symlink(shutil.which(a), os.path.join(bindir, "awk"))
        env = {"PATH": bindir + os.pathsep + os.environ["PATH"], "HOME": tmp,
               "TF_VAR_cloudflare_api_token": "t", "AEGIS_INIT_CONF": os.path.join(tmp, "none")}

        def run(*args, extra=None):
            e = dict(env, **(extra or {}))
            return subprocess.run(["bash", os.path.join(tofu_dir, "tofu-apply.sh"), "-chdir=envs/t", *args],
                                  capture_output=True, text=True, env=e, timeout=60)

        for sub in (["plan", "-detailed-exitcode"], ["apply", "-auto-approve"], ["destroy", "-auto-approve"]):
            p = run(*sub)
            out = p.stdout + p.stderr
            scope_runs += 1
            if SECRET in out:
                findings.append(f"[{a}] `{sub[0]}` printed a value of the state")
            if "module.tunnel.random_id.tunnel_secret will be destroyed" not in out or "Plan: 0 to add" not in out:
                findings.append(f"[{a}] `{sub[0]}` hid the addresses or the summary: the operator cannot read what it does")
            if "Error: tunnel has active connections" not in out:
                findings.append(f"[{a}] `{sub[0]}` hid tofu's error (aegis destroy retries on its words)")
            want = 2 if sub[0] == "plan" else 0
            if p.returncode != want:
                findings.append(f"[{a}] `{sub[0]}` exited {p.returncode}, not tofu's {want}: the filter ate the exit code")
        p = run("output", "-raw", "tunnel_token")
        if p.stdout != SECRET:
            findings.append(f"[{a}] `output -raw` is filtered or decorated: phase 25's capture would read {p.stdout[:20]!r}")
        p = run("plan", extra={"AEGIS_TOFU_SHOW_VALUES": "1"})
        if SECRET not in p.stdout + p.stderr:
            findings.append(f"[{a}] AEGIS_TOFU_SHOW_VALUES=1 does not show the values: debugging by hand has no way in")

for x in findings:
    print(x)
print(f"SCOPE: the wrapper run {scope_runs} time(s) over a fake tofu (plan, apply, destroy) under {', '.join(awks)}; output -raw and the escape hatch")
