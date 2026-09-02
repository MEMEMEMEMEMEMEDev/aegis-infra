# teeth of check 176 — the pruner is dry by default, and what the
# instance pins is never a candidate.
#
# The mutations are not cosmetic: each one is a state in which
# `aegis image gc` would delete something that is in use, or delete
# without being asked. The controls are the two shapes that made eight
# checks accuse the wrong thing in one day — a comment that quotes the
# forbidden code, and a message reworded.
IMG="libexec/aegis-image"

# THE ONE THAT MATTERS. The deleter stops consulting the plan, so it
# will delete whatever it is handed: the digest a manifest of the
# instance fixes, the image of a tenant pod that is serving traffic,
# the destination images.txt promises is mirrored. A prune that deletes
# what is running is worse than no prune at all.
red_1() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '''    gc_planned_prune "$repo" "$dig" \\
'''
assert t.count(old) == 1
a = t.index(old)
b = t.index('    code="$(retry_net 3 curl -sS --max-time 60 \\\n        --netrc-file "$SECRETS_TMP/registry.netrc" --cacert "$SECRETS_TMP/aegis-ca.crt" \\\n        -o /dev/null -w', a)
open(p, "w", encoding="utf-8").write(t[:a] + t[b:])
PY
}

# The other half of the same guard: the deleter stops asking whether
# this run was ever told to act. Typing the verb to see what it would
# do would then delete.
red_2() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '''    (( GC_ACT == 1 )) \\
        || { log_error "refusing to delete $repo@$dig: nobody asked this run to act — it is a dry run"; return 1; }
'''
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, "", 1))
PY
}

# The default flips. Every caller that never asked for anything gets a
# delete, and there is no way back from one.
red_3() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "\nGC_ACT=0\n"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, "\nGC_ACT=1\n", 1))
PY
}

# Something other than a person moves the flag: an environment variable
# reaches in and turns «explain the plan» into «delete it» for anybody
# who happens to have it exported.
red_4() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "\nGC_ACT=0\n"
assert t.count(old) == 1
new = '\nGC_ACT=0\n[[ "${AEGIS_IMAGE_GC_YES:-0}" == 1 ]] && GC_ACT=1\n'
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# THE SOURCE ONLY THE CLUSTER CAN ANSWER FOR. The tenants' overlays
# live in the organisations' repositories, not on this disk: with this
# question gone, the image of every app that is serving traffic becomes
# a candidate the moment two newer builds exist.
red_5() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
a = t.index('    local live\n    live="$(kubectl get pods,deployments')
b = t.index('    sort -u -o "$out" "$out"')
open(p, "w", encoding="utf-8").write(t[:a] + t[b:])
PY
}

# The instance's own manifests stop being read: what this platform
# fixes by digest —which is in use however old its tag is— stops being
# protected.
red_6() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '    gc_scan_manifests "$PLATFORM_DIR" >> "$out" \\\n'
assert t.count(old) == 1
a = t.index(old)
b = t.index('    # (2) WHAT images.txt DECLARES.', a)
open(p, "w", encoding="utf-8").write(t[:a] + t[b:])
PY
}

# The scan is allowed to fail quietly. It is the shape check 166 was
# born from: the scanner prints nothing, the protected set comes out
# empty, and an empty protected set means every image in the registry
# is a candidate.
red_7() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '''    gc_scan_manifests "$PLATFORM_DIR" >> "$out" \\
        || die "the scan of $PLATFORM_DIR for pinned digests failed: nothing was planned and nothing was deleted — a prune that cannot read what the instance fixes is a prune that deletes what is running"
'''
assert t.count(old) == 1
new = '    gc_scan_manifests "$PLATFORM_DIR" >> "$out" || true\n'
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The planner stops subtracting the protected set: it would rank images
# by age and nothing else, and the oldest image of a repository is very
# often exactly the one a manifest pins.
red_8() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '''    python3 - "$SECRETS_TMP/gc-inventory.tsv" "$SECRETS_TMP/gc-protected.tsv" "$KEEP" "$GC_PLAN" <<'PY'
'''
assert t.count(old) == 1
new = '''    python3 - "$SECRETS_TMP/gc-inventory.tsv" "$SECRETS_TMP/inventario.tsv" "$KEEP" "$GC_PLAN" <<'PY'
'''
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The plan is computed before the protected set exists. The file it
# subtracts is not there yet, so it subtracts nothing — green, and
# every pin unprotected.
red_9() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '''    gc_pins
    gc_inventory
    gc_plan || die "the plan could not be computed: nothing was deleted"
'''
assert t.count(old) == 1
new = '''    gc_inventory
    gc_plan || die "the plan could not be computed: nothing was deleted"
    gc_pins
'''
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The signatures stop travelling with the manifest they sign. cosign
# stores them as TAGS, so --delete-untagged marks them live: the prune
# then frees less than it says it did and leaves a signature of an
# image that is gone.
red_10() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '            elif verdicts.get(parent) == "KEEP":\n'
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, '            elif True:\n', 1))
PY
}

