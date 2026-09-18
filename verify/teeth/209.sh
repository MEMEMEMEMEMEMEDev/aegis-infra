# teeth for 209 — the round must READ the probes. Each red takes one
# half of the reading away, which is how it looked before 2026-09-18.
C209="$AEGIS_ROOT/libexec/aegis-check"

# back to counting: the probes exist and nobody reads them
red_1() { python3 - "$C209" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index('  if [[ -n "$probes" && "$probes" -gt 0 ]]; then')
j = s.index('\n  fi\n', s.index('ok "the $probes public site(s) answer their probe"'))
p.write_text(s[:i] + s[j + len('\n  fi\n'):])
P
}

# the status code stops being read: a login redirect and a dead site
# become the same answer
red_2() { sed -i 's/probe_http_status_code{job=~"sitio-\.\*"} >= 300 < 400/probe_success{job=~"sitio-.*"} == 2/g' "$C209"; }

# a site that is down becomes a note: nobody is woken, nothing is red
red_3() { python3 - "$C209" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '          bad "$down of the $probes public site(s) do not answer: no reply, or an error"'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '          notice "$down of the $probes public site(s) do not answer: no reply, or an error"', 1))
P
}

# ── controls ──
# rewording the sentence changes no measurement
control_1() { sed -i 's/do not answer: no reply, or an error/give no reply, or an error/' "$C209"; }
# a comment about the probes is not a read
control_2() { printf '\n# note: the probe walks the whole path; that is why the window accepts on it.\n' >> "$C209"; }
# one more note beside the verdict
control_3() { python3 - "$C209" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '          ok "the $probes public site(s) answer their probe"'
assert s.count(old) == 1
p.write_text(s.replace(old, '          ok "the $probes public site(s) answer their probe"\n          note "measured by the blackbox module sitio_publico"', 1))
P
}
