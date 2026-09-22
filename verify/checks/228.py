"""Check 228 — a server image is not a desktop.

2026-09-22, the first Vultr VM of the lab: Ubuntu 26.04 boots into
`graphical.target` with no display manager installed, and the probe
behind `aegis host` said a human shares the machine. aegis would have
reserved memory for a desktop that does not exist, on a 15 GB node.

Driven, not read: `probe_shared_with_a_human` is loaded from
libexec/aegis-host and run against a fake `systemctl` and `loginctl`
that answer five machine shapes.
"""
import importlib.machinery
import importlib.util
import os
import stat
import sys
import tempfile

ROOT = sys.argv[1]
HOST = os.path.join(ROOT, "libexec", "aegis-host")
findings = []
driven = 0

sys.path.insert(0, os.path.join(ROOT, "lib"))
loader = importlib.machinery.SourceFileLoader("aegis_host_228", HOST)
spec = importlib.util.spec_from_loader("aegis_host_228", loader)
mod = importlib.util.module_from_spec(spec)
try:
    loader.exec_module(mod)
    probe = mod.probe_shared_with_a_human
except Exception as e:   # noqa: BLE001 — a probe that cannot load was never measured
    print(f"libexec/aegis-host could not be loaded to drive the probe: {e}")
    sys.exit(0)

# (name, graphical.target state, display-manager LoadState, seated local session?, expected)
SHAPES = [
    ("cloud server image (graphical.target, no display manager)", "active", "not-found", False, False),
    ("desktop with nobody logged in (display manager waiting)", "active", "loaded", False, True),
    ("desktop with somebody at the seat", "active", "loaded", True, True),
    ("headless server (multi-user.target)", "inactive", "not-found", False, False),
    ("graphical.target, display manager unreadable", "active", "", False, True),
]

for name, gstate, dm, seated, want in SHAPES:
    with tempfile.TemporaryDirectory() as td:
        sysctl = os.path.join(td, "systemctl")
        with open(sysctl, "w") as f:
            f.write("#!/bin/sh\n"
                    f'case "$*" in\n'
                    f'  "is-active graphical.target") echo "{gstate}" ;;\n'
                    f'  *display-manager.service*) ' + (f'echo "LoadState={dm}"' if dm else "exit 1") + " ;;\n"
                    "  *) exit 1 ;;\n"
                    "esac\n")
        login = os.path.join(td, "loginctl")
        with open(login, "w") as f:
            f.write("#!/bin/sh\n"
                    'case "$1" in\n'
                    '  list-sessions) echo "7 1000 someone - 999 user - no -" ;;\n'
                    '  show-session) ' + ('printf "Seat=seat0\\nRemote=no\\nType=wayland\\n"' if seated
                                          else 'printf "Seat=\\nRemote=yes\\nType=tty\\n"') + " ;;\n"
                    "esac\n")
        for x in (sysctl, login):
            os.chmod(x, stat.S_IRWXU)
        old = os.environ.get("PATH", "")
        os.environ["PATH"] = td + ":" + old
        try:
            got, evidence = probe()
        finally:
            os.environ["PATH"] = old
        driven += 1
        if got != want:
            findings.append(f"{name}: the probe answered shared={got}, expected {want} "
                            f"(evidence: {'; '.join(evidence)})"
                            + (": memory would be reserved for a desktop that does not exist"
                               if want is False else
                               ": a real desktop would be left without its floor"))

for f in findings:
    print(f)
print(f"SCOPE: the probe driven against {driven} machine shapes with a fake systemctl and loginctl")
