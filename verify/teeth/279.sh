# teeth of check 279 — traefik buffers bodies in a volume with a ceiling.
V279="$AEGIS_ROOT/seed/platform/k8s/base/ingress/traefik/values.yaml"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the chart as it was: Go writes to /tmp, no ceiling
red_1() { _sub "$V279" 'env:
  - name: TMPDIR
    value: /buffer
' ''; }

# the volume without its ceiling
red_2() { _sub "$V279" '      emptyDir:
        sizeLimit: 2Gi' '      emptyDir: {}'; }

# TMPDIR points where nothing is mounted (read-only root)
red_3() { _sub "$V279" '    value: /buffer' '    value: /var/buffer'; }

# the mount names a volume nobody declares
red_4() { _sub "$V279" '  additionalVolumes:
    - name: buffer' '  additionalVolumes:
    - name: bufer'; }

# ── controls ──
control_1() { _sub "$V279" 'sizeLimit: 2Gi' 'sizeLimit: 3Gi'; }
