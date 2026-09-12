# teeth for check 132 (the chain never draws a link it did not measure)
#
# Every red puts a green tick on work nobody did. None of them fails:
# the command runs, the chain fills in, and the two links no other
# platform shows become decoration.

B132="$AEGIS_ROOT/libexec/aegis-builds"
J132="$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"

# THE RENAME. The pipeline calls the field something else and nobody
# tells the reader: None is not "true", so an image nobody scanned gets
# a tick.
red_1() { sed -i 's/"scan_skipped":%s/"scanned_ok":%s/' "$J132"; }

# the anti-loop's skip becomes work: a commit that touched only k8s/
# reports a build, a scan and a signature that never happened
red_2() { python3 - "$B132" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        return {link: "not-evaluable" for link in LINKS}, "no build (only manifests changed)"'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '        return {link: "done" for link in LINKS}, "no build (only manifests changed)"', 1))
P
}

# the scan's absence stops being an absence
red_3() { sed -i 's/chain\["scan"\] = "not-evaluable" if event.get("scan_skipped") == "true" else "done"/chain["scan"] = "done"/' "$B132"; }

# a build that never wrote its digest is drawn as deployed
red_4() { sed -i 's/chain\["digest"\] = "done" if event.get("digest") else "wrong"/chain["digest"] = "done"/' "$B132"; }

# the two links beyond this source disappear instead of being named:
# four ticks, and a reader who believes the deploy arrived
red_5() { python3 - "$B132" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''BEYOND = {"sync": "ArgoCD's Application status (aegis check, section 3)",
          "admission": "Kyverno's rejections in the tenant namespaces"}'''
assert s.count(old) == 1
p.write_text(s.replace(old, "BEYOND = {}", 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the prose of the report changes
control_1() { sed -i 's/newest first/most recent first/' "$B132"; }

# a field the pipeline DOES write is read as well: reading more of a
# real event is not inventing anything
control_2() { sed -i 's/"branch": event.get("branch"),/"branch": event.get("branch"), "tag2": event.get("tag"),/' "$B132"; }

# a third link beyond this source is named: more honesty about gaps is
# never a regression
control_3() { python3 - "$B132" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
p.write_text(s.replace('"admission": "Kyverno\'s rejections in the tenant namespaces"}',
                       '"admission": "Kyverno\'s rejections in the tenant namespaces",\n          "probe": "the sitio-<org> probe, once it is serving"}', 1))
P
}