# A second place that deletes. It is how the guards come undone without
# anybody removing one: the new call site is written without them, and
# it is the copy nobody notices.
red_11() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "do_gc() {\n"
assert t.count(old) == 1
new = '''gc_drop() {
    curl -sS --netrc-file "$SECRETS_TMP/registry.netrc" --cacert "$SECRETS_TMP/aegis-ca.crt" \\
        -X DELETE "https://$REGISTRY_CLUSTER_IP:5000/v2/$1/manifests/$2"
}

do_gc() {
'''
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# The verb disappears from the dispatch: `aegis image gc` is accepted
# and then does nothing at all, which is the quietest of the three ways
# to be missing.
red_12() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "    gc)      do_gc ;;\n"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, "", 1))
PY
}

# The retention default moves in the code and not in the protocol. The
# operator plans a prune against the number they read and the command
# acts on another one; with a repository that costs 5.6 GB per build,
# that difference is measured in tens of gigabytes.
red_13() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "\nGC_KEEP_DEFAULT=2\n"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, "\nGC_KEEP_DEFAULT=8\n", 1))
PY
}

# ── controls ─────────────────────────────────────────────────────────
# THE PROSE THAT NAMES THE FORBIDDEN SHAPES. This file argues every
# decision beside the code that makes it, so the paragraph above the
# deleter quotes `GC_ACT=1`, the DELETE and the guard it refuses to go
# without. Eight checks accused exactly that paragraph in one day; this
# control is the reason the scan strips comments before it reads.
control_1() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "reg_delete_manifest() {   # <repo> <digest>\n"
assert t.count(old) == 1
new = ("# note: never a second function with -X DELETE in it, and never a\n"
       "# GC_ACT=1 that any environment variable can reach. The guard on\n"
       "# gc_planned_prune stays inside this function, not at its callers.\n"
       + old)
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# control: the same trap one language down. The comment goes INSIDE the
# planner's python and quotes the very expression the check looks for.
control_2() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "rows, kept, pruned, freeable = [], 0, 0, 0\n"
assert t.count(old) == 1
new = ("# a companion is decided by verdicts.get(parent) == \"KEEP\" and by\n"
       "# nothing else: not by prot_digest, not by prot_tag, not by its age.\n"
       + old)
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# control: the wording of a refusal is prose. Rewriting it changes
# nothing about what is refused.
control_3() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = 'nobody asked this run to act — it is a dry run'
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, 'this run was never told to act; it only explains', 1))
PY
}

# control: a FOURTH source of protection. More things that may not be
# deleted is more discipline, not less, and the check must not read it
# as a change of shape.
control_4() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = '    sort -u -o "$out" "$out"\n'
assert t.count(old) == 1
new = ('    while IFS= read -r _f; do\n'
       '        printf \'tag\\t%s\\t%s\\tnamed by a Containerfile of the seed\\n\' "${_f%%:*}" "${_f#*:}" >> "$out"\n'
       '    done < <(grep -rhoE "aegis-base-[a-z]+:[0-9.]+-[0-9]+" "$PLATFORM_DIR" 2>/dev/null | sort -u)\n'
       + old)
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

# control: a new flag on the verb. Growing the surface of the command
# is not the same as loosening what it refuses.
control_5() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "            --dry-run)  shift ;;\n"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, old + "            --quiet)    shift ;;\n", 1))
PY
}

# control: the protocol gains a paragraph about the number without
# changing it. Documentation is not drift.
control_6() {
    python3 - "$AEGIS_ROOT/seed/platform/docs/protocols/images.md" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "**Default `--keep`:** 2\n"
assert t.count(old) == 1
new = old + "\nMeasured against the reference instance on 2026-09-01, where the two\nrebuilds of the engine that started all this occupied 11.2 GB.\n"
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}
