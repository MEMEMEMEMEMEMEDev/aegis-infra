# teeth for check 154 (the restore leaves the organization working)
# generated on 2026-08-29 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
DATA="libexec/aegis-data"

# the real regression: the bucket half goes back to giving up
red_1() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '''            for p in buckets:
                restore_bucket(p, tmp)'''
new = '''            for p in buckets:
                print(f"  {yellow}!{reset} {p['bucket']}: restoring objects is "
                      f"not implemented yet; the bundle DOES have them")'''
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

# the first of the two orders of the review of 2026-08-29: the sha256
# goes back INSIDE the write loop, so object N's mismatch dies with
# objects 1..N-1 already uploaded — half a restore, silent
red_6() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
start = t.index("    # THE WHOLE PAYLOAD AGAINST")
end = t.index("    ak, sk = s3_credential(ns)", start)
t = t[:start] + t[end:]
old = '            data = open(os.path.join(payload, p["directorio"],\n'
old += '                                     o["archivo"]), "rb").read()\n'
new = old + '            if hashlib.sha256(data).hexdigest() != o["sha256"]:\n'
new += '                die("it does not match its sha256 from the manifest")\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, new, 1))
PY
}

# the second: the objects leave the window with the consumers down and
# go back to travelling with the application already serving
red_7() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
inside = '            for p in buckets:\n                restore_bucket(p, tmp)\n'
assert t.count(inside) == 1
t = t.replace(inside, "", 1)
after = '        finally:\n            scale_consumers_up(ns, consumers)\n'
assert t.count(after) == 1
t = t.replace(after, after + '\n        for p in buckets:\n            restore_bucket(p, tmp)\n', 1)
open(p, "w").write(t)
PY
}

# the mutation that emptied the check without turning it red: somebody
# simplifies the exec and takes the loopback out. Over the unix socket
# the pg_hba of the image trusts the connection, so the proof that the
# credential opens the database passes with ANY password
red_8() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'exec psql -h 127.0.0.1 -U '
new = 'exec psql -U '
assert t.count(old) == 1
open(p, "w").write(t.replace(old, new, 1))
PY
}

# the silent repair: the credential decoded with errors=replace. Each
# invalid byte becomes U+FFFD, the ALTER ROLE installs the mutilated
# string and the proof compares it against itself — green, and the
# application, which gets the raw bytes, stays out
red_9() {
    python3 - "$AEGIS_ROOT/$DATA" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '''    try:
        user = user.decode().strip()
        password = password.decode()
    except UnicodeDecodeError:'''
new = '''    user = user.decode(errors="replace").strip()
    password = password.decode(errors="replace")
    if False:'''
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
