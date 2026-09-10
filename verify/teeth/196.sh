# teeth of check 196 — no panel calls the root cgroup the machine, and
# the host family's absence guard names every one of its subjects.

# THE PANEL THAT LIED, put back exactly as it was. «Machine memory»
# reading cAdvisor's root cgroup leaves out swap, slab and the page
# cache — which is why, on the day the desktop was being paged out to
# make room for the AI engines, the panel that should have shown it
# stayed calm.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/dashboards/usage.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(r'100 * (1 - last_over_time(aegis_host_ram_available_bytes[5m]) / last_over_time(aegis_host_ram_total_bytes[5m]))',
              r'100 * sum(container_memory_working_set_bytes{id=\\\"/\\\"}) / sum(machine_memory_bytes)')
open(p, "w", encoding="utf-8").write(s)
PY
}

# the other half of the same lie, on the panel that names free memory.
red_2() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/dashboards/usage.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(r'last_over_time(aegis_host_ram_available_bytes[5m])',
              r'sum(machine_memory_bytes) - sum(container_memory_working_set_bytes{id=\\\"/\\\"})', 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

# the absence guard gone. Every rule in the family compares against a
# value, so all of them go EMPTY rather than false when the host stops
# reporting — and an empty rule looks exactly like a healthy machine.
red_3() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'\n *- alert: MedicionDelAnfitrionAusente\n(?:.*\n)*?(?= *[a-z_]+\.yaml: \||\Z)', "\n", s)
open(p, "w", encoding="utf-8").write(s)
PY
}

# the guard kept, but watching only the heartbeat. One probe can die
# while the rest keep pushing, and this sleeps through it.
red_4() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'(- alert: MedicionDelAnfitrionAusente\n *expr: )[^\n]*',
           r'\1absent(last_over_time(aegis_host_metrics_timestamp_seconds[15m]))', s)
open(p, "w", encoding="utf-8").write(s)
PY
}

# and the whole family gone: the machine publishes and nothing alerts,
# which is paying for a measurement nobody reads.
red_5() {
    sed -i 's|^  anfitrion.yaml: ||  anfitrion_viejo.yaml: ||' \
        "$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml"
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'\n  anfitrion\.yaml: \|\n(?:.*\n)*?\Z', "\n", s)
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: a panel that reads the root cgroup and SAYS SO. The root
# cgroup is a legitimate subject; what is forbidden is calling it the
# machine.
control_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/dashboards/usage.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(r'\"title\": \"Memory by subsystem\"',
              r'\"title\": \"Memory of the root cgroup\"', 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: CPU read from the root cgroup, which is honest. Every
# process lives in some cgroup and the root aggregates them, so there
# is no page cache hiding outside it — the divergence this check
# watches is specific to memory.
control_2() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/dashboards/usage.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(r'\"title\": \"Machine CPU\"', r'\"title\": \"Machine CPU (host)\"', 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: one more rule in the family, with its subject named in the
# guard. Growing the family has to stay green.
control_3() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("          - alert: MedicionDelAnfitrionAusente",
              "          - alert: PocaRamLibre\n"
              "            expr: last_over_time(aegis_host_ram_available_bytes[5m]) < 1073741824\n"
              "            for: 10m\n"
              "            labels: {severity: warning}\n"
              "            annotations:\n"
              "              summary: \"less than a gigabyte of RAM is available\"\n"
              "              description: \"A legitimate extra rule over a series the guard already names.\"\n"
              "          - alert: MedicionDelAnfitrionAusente")
open(p, "w", encoding="utf-8").write(s)
PY
}
