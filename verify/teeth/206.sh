# teeth for 206 — the inventory must see every class. Each red blinds
# ONE reader, which is exactly how a real regression would arrive.
P206="$AEGIS_ROOT/lib/aegis/pins.py"

# the charts stop being read: thirteen versions vanish quietly
red_1() { python3 - "$P206" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    apps = platform / "k8s" / "argocd-apps"'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    apps = platform / "k8s" / "argocd-apps-gone"', 1))
P
}

# the images written by hand in the manifests stop being read
red_2() { python3 - "$P206" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'READERS = (_mirror, _containerfiles, _charts, _raw_images, _jenkinsfiles, _group_vars)'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'READERS = (_mirror, _containerfiles, _charts, _jenkinsfiles, _group_vars)', 1))
P
}

# the CI's pod templates stop being read
red_3() { python3 - "$P206" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    for f in sorted(platform.rglob("Jenkinsfile*")):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    for f in sorted(platform.rglob("Jenkinsfile.none")):', 1))
P
}

# the colon of a port is read as a tag again: half the references lose
# their version and are dropped for having none
red_4() { python3 - "$P206" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    slash = ref.rfind("/")
    colon = ref.rfind(":")
    if colon > slash:'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    slash = ref.rfind("/")
    colon = ref.find(":")
    if colon > slash:''', 1))
P
}

# a pin arrives with no file and no line: nobody could edit it
red_5() { python3 - "$P206" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        d = {"clase": self.cls, "nombre": self.name, "version": self.current,
             "donde": [{"fichero": p, "linea": n} for p, n in self.where],'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        d = {"clase": self.cls, "nombre": self.name, "version": self.current,
             "donde": [],''', 1))
P
}

# ── controls ──
# the words of a comment are not a reader
control_1() { printf '\n# note: every pin lives where it is consumed; this file only reads.\n' >> "$P206"; }
# a class gains a friendlier label: the derivation is untouched
control_2() { sed -i 's/"the CI.s pod templates"/"the pod templates of the CI"/' "$AEGIS_ROOT/libexec/aegis-update"; }
# one more reader that finds nothing changes no answer
control_3() { python3 - "$P206" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'READERS = (_mirror, _containerfiles, _charts, _raw_images, _jenkinsfiles, _group_vars)'
assert s.count(old) == 1
p.write_text(s.replace(old, '''def _nothing(root, platform, pins):
    """a reader for a class this tree does not carry"""
    return


READERS = (_mirror, _containerfiles, _charts, _raw_images, _jenkinsfiles, _group_vars, _nothing)''', 1))
P
}
