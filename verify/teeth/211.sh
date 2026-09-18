# teeth for 211 — a binary of the host must not be able to arrive
# unproved. Each red is a way the phase looked before 2026-09-18.
P211="$AEGIS_ROOT/init/phases/05-host.sh"
G211="$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"

# helm goes back to `curl | bash` of a script off a moving branch
red_1() { python3 - "$P211" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index('        helm)')
j = s.index(';;', i) + 2
p.write_text(s[:i] + '''        helm)
            run_cmd retry_net 3 bash -c "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=v${pin} bash" ;;''' + s[j:])
P
}

# kubectl is downloaded and installed with nothing comparing its bytes.
# Aimed at the fetch_verified CALL and not at `kubectl)`: the phase has
# two case branches with that label —tool_version has one too— and a
# tooth that mutates the wrong one mutates nothing the check reads.
red_2() { python3 - "$P211" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            fetch_verified \\
                "https://dl.k8s.io/release/v${pin}/bin/linux/amd64/kubectl" \\
                /tmp/kubectl \\
                "https://dl.k8s.io/release/v${pin}/bin/linux/amd64/kubectl.sha256" \\
                kubectl'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            run_cmd retry_net 3 curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/v${pin}/bin/linux/amd64/kubectl"''', 1))
P
}

# the checksum is compared and the mismatch is a warning: protection
# that reads as protection and is not
red_3() { python3 - "$P211" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        die "CHECKSUM MISMATCH on $name'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        log_warn "CHECKSUM MISMATCH on $name''', 1))
P
}

# a tool goes back to carrying a number nobody delivers: apt installs
# the distribution's line and the pin is a promise
red_4() { sed -i 's/^  age: "apt".*/  age: "1.2.1"/' "$G211"; }

# the catch-all branch goes away: a tool nobody wrote a case for is
# silently not installed
red_5() { python3 - "$P211" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index('        *)\n            # Everything else is the distribution')
j = s.index(';;', i) + 2
p.write_text(s[:i] + s[j:])
P
}

# ── controls ──
# a COMMENT that spells the forbidden pattern out is prose, not code
control_1() { printf '\n# note: nothing here pipes `curl -fsSL https://example/x | bash` into a shell.\n' >> "$P211"; }
# the message a verified download prints changes; the verification does not
control_2() { sed -i 's/verified against the sha256 its publisher publishes/checked against the sha256 its publisher signs off on/' "$P211"; }
# a sixth tool with its own verified branch is one more of the same
control_3() { python3 - "$P211" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        cosign)'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''        yq)
            fetch_verified \\
                "$GH_REL/mikefarah/yq/releases/download/v${pin}/yq_linux_amd64" \\
                /tmp/yq \\
                "$GH_REL/mikefarah/yq/releases/download/v${pin}/checksums" \\
                yq_linux_amd64
            run_cmd sudo install -m755 /tmp/yq /usr/local/bin/yq
            rm -f /tmp/yq ;;
        cosign)''', 1))
P
}
