# teeth for check 154 (the restore leaves the organization working)
# generated on 2026-08-29 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
DATA="libexec/aegis-data"

# the real regression: the bucket half goes back to giving up
red_1() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '''            if p["tipo"] != "postgres":
                restore_bucket(p, tmp)
                continue'''
new = '''            if p["tipo"] != "postgres":
                print(f"  {yellow}!{reset} {p['bucket']}: restoring objects is "
                      f"not implemented yet; the bundle DOES have them")
                continue'''
assert t.count(old) == 1
open(p, "w").write(t.replace(old, new, 1))
PY
}

# the other real regression: the ALTER ROLE with the password in argv,
# which is what /proc/PID/cmdline publishes to anyone on the machine
red_2() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '''    r = kubectl(["exec", "-i", "-n", ns, pod, "--", "sh", "-c",
                 'psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1'],
                binary=True, stdin_data=sql.encode())'''
new = '''    r = kubectl(["exec", "-n", ns, pod, "--", "sh", "-c",
                 f'psql -U "$POSTGRES_USER" -d postgres -Atc '
                 f'"ALTER ROLE app WITH PASSWORD \\'{password}\\'"'])'''
assert t.count(old) == 1
open(p, "w").write(t.replace(old, new, 1))
PY
}

# and the quiet one: the restore stops realigning, which is the state
# that looked green while the organization could not log in
red_3() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '''                user = realign_role(p["ns"], pod, p["secreto"], app_db)'''
new = '''                user = "unchanged"'''
assert t.count(old) == 1
open(p, "w").write(t.replace(old, new, 1))
PY
}

# the measurement, out of the convention: a series without the aegis_
# prefix is one that no dashboard and no rule of this platform finds
red_4() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'aegis_org_bucket_bytes{{org="'
new = 'org_bucket_bytes{{org="'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, new, 1))
PY
}

# the blocker of the review of 2026-08-29: the headers flattened into a
# plain dict. Garage answers `content-length:` in lowercase, so the size
# read back is -1 for EVERY object and the restore, having uploaded the
# whole bucket, declares itself failed.
red_5() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "            return r.status, r.read(), r.headers"
new = "            return r.status, r.read(), dict(r.headers)"
assert t.count(old) == 1
open(p, "w").write(t.replace(old, new, 1))
PY
}

# control: a comment may name the credential
control_1() {
    printf '\n# The word password appears here on purpose: a comment explains,\n# it does not execute.\n' \
        >> "$AEGIS_ROOT/$DATA"
}

# control: and a DOCSTRING may narrate the hole that was closed. This is
# the distinction the check is built on — if it bit here, the file could
# no longer tell its own history.
control_2() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '''"""aegis-data — captures and restores the tenants' DATA.
'''
new = '''"""aegis-data — captures and restores the tenants' DATA.

Until 2026-08-27 restoring the objects of the bucket was not implemented
and the role was realigned by hand; both holes are closed below.
'''
assert t.count(old) == 1
open(p, "w").write(t.replace(old, new, 1))
PY
}
