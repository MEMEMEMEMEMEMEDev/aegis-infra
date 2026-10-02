# teeth of check 269 — the watch looks at what runs in the tenants.
W269="$AEGIS_ROOT/seed/platform/image-watch/Jenkinsfile"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# a service's repo (the indented `- repo:` under servicios) is not read: only the top-level one
red_1() { _sub "$W269" "sed -n 's/^[[:space:]]*-\\\\{0,1\\\\}[[:space:]]*repo:" "sed -n 's/^repo:"; }

# newName is ignored: the image scanned is the one the overlay renames away from
red_2() { _sub "$W269" '                  /^[[:space:]]*newName:/ { n = $0; sub(/.*newName:[[:space:]]*/, "", n); sub(/[[:space:]].*/, "", n); next }
' ''; }

# a never-built app is scanned as if it ran
red_3() { _sub "$W269" "              if (dg ==~ /sha256:0{64}/) {" "              if (false) {"; }

# an app is scanned with the mirror's exceptions
red_4() { _sub "$W269" "            def r = pullAndScan(\"\${env.REGISTRY}/\${dst}\".toString(), t.kind == 'mirror'," "            def r = pullAndScan(\"\${env.REGISTRY}/\${dst}\".toString(), true,"; }

# a repo that could not be cloned is scanned anyway
red_5() { _sub "$W269" '            if (t.unreadable) {' '            if (false) {'; }

# the books send an app's finding upstream
red_6() { _sub "$W269" "              ? \"the app: a build of \${t.slug} (its base is the loop's; its own dependencies are its repo's)\"" "              ? \"upstream\""; }

# a comment after the digest makes the line unreadable, and the app drops out of the books
red_7() { _sub "$W269" '                  /^[[:space:]]*digest:/ { d = $0; sub(/.*digest:[[:space:]]*/, "", d); sub(/[[:space:]].*/, "", d); next }' '                  /^[[:space:]]*digest:/ { d = $0; sub(/.*digest:[[:space:]]*/, "", d); next }'; }

# an overlay line the stage cannot read is skipped without a word
red_8() { _sub "$W269" '                echo "NOTICE: ${r.slug}: a line of its overlay'"'"'s images I cannot read as «name digest»: ${l.trim()} — that image is NOT watched"
' ''; }

# the series are gathered with a closure method this job never ran
red_9() { _sub "$W269" "            def series = []
            for (line in readFile('ledger.prom').split('\\n')) {
              if (line.trim()) { series << line.trim() }
            }
            LEDGER_METRICS = series" "            LEDGER_METRICS = readFile('ledger.prom').split('\\n').findAll { it.trim() }"; }

# the scan's file is found by List.indexOf again
red_10() { _sub "$W269" '                                "${n}.txt".toString())' '                                "${TARGETS.indexOf(t)}.txt".toString())'; }

# ── controls ──
control_1() { _sub "$W269" "echo 'apps: no contract in orgs/ names a repo — no tenant image runs on this instance'" "echo 'apps: no contract names a repo — nothing of a tenant runs here'"; }
