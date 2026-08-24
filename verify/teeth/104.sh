# teeth for check 104 (no command reads another one's prose)
# A3: aegis-app decided whether the webhook had been created by looking
# for the phrase «webhook creado» in the other command's output.
red_1() {
    cat >> "$AEGIS_ROOT/libexec/aegis-app" <<'PY'


def _a3_regression():
    import subprocess
    r = subprocess.run(["aegis-webhook", "--aplicar"], capture_output=True, text=True)
    return "webhook creado" in r.stdout
PY
}
