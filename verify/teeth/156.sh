# teeth for check 156 (a type with state answers for its own backup, and
# the platform can serve it)
#
# The mutations are the ways this really breaks, in the order the
# mechanism runs: a type written without a backup, the two crossings of
# `disco` and the dump, a label that stops agreeing with the promise, a
# credential slipped into argv, a generator that stops refusing an
# unmeasured image, a rule taken out of the catalogue reader, and the
# three derivations —the Secret, the NetworkPolicy, the resource table—
# that make a declared type into a deployed one. Each was applied over a
# copy of the tree and the check went red; both controls stayed green.
CAT="seed/platform/services.yaml"
ORG="lib/aegis/org.py"

# THE REGRESSION THIS CHECK EXISTS FOR: a fourth type with state,
# written the way the first three were written before today — an image,
# a port, a disk — and not one word about who ever captures it. It
# deploys, it holds the organization's data, and no backup goes near it.
red_1() {
    python3 - "$AEGIS_ROOT/$CAT" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
m = re.search(r"(?m)^  redis:\n", t)
assert m, "services.yaml has no `redis:` type where this tooth expects it"
new = ("  clickhouse:\n"
       "    imagen: clickhouse\n"
       "    digest: sha256:" + "0" * 64 + "\n"
       "    tag_origen: \"25.3\"\n"
       "    puerto: 9000\n"
       "    disco: 5Gi\n"
       "    uid: 101\n"
       "    gid: 101\n"
       "    component: datos\n")
open(p, "w", encoding="utf-8").write(t[:m.start()] + new + t[m.start():])
PY
}

# The first crossing: the cache grows a disk while still declaring it is
# not backed up. That volume would be the one thing in the namespace
# that survives a restart and that nobody captures.
red_2() {
    python3 - "$AEGIS_ROOT/$CAT" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "    uid: 999 # measured in the image's config: adduser -u 999 redis\n"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, "    disco: 1Gi\n" + old, 1))
PY
}

