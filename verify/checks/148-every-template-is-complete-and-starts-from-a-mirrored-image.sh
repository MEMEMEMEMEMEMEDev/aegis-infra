# title: every template is complete, and every FROM resolves to a mirrored image
# origin: new in v3 — 2026-08-29, the day `base` was the only template and its two FROMs were docker.io
check() {
# seed/templates/<name>/ is the ONLY thing a new organization is handed:
# `aegis app new <org> --template <name>` writes it, the template
# evaporates (journeys/design.md §0.3) and from then on it is somebody's
# repo forever. Whatever is wrong in here is wrong in every app born
# from it, and nothing goes back to fix it.
#
# TWO PROPERTIES, and each one has a failure that is silent for a while:
#
# 1. THE FIVE PIECES. A template is a contract plus a repo skeleton, and
#    the skeleton is not complete until it can be built and deployed:
#      · contract.yaml.tpl  — without it `new --template` stops, but
#        only after resolving values, and the error blames the command;
#      · repos/<svc>/Containerfile — without it there is nothing to
#        build and the pipeline fails on a repo the operator just made;
#      · repos/<svc>/k8s/base/ + k8s/overlays/dev/ — the overlay is
#        where the pipeline WRITES the digest, so a skeleton with the ci
#        script and no overlay fails at the deploy stage with «I could
#        not find these images», which reads like a bug in the script;
#      · repos/<svc>/ci/ — the script that writes that digest;
#      · README.md — the one place that says what may be changed and
#        what may not. A template whose contract nobody explains gets
#        edited exactly where it must not be.
#
# 2. NO `FROM` OFF THE INTERNET. Until 2026-08-29 the `base` template
#    shipped `FROM docker.io/library/golang:1.26-alpine` and
#    `FROM docker.io/library/alpine:3.21`: an unmirrored, unscanned,
#    unsigned image, pinned by a MUTABLE TAG, entering the pipeline that
#    afterwards signs the result with the aegis key. It is the hole
#    mirror-images was built to close (its own header tells how the
#    canary was the last place it hid) — and the template was reopening
#    it for every organization that would ever be created.
#    So a template's FROM is one of two things: a placeholder resolved
#    at instantiation against the LIVE registry (which is the only party
#    that knows the internal digest — the mirror rewrites the manifest
#    as it copies, so images.txt's digest pulls nothing here), or an
#    already-pinned `@sha256:` reference. Never a bare tag.
#
# 3. THE PLACEHOLDER POINTS SOMEWHERE. Until 2026-08-29 property 2 was
#    all this asked, and it said PASS over six templates of which three
#    could not be instantiated at all: `__FROM_BASE_NGINX__` meant
#    `aegis-base-nginx:3.22`, a tag base-images does not publish and
#    never will (it tags `<minor>-<build number>`; «No floating tag,
#    ever»), and `__FROM_CI_NODE__` meant an image ci-images pushes
#    without signing, which is what the resolver refuses. A placeholder
#    that resolves to nothing is a FROM off the internet with a nicer
#    face: the pipeline fails either way, only later and with an error
#    about a manifest. So the placeholders are crossed against the table
#    that owns them (`_FROM_IMAGES` in libexec/aegis-app) and the table
#    against mirror-images/images.txt — and a row images.txt does not
#    declare yet is legal only if every template using it SAYS SO in its
#    README, naming the image. «It does not instantiate today» is a fact
#    the operator has to read before spending an afternoon on it, not
#    after.
#
# And the USER, which is one line and the difference between a pod that
# runs and a pod that is rejected at admission: tenant namespaces are
# PSS restricted, so the USER IN FORCE AT THE END OF THE FINAL STAGE has
# to be NUMERIC and not 0. The final stage, and not the last line of the
# file: until 2026-08-29 this read `grep USER | tail -1`, so a
# `USER 65532` in a BUILD stage with nothing in the runtime one
# satisfied it — while the image that actually runs is root and is
# rejected at admission. A USER does not survive a FROM: every stage
# starts at its own base image's user. `USER nginx` fails runAsNonRoot
# because the kubelet cannot read the image's /etc/passwd to prove the
# name is not root. Same clause check 138 asserts on the bases the
# platform owns, for the same reason, one level up.
T="$SEED/templates"
[[ -d "$T" ]] || { fail "$T does not exist: the template catalogue is gone and there is nothing to instantiate from"; return; }
D148=""
n_tpl=0 ; n_cf=0
for tpl in "$T"/*/; do
    [[ -d "$tpl" ]] || continue
    name="$(basename "$tpl")"
    n_tpl=$((n_tpl+1))
    [[ -f "$tpl/contract.yaml.tpl" ]] || D148="$D148 $name: no contract.yaml.tpl;"
    [[ -f "$tpl/README.md" ]] || D148="$D148 $name: no README.md (nothing says what may be changed and what may not);"
    if [[ ! -d "$tpl/repos" ]] || [[ -z "$(ls -A "$tpl/repos" 2>/dev/null)" ]]; then
        D148="$D148 $name: repos/ empty — a contract with no skeleton is half a template;"
        continue
    fi
    for svc in "$tpl"/repos/*/; do
        [[ -d "$svc" ]] || continue
        s="$name/$(basename "$svc")"
        cf="$svc/Containerfile"
        [[ -f "$cf" ]] || { D148="$D148 $s: no Containerfile;"; }
        [[ -d "$svc/k8s/base" ]] || D148="$D148 $s: no k8s/base/;"
        [[ -f "$svc/k8s/base/kustomization.yaml" ]] || D148="$D148 $s: k8s/base/ without a kustomization.yaml;"
        [[ -f "$svc/k8s/overlays/dev/kustomization.yaml" ]] \
            || D148="$D148 $s: no k8s/overlays/dev/kustomization.yaml — the pipeline has nowhere to write the digest;"
        [[ -n "$(ls -A "$svc/ci" 2>/dev/null)" ]] || D148="$D148 $s: ci/ empty (nothing writes the digest into the overlay);"
        [[ -f "$cf" ]] || continue
        n_cf=$((n_cf+1))
        # Comments are stripped FIRST: several of these Containerfiles
        # tell the story of the docker.io line they replaced, and a
        # check that bit its own documentation would teach people to
        # stop writing it (the class already paid for in checks 22, 66,
        # 71 and 104).
        code="$(joincont "$cf" | grep -vE '^[[:space:]]*#')"
        while IFS= read -r from; do
            [[ -z "$from" ]] && continue
            # legitimate: a __FROM_*__ placeholder, or an @sha256: pin.
            grep -qE '(__FROM_[A-Z0-9_]+__|@sha256:[0-9a-f]{64})' <<< "$from" && continue
            D148="$D148 $s: «$(echo "$from" | tr -s ' ')» is neither a __FROM_*__ placeholder nor pinned by @sha256: — an image by tag is a mutable pointer entering the pipeline that signs the result;"
        done <<< "$(grep -E '^[[:space:]]*FROM[[:space:]]' <<< "$code" || true)"
        # The USER IN FORCE at the end of the file: every FROM opens a
        # new stage and clears it, because a stage starts at its base
        # image's user and inherits nothing from the stage before it.
        last_user="$(awk '/^[[:space:]]*FROM[[:space:]]/{u=""} /^[[:space:]]*USER[[:space:]]/{u=$2} END{print u}' <<< "$code")"
        if [[ -z "$last_user" ]]; then
            D148="$D148 $s: the FINAL stage declares no USER: what runs is root, and PSS restricted rejects it at admission (a USER in an earlier stage does not carry over);"
        elif ! [[ "$last_user" =~ ^[1-9][0-9]*(:[0-9]+)?$ ]]; then
            D148="$D148 $s: the final stage's USER is '$last_user', and it has to be numeric and not 0: runAsNonRoot cannot be proven for a name (the kubelet does not read the image's /etc/passwd);"
        fi
    done
done
# A sweep that swept nothing is not a verdict: zero templates means
# `--template` has no catalogue, and this check stopped measuring.
(( n_tpl > 0 )) || D148="$D148 seed/templates/ has no template: the catalogue --template offers is empty;"
printf '    %s template(s) · %s Containerfile(s)\n' "$n_tpl" "$n_cf"
# ── property 3, in python: the table is a python dict and images.txt a
# two-column file, and reading both with `ast` and `awk` beats a grep
# that would go stale the first time either changes shape.
ROOT="$AEGIS_ROOT" python3 - <<'P3' || D148="$D148 (the placeholder/table detail is above);"
import ast, os, pathlib, re, sys

root = pathlib.Path(os.environ["ROOT"])
seed = root / "seed"
bad = []

src = (root / "libexec" / "aegis-app").read_text(errors="replace")
table = None
for node in ast.walk(ast.parse(src)):
    if (isinstance(node, ast.Assign) and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id == "_FROM_IMAGES"):
        table = ast.literal_eval(node.value)
if table is None:
    print("    libexec/aegis-app declares no _FROM_IMAGES: the placeholders "
          "have no owner and every template FROM resolves to nothing",
          file=sys.stderr)
    sys.exit(1)

# The DESTINATION column of the mirror list: what the internal registry
# ends up holding, which is what a template FROM is asked to resolve to.
images = seed / "platform" / "mirror-images" / "images.txt"
declared = set()
for ln in images.read_text(errors="replace").splitlines():
    ln = ln.strip()
    if not ln or ln.startswith("#"):
        continue
    f = ln.split()
    if len(f) >= 2:
        declared.add(f[1])

ph_re = re.compile(r"__FROM_[A-Z0-9_]+__")
n_ph = 0
for tpl in sorted(d for d in (seed / "templates").iterdir() if d.is_dir()):
    used = set()
    for f in sorted(tpl.rglob("*")):
        if f.is_file():
            try:
                used |= set(ph_re.findall(f.read_text(encoding="utf-8")))
            except (UnicodeDecodeError, OSError):
                continue
    readme = tpl / "README.md"
    text = readme.read_text(errors="replace") if readme.is_file() else ""
    for ph in sorted(used):
        n_ph += 1
        if ph not in table:
            bad.append(f"    {tpl.name}: {ph} belongs to no table — "
                       f"_FROM_IMAGES (libexec/aegis-app) owns the placeholders, "
                       f"and one it does not know stops `app new` after it has "
                       f"already resolved every other value")
        elif table[ph] not in declared and table[ph] not in text:
            bad.append(f"    {tpl.name}: {ph} means {table[ph]}, which "
                       f"mirror-images/images.txt does not declare, and this "
                       f"template's README never names it — so the template does "
                       f"not instantiate and nothing warns the operator first")

print(f"    {n_ph} FROM placeholder(s) crossed against _FROM_IMAGES "
      f"({len(table)} rows) and {len(declared)} mirrored image(s)", file=sys.stderr)
for m in bad:
    print(m, file=sys.stderr)
sys.exit(1 if bad else 0)
P3

if [[ -n "$D148" ]]; then fail "templates:$D148"
else pass "$n_tpl template(s) complete (contract, skeleton, k8s/base + overlay, ci and README), every FROM a placeholder its table resolves or a digest, and every FINAL stage numeric and non-root"; fi
}
