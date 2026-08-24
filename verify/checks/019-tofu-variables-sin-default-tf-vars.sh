# titulo: tofu: variables sin default ↔ TF_VARs del wrapper
# origen: verify-static.sh (v2) ══ 19
check() {
# Corrida #4: toda variable declarada sin default y no inyectada =
# prompt INTERACTIVO latente de tofu (rompe D11). Cruce estático:
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"semilla"/"plataforma"
wrapper = (P/"tofu"/"tofu-apply.sh").read_text()
# solo ASIGNACIONES export reales — mencionar el nombre en un guard
# o mensaje no inyecta nada (el primer teeth-test de este check se
# dejó engañar exactamente por eso):
injected = set(re.findall(r'^\s*export TF_VAR_([a-z0-9_]+)=', wrapper, re.M))
envs = set()
for ph in (root/"init"/"phases").glob("*.sh"):
    envs |= set(re.findall(r'envs/([a-z0-9-]+)', ph.read_text()))
ok = True; n = 0
for env in sorted(envs):
    for tf in (P/"tofu"/"envs"/env).glob("*.tf"):
        text = tf.read_text()
        # bloques variable "x" { ... } (llaves balanceadas a 1 nivel):
        for m in re.finditer(r'variable\s+"([a-z0-9_]+)"\s*\{(.*?)\n\}',
                             text, re.S):
            name, body = m.group(1), m.group(2)
            n += 1
            if "default" in body: continue
            if name not in injected:
                print(f"FAIL {env}: variable '{name}' sin default NI "
                      f"TF_VAR del wrapper → prompt interactivo latente")
                ok = False
print(f"variables tofu cruzadas contra el wrapper: {n} (envs: {', '.join(sorted(envs))})")
sys.exit(0 if ok else 1)
EOF
then pass "toda variable tofu sin default está inyectada por el wrapper"
else fail "variable tofu que tofu pediría interactiva"; fi
}
