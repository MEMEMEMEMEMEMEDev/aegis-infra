# title: every AI image the kustomization pins has a producer named in the artifact
# origin: new in v3 — measured on 2026-08-31: three rows pinned, two with nobody to build them
check() {
# The kustomization of ai-system pins three images by digest. Nothing
# asked, until this check, WHO produces each of them — and on
# 2026-08-31 the honest answer for two of them was «nobody»:
# `aegis-engine-cpu` had a manifest claiming its source was in the
# artifact and the directory did not exist, and `aegis-ai-vllm` had a
# build definition no job could fire. A row pinned with no producer is
# a promise the instance discovers it cannot keep at the exact moment
# it tries.
#
# THREE legitimate kinds of producer, and the third is the interesting
# one:
#
#   1. BUILT HERE — a `ai/<x>/Jenkinsfile` of the seed whose `IMAGE`
#      is that name. The link is the Jenkinsfile's own variable and not
#      a table here: the pipeline already has to be right about which
#      image it pushes.
#   2. MIRRORED — a destination row in mirror-images/images.txt.
#   3. PROVIDED BY THE INSTANCE — the image comes from a repository
#      that is NOT part of this artifact, and the artifact says so
#      properly: a config placeholder that names the repository (so
#      there is somewhere to put the answer) AND a job-dsl item that
#      builds it (so the answer is used). That is the gateway's case,
#      and it is a legitimate answer rather than a hole — but only when
#      both halves are there. A placeholder with no job is a question
#      nobody acts on; a job with no placeholder is a job pointing
#      nowhere.
#
# What is NOT accepted is a fourth kind: a row that is pinned and
# whose producer is nowhere. That is the state this check was written
# out of.
KUST="$SEED/platform/k8s/base/ai-system/kustomization.yaml"
[[ -f "$KUST" ]] || { fail "the ai-system kustomization is not there: $KUST"; return; }

OUT="$(python3 - "$SEED/platform" "$KUST" "$AEGIS_ROOT/lib/common.sh" <<'PY'
import re, sys, pathlib, yaml
root, kust, common = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])

try:
    rows = [i.get("name", "").rsplit("/", 1)[-1]
            for i in (yaml.safe_load(open(kust, encoding="utf-8")) or {}).get("images") or []]
except Exception as e:
    print(f"FAILthe kustomization could not be read ({e!r})")
    raise SystemExit
rows = [r for r in rows if r]
if not rows:
    print("FAILthe kustomization pins no image at all: with no row, no producer "
          "could be missing, and that is a verdict about the reader")
    raise SystemExit

built = {}
for jf in sorted(root.glob("ai/*/Jenkinsfile")):
    m = re.search(r"^\s*IMAGE\s*=\s*'([^']+)'", jf.read_text(encoding="utf-8"), re.M)
    if m:
        built[m.group(1)] = str(jf.relative_to(root))

mirrored = set()
imgs = root / "mirror-images" / "images.txt"
if imgs.is_file():
    for l in imgs.read_text(encoding="utf-8").splitlines():
        l = l.strip()
        if l and not l.startswith("#") and len(l.split()) >= 2:
            mirrored.add(l.split()[1].split(":")[0])

# The instance-provided kind: the placeholders the config class owns,
# derived from lib/common.sh and never listed here.
placeholders = set()
for l in common.read_text(encoding="utf-8").splitlines():
    if l.startswith("_CONFIG_PLACEHOLDERS="):
        placeholders = set(re.findall(r"[A-Z][A-Z0-9_]+", l.split("=", 1)[1]))
        break

values = root / "k8s/base/platform/jenkins/values.yaml"
jobdsl = values.read_text(encoding="utf-8") if values.is_file() else ""

print("    %d row(s) pinned · %d built here · %d mirrored" % (len(rows), len(built), len(mirrored)))

for r in rows:
    if r in built or r in mirrored:
        continue
    # instance-provided: a placeholder that names this image's repo AND
    # a job-dsl item that consumes it.
    key = r.upper().replace("-", "_") + "_REPO"
    ph = f"__{key}__"
    # CONSUMED, not merely mentioned. The first version of this check
    # asked whether the placeholder appeared anywhere in the job-dsl,
    # and its own tooth caught it: a job that names it in a comment or
    # in a guard while pointing its repository somewhere else passed
    # green. What makes the instance-provided kind real is that the
    # answer is USED as the repository.
    used = re.search(r"(?:repository|url)\(\s*'[^']*" + re.escape(ph) + r"[^']*'",
                     jobdsl) is not None
    if key in placeholders and used:
        continue
    why = []
    if key not in placeholders:
        why.append(f"no config placeholder {ph} that names its repository")
    if not used:
        why.append(f"no job-dsl item that USES {ph} as a repository (mentioning it "
                   f"in a comment or a guard is not consuming it)")
    print("FAIL%s is pinned and has NO producer in the artifact: it is not built "
          "here (no ai/*/Jenkinsfile declares IMAGE = '%s'), it is not mirrored, and "
          "it is not provided by the instance either (%s)" % (r, r, "; ".join(why)))
PY
)" || { fail "the reading of the producers could not be completed"; return; }
printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "AI images pinned with no producer: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "every AI image the kustomization pins is built here, mirrored, or provided by the instance with both halves declared"
fi
}
