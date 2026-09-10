# teeth of check 193 — the node's reservation is a derived drop-in,
# written whenever there is a value, and taken back out if the node
# does not return.

# THE RESERVATION MOVED INTO THE FILE THAT ALREADY HAS AN OWNER. That
# task is grepped literally by check 024 and is written only when this
# host runs systemd-resolved — a memory reservation has no business
# depending on either.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("          resolv-conf: /run/systemd/resolve/resolv.conf\n",
              "          resolv-conf: /run/systemd/resolve/resolv.conf\n"
              "          kubelet-arg:\n"
              "            - \"system-reserved=memory=6Gi\"\n")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the drop-in hung off systemd-resolved. On a host without it the node
# would silently keep nothing back — the exact gap that made a separate
# file the right shape.
red_2() {
    python3 - "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("      when: aegis_node_reserved | default('') | length > 0",
              "      when: resolved_real.stat.exists")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the numbers written into the playbook. One machine's arithmetic
# applied to every other machine that ever installs this.
red_3() {
    python3 - "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('        content: "{{ aegis_node_reserved }}"',
              '        content: |\n'
              '          kubelet-arg:\n'
              '            - "system-reserved=memory=6Gi"\n')
open(p, "w", encoding="utf-8").write(s)
PY
}

# the phase stops deriving the value. The playbook is deliberately
# dumb, so if the phase does not derive it, nothing does.
red_4() {
    sed -i 's|reservation --for kubelet|reserva-del-nodo|' "$AEGIS_ROOT/init/phases/20-k3s.sh"
}

# THE VALVE REMOVED. A malformed kubelet-arg stops k3s from starting,
# and this is the difference between a few seconds of downtime and a
# machine that does not come back.
red_5() {
    python3 - "$AEGIS_ROOT/init/phases/20-k3s.sh" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'\n *sudo -n rm -f "\$AEGIS_RESERVED_FILE"\n', "\n", s)
open(p, "w", encoding="utf-8").write(s)
PY
}

# and the task gone entirely: the node keeps nothing back and the
# scheduler goes on believing it owns every byte.
red_6() {
    python3 - "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("        dest: /etc/rancher/k3s/config.yaml.d/10-aegis-node-reserved.yaml",
              "        dest: /etc/rancher/k3s/otra-cosa.yaml")
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: prose in the playbook EXPLAINING why the reservation is not
# in config.yaml. Naming system-reserved is not writing one.
control_1() {
    python3 - "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("    - name: k3s config directories",
              "    # a legitimate note: system-reserved=memory= is NOT written here;\n"
              "    # it arrives derived, in its own drop-in.\n"
              "    - name: k3s config directories")
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: one more kubelet-arg in the derived content. Growing what
# the node keeps back has to stay green, because the content comes from
# the command and not from here.
control_2() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('        \'  - "enforce-node-allocatable=pods"\',',
              '        \'  - "enforce-node-allocatable=pods"\',\n'
              '        \'  - "kube-reserved=memory=0"\',')
open(p, "w", encoding="utf-8").write(s)
PY
}

# THE VALVE'S PROBE THAT CAN ONLY SAY NO. `wait_for TIMEOUT EVERY WHAT
# cmd...` eats three arguments before the command; passing the verb
# where the label goes leaves `get --raw=/readyz` as the command, which
# is not one. Measured 2026-09-10: the probe never succeeded, the valve
# fired after 180 s, and a reservation that was working was rolled back
# on a cluster that was healthy the whole time. A safety net that
# cannot say yes is a timer that turns the feature off.
red_7() {
    sed -i 's|    if wait_for 180 5 "the API to answer after the restart" \\|    if wait_for 180 5 kubectl get --raw=/readyz \\|' \
        "$AEGIS_ROOT/init/phases/20-k3s.sh"
}
