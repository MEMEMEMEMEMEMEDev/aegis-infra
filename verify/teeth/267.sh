# teeth of check 267 — the watch keeps the books.
L267="$AEGIS_ROOT/seed/platform/image-watch/ledger.sh"
W267="$AEGIS_ROOT/seed/platform/image-watch/Jenkinsfile"
S267="$AEGIS_ROOT/lib/aegis/seed.py"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# an image the watch could not scan drops out of the books (absent reads as clean)
red_1() { _sub "$L267" "        printf 'unmeasured|%s|%s|%s||||||the watch could not scan it this morning||||%s\\n' \\
            \"\$img\" \"\$kind\" \"\$dig\" \"\$fixer\" >> \"\$WORK/body\"
        continue" "        continue"; }

# an image scanned clean is not written down
red_2() { _sub "$L267" "        printf 'clean|%s|%s|%s||||||||||%s\\n' \"\$img\" \"\$kind\" \"\$dig\" \"\$fixer\" >> \"\$WORK/body\"
" ""; }

# yesterday's first-seen day is not read: a dateless finding's window restarts every morning
red_3() { _sub "$L267" '$6 = (k in F) ? F[k] : today' '$6 = today'; }

# a stale exploited list is not said
red_4() { _sub "$L267" '    if (why != "") print "unmeasured|exploited-list|kev||||||" why' '    if (0) print "unmeasured|exploited-list|kev||||||" why'; }

# the series have no explicit zeros for a clean image
red_5() { _sub "$L267" '            for (j = 1; j <= 4; j++) printf' '            for (j = 1; j <= 4; j++) if (C[ORDER[i] "|" st[j]] > 0) printf'; }

# the publish guard is gone: whatever the clone holds is committed
red_6() { _sub "$W267" '              if git diff --cached --name-only | grep -vxF -e image-watch/ledger.txt -e "${KEV_REL}" | grep -q .; then' '              if false; then'; }

# the exploited list is fetched but never published: the tenants keep the seed's
red_7() { _sub "$W267" '              cp "${WORKSPACE}/${KEV_REL}" "${SCRATCH}/${KEV_REL}"
' ''; }

# a short download replaces the list
red_8() { _sub "$W267" '              elif [ "$NEW" -lt $(( OLD * 9 / 10 )) ]; then' '              elif false; then'; }

# the seed takes the instance's exploited list back on every apply
red_9() { _sub "$S267" '    "k8s/base/platform/vuln-policy/kev.txt", "image-watch/ledger.txt",' '    "image-watch/ledger.txt",'; }

# ── controls ──
control_1() { _sub "$L267" 'the watch could not scan it this morning' 'the watch could not look at it this morning'; }
control_2() { _sub "$W267" "echo 'publish: no ledger this morning — nothing is committed'" "echo 'publish: no books this morning — nothing is committed'"; }
