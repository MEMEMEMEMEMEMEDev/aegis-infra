# teeth of check 200 — the requirements both READMEs publish are the
# ones plans.yaml declares and the preflight measures.

# THE STATE THAT WAS MEASURED, put back: the init's gate holding its own
# opinion. Twenty here, twenty-five in `aegis preflight`, twenty-five in
# both READMEs, and nobody able to say which was the requirement.
red_1() {
    python3 - "$AEGIS_ROOT/init/phases/00-preflight.sh" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'gate "disco-suficiente" bash -c \'(?:.|\n)*?\'\n',
           'gate "disco-20G" bash -c \\\n'
           "    '[[ $(df --output=avail -BG / | tail -1 | tr -dc 0-9) -ge 20 ]]'\n", s)
open(p, "w", encoding="utf-8").write(s)
PY
}

# the published promise drifting from the enforced number. This is the
# worse direction: a README that states a requirement the artifact does
# not hold reads as a measurement and is not one.
red_2() {
    sed -i 's|25 GB libres en `/`|40 GB libres en `/`|' "$AEGIS_ROOT/README.md"
}

# and the same drift in the English door, which is the one that has
# rotted before: on 2026-08-29 it was 250 lines against 595.
red_3() {
    sed -i 's|25 GB free on `/`|40 GB free on `/`|' "$AEGIS_ROOT/README.en.md"
}

# the number taken out of its single home. Everything downstream goes
# back to holding copies.
red_4() {
    sed -i 's|^  disco_minimo: 25Gi$|  disco_libre_minimo: 25Gi|' \
        "$AEGIS_ROOT/seed/platform/plans.yaml"
}

# the requirements section stops offering the command that answers the
# question it raises. The reader is left estimating on a product that
# can measure.
red_5() {
    python3 - "$AEGIS_ROOT/README.en.md" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("aegis host measure", "el comando de medicion").replace(
    "aegis host budget", "el comando de presupuesto").replace(
    "aegis host floor --set", "el comando de piso")
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: the requirement CHANGED, in its one home and in both places
# that publish it. That is the edit this whole arrangement exists to
# make cheap, and it has to stay green.
control_1() {
    sed -i 's|^  disco_minimo: 25Gi$|  disco_minimo: 30Gi|' \
        "$AEGIS_ROOT/seed/platform/plans.yaml"
    sed -i 's|25 GB libres en `/`|30 GB libres en `/`|' "$AEGIS_ROOT/README.md"
    sed -i 's|25 GB free on `/`|30 GB free on `/`|' "$AEGIS_ROOT/README.en.md"
}

# control: prose in a reader that NAMES a number without comparing
# against it. The comment explaining that the threshold moved to
# plans.yaml must not read as the threshold staying.
control_2() {
    printf '\n# a legitimate note: this used to compare -ge 25 by hand.\n' \
        >> "$AEGIS_ROOT/libexec/aegis-preflight"
}
