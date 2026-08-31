# teeth of check 161 — a host step a manifest declares is executed by
# somebody, and measured where it becomes true.

# THE STATE THE ARTIFACT WAS IN until 2026-08-31: the RuntimeClass
# enumerated three host steps and step 1 existed only as that comment.
# Take the task away and the comment is back to installing nothing.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" <<'PY'
import sys
p = sys.argv[1]
out = [l for l in open(p, encoding="utf-8") if "nvidia-container-toolkit" not in l]
open(p, "w", encoding="utf-8").writelines(out)
PY
}

# installed and NOT measured: the package can install fine and
# containerd never see it, and from the playbook's side those two are
# indistinguishable.
red_2() {
    sed -i 's/nvidia-runtime-in-containerd/nvidia-runtime-presente/g' \
        "$AEGIS_ROOT/init/phases/20-k3s.sh"
}

# measured, but against the wrong thing: asking whether the binary
# exists instead of whether the runtime k3s hands a Pod exists.
red_3() {
    sed -i 's|/var/lib/rancher/k3s/agent/etc/containerd/config.toml|/usr/bin/nvidia-ctk|; s|/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml|/usr/bin/nvidia-ctk2|' \
        "$AEGIS_ROOT/init/phases/20-k3s.sh"
}

# the drift that erases itself: editing by hand a file k3s regenerates
# from its template on every boot.
red_4() {
    printf '\n    - name: configure containerd by hand\n      ansible.builtin.command: nvidia-ctk runtime configure --runtime=containerd\n' \
        >> "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml"
}

# and the subject taken away: if the manifest stops naming the host
# package, the coupling stopped being written down and that has to be
# SAID, not passed. The shape of the bug found in check 004 on
# 2026-08-29.
red_5() {
    sed -i 's/nvidia-container-toolkit/el paquete correspondiente/g' \
        "$AEGIS_ROOT/seed/platform/k8s/base/gpu/runtimeclass.yaml"
}

# control: THE PROSE that explains why the hand edit is not done cannot
# turn it red. The first version of this check did exactly that — it
# read the paragraph and accused the file of doing what the paragraph
# says it refuses to do.
control_1() {
    printf '\n    # note: never nvidia-ctk runtime configure against k3s.\n' \
        >> "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml"
}

# control: more documentation in the manifest changes nothing.
control_2() {
    printf '\n# note: the handler name is fixed by k3s.\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/base/gpu/runtimeclass.yaml"
}