# The second: the document database declares it is not backed up, with a
# reason that reads fine, and keeps its volume. The catalogue now
# promises exactly the opposite of what it did this morning and the
# manifests do not change by a byte.
red_3() {
    python3 - "$AEGIS_ROOT/$CAT" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "    backup:\n      method: dump\n      # ONE ARCHIVE PER DATABASE"
assert t.count(old) == 1
new = ("    backup:\n"
       "      method: none\n"
       "      reason: |\n"
       "        it is only used for a cache of rendered documents, so there is\n"
       "        nothing here that is not somewhere else as well\n"
       "      # ONE ARCHIVE PER DATABASE")
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The label stops agreeing with the promise. The type is still dumped
# and is no longer labelled `datos`, which is the label whatever
# captures it selects by: a backup that will never come looking, and a
# catalogue that says it will.
red_4() {
    python3 - "$AEGIS_ROOT/$CAT" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
# the mongodb one, which is the second `component: datos` in the file
ms = [m for m in re.finditer(r"(?m)^    component: datos$", t)]
assert len(ms) == 2, f"expected two `component: datos`, found {len(ms)}"
m = ms[1]
open(p, "w", encoding="utf-8").write(
    t[:m.start()] + "    component: cache" + t[m.end():])
PY
}

# The credential moves into argv. It is the flag every tutorial uses and
# the one /proc/<pid>/cmdline publishes to everything else in the pod —
# the same regression check 154 caught inside the restore.
red_5() {
    python3 - "$AEGIS_ROOT/$CAT" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '''          mongodump --username="$(cat /etc/aegis/credential/usuario)" \\
                    --authenticationDatabase=admin \\
                    --config=/tmp/aegis-dump.yaml \\'''
new = '''          mongodump --username="$(cat /etc/aegis/credential/usuario)" \\
                    --authenticationDatabase=admin \\
                    --password="$(cat /etc/aegis/credential/password)" \\'''
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The generator stops refusing an image nobody measured and falls back
# to the tag. The manifest reads correctly, Kyverno appends the digest
# on admission, desired != live forever — and if the tag was never
# mirrored at all, an ImagePullBackOff that looks like a cluster
# problem.
red_6() {
    python3 - "$AEGIS_ROOT/$ORG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '''    if block.get("digest"):
        return f"{cat['registro']}/{block['imagen']}@{block['digest']}"
'''
new = old + '''    return f"{cat['registro']}/{block['imagen']}:{block['tag_origen']}"
'''
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The catalogue reader stops demanding a backup. Nothing in the seed
# breaks —the three types still declare theirs— and the rule is gone:
# the next type written without one goes in clean. This is the mutation
# that would leave a check built only out of `provided_type` green,
# which is why 156 builds its own counter-examples.
red_7() {
    python3 - "$AEGIS_ROOT/$ORG" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '    backup = block.get("backup")\n    if not isinstance(backup, dict):\n'
assert t.count(old) == 1
new = ('    backup = block.get("backup")\n'
       '    if not isinstance(backup, dict):\n'
       '        return block\n'
       '    if False:\n')
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# And it stops demanding that the two halves agree: a dumped type with
# nothing to dump from, and an unbacked-up type with a volume, both go
# through.
red_8() {
    python3 - "$AEGIS_ROOT/$ORG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '        if block.get("disco") is None:\n'
assert t.count(old) == 1
t = t.replace(old, '        if False:\n', 1)
old2 = '        if block.get("disco") is not None:\n'
assert t.count(old2) == 1
open(p, "w", encoding="utf-8").write(t.replace(old2, '        if False:\n', 1))
PY
}

# The cache renders a volume the catalogue never gave it. Same hole as
# red_2 and from the other side: the file says «no disk» and the
# manifest creates one, so what is deployed is not what was declared and
# the thing that survives is the thing nobody captures.
red_9() {
    python3 - "$AEGIS_ROOT/$ORG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '''        - name: datos
          emptyDir: {{}}"""])'''
new = '''        - name: datos
          emptyDir: {{}}
  volumeClaimTemplates:
    - apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: datos
      spec:
        accessModes: [ReadWriteOnce]
        volumeMode: Filesystem
        resources:
          requests: {{storage: 1Gi}}"""])'''
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The Secret goes back to being a postgres thing. The cache and the
# document database render a `secretKeyRef` to a Secret the
# secret-generator never lists: the pod waits forever for something
# nobody creates, and the event says «secret not found» about a name
# that is in the manifest.
red_10() {
    python3 - "$AEGIS_ROOT/$ORG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = 'for b in sorted(x["nombre"] for x in c["servicios"] if x["tipo"] in PROVIDED):'
new = 'for b in sorted(x["nombre"] for x in c["servicios"] if x["tipo"] == "postgres"):'
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The NetworkPolicy goes back to the two constants it had when postgres
# was the only provided type. `usa: [redis]` now writes a rule that
# opens 5432 towards the pods labelled `datos`: the traffic that was
# declared is blocked and traffic nobody declared is allowed.
red_11() {
    python3 - "$AEGIS_ROOT/$ORG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '                pt = provided_type(cat, u)\n'
new = '                pt = {"component": "datos", "puerto": 5432}\n'
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The cache falls out of the table that decides who the platform
# provides. The contract still names `redis` —TYPES has it— and from
# there on it is treated as something the tenant BUILDS: a `repo` is
# demanded of it, its resources are charged as a `tamano` word, and
# nothing renders it.
red_12() {
    python3 - "$AEGIS_ROOT/$ORG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '''    "redis": {"requests.cpu": "50m", "requests.memory": "64Mi",
              "limits.cpu": "500m", "limits.memory": "512Mi"},
'''
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, "", 1))
PY
}

# control: a comment is not a type, and a catalogue that explains itself
# is the point of the file
control_1() {
    printf '\n# A note about how these three were chosen, and about the fourth\n# that has not been needed yet.\n' \
        >> "$AEGIS_ROOT/$CAT"
}

# control: MEASURING THE DIGEST is exactly the edit this whole shape
# exists to make possible — the operator runs the two commands the
# refusal printed and replaces the `pending:` block with the number the
# registry answered. If the check bit here, the type could never
# graduate and the refusal would be a wall instead of a door.
control_2() {
    python3 - "$AEGIS_ROOT/$CAT" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
# (?m) and NOT (?ms): with DOTALL the `.` of `.*` crosses newlines,
# the greedy match runs to the end of the file, and this control ate
# the whole catalogue — which the check reported, correctly, as a
# tree that no longer holds together. A tooth that mutates more than
# it means to measures something else.
m = re.search(r"(?m)^    pending:\n(?:^      .*\n)+", t)
assert m, "no `pending:` block where this control expects one"
open(p, "w", encoding="utf-8").write(
    t[:m.start()] + "    digest: sha256:" + "9f" * 32 + "\n" + t[m.end():])
PY
}
