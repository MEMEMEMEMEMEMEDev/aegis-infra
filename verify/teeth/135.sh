# teeth for check 135 (every mirrored image carries repo, tag and digest)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# 2026-08-27: the tag moved from a comment into the reference so that
# image-watch could ask, by machine, whether upstream moved. Each red
# below is one of the three ways the list can go quietly wrong.
IMG="seed/platform/mirror-images/images.txt"

# the tag falls out of one line: the pull still works, and image-watch
# reports «upstream did not move» about an image it never asked about
red_1() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^(public\.ecr\.aws/docker/library/redis):[^@\s]+@", r"\1@", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# the digest falls out: the source becomes a mutable pointer
red_2() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^(public\.ecr\.aws/docker/library/redis:[^@\s]+)@sha256:[0-9a-f]{64}", r"\1", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# a third column: the parser of every instance reads two fields and
# the third one lands inside the destination
red_3() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^(public\.ecr\.aws/docker/library/redis:\S+\s+\S+)$", r"\1\tredis-latest", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# control: a comment explaining an entry is not an entry
control_1() { printf '# legitimate comment: why this image is here\n' >> "$AEGIS_ROOT/$IMG"; }
# control: the order of the list carries no meaning
control_2() {
    python3 - "$AEGIS_ROOT/$IMG" <<'PY'
import sys
p = sys.argv[1]; lines = open(p).read().split("\n")
idx = [i for i, l in enumerate(lines) if l.strip() and not l.lstrip().startswith("#")]
assert len(idx) >= 2
a, b = idx[0], idx[1]
lines[a], lines[b] = lines[b], lines[a]
open(p, "w").write("\n".join(lines))
PY
}
