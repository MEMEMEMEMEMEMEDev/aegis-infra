# title: tofu: variables with no default ↔ the wrapper's TF_VARs
# origin: verify-static.sh (v2) ══ 19
check() {
# Run #4: every variable declared with no default and not injected =
# a latent INTERACTIVE prompt from tofu (it breaks D11). Static
# cross-check:
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
wrapper = (P/"tofu"/"tofu-apply.sh").read_text()
# only real export ASSIGNMENTS — mentioning the name in a guard or a
# message injects nothing (the first teeth-test of this check was
# fooled by exactly that):
injected = set(re.findall(r'^\s*export TF_VAR_([a-z0-9_]+)=', wrapper, re.M))
envs = set()
for ph in (root/"init"/"phases").glob("*.sh"):
    envs |= set(re.findall(r'envs/([a-z0-9-]+)', ph.read_text()))
ok = True; n = 0
for env in sorted(envs):
    for tf in (P/"tofu"/"envs"/env).glob("*.tf"):
        text = tf.read_text()
        # variable "x" { ... } blocks (braces balanced at 1 level):
        for m in re.finditer(r'variable\s+"([a-z0-9_]+)"\s*\{(.*?)\n\}',
                             text, re.S):
            name, body = m.group(1), m.group(2)
            n += 1
            if "default" in body: continue
            if name not in injected:
                print(f"FAIL {env}: variable '{name}' with no default AND no "
                      f"TF_VAR from the wrapper → latent interactive prompt")
                ok = False
print(f"tofu variables cross-checked against the wrapper: {n} (envs: {', '.join(sorted(envs))})")
sys.exit(0 if ok else 1)
EOF
then pass "every tofu variable with no default is injected by the wrapper"
else fail "a tofu variable that tofu would ask for interactively"; fi
}
