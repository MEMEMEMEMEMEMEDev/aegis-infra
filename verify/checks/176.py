# scanner of check 176 — the pruner of the internal registry is dry by
# default and nothing the instance fixes is a candidate.
#
# It is its own python file for the two reasons this tree has paid for
# more than once: a sed that fails silently prints nothing and turns a
# check green (check 166), and a grep over a file that documents every
# decision beside the code reads the paragraph explaining the defect as
# the defect (checks 161, 163, 165, 166, 167, 168 — and the eighth time
# was the one that made this a rule). Everything below is read from the
# code with the comments taken out; the ONE line read raw is the
# `# aegis-subcommands:` metadata, which is a comment on purpose and is
# the same source check 112 and the menu read.
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
img = root / "libexec" / "aegis-image"
doc = root / "seed" / "platform" / "docs" / "protocols" / "images.md"
if not img.is_file():
    sys.exit("libexec/aegis-image does not exist: this check has no subject")

raw = img.read_text(encoding="utf-8")
# `#` opens a comment in shell and in python at the start of a line or
# after whitespace — the shape that leaves `${1#--keep=}` and a URL's
# `https://` alone. The embedded python of this command follows the same
# convention, so one rule covers both languages of the file.
HASH = re.compile(r'(^|\s)#.*$')
lines = [HASH.sub(r'\1', l) for l in raw.splitlines()]
code = "\n".join(lines)

D = []


def body_of(name):
    """The body of a bash function, from `name() {` to the `}` in column 0."""
    out, on = [], False
    for line in lines:
        if line.startswith(name + "()"):
            on = True
            continue
        if on and line.startswith("}"):
            break
        if on:
            out.append(line)
    return "\n".join(out)


# ── 1. the verb exists, is accepted, and is dispatched ───────────────
# Three places, because a verb missing from any one of them fails
# differently: the metadata is what check 112 and the menu read, the
# guard is what refuses an unknown subcommand before anything is
# sourced, and the dispatch is what actually runs.
subs = ""
for line in raw.splitlines()[:20]:
    if line.startswith("# aegis-subcommands:"):
        subs = line.split(":", 1)[1]
if "gc" not in subs.split():
    D.append("libexec/aegis-image does not declare `gc` in its `# aegis-subcommands:` line, "
             "so the menu and check 112 do not know the subcommand exists")
if not re.search(r'^\s*request\|list\|from\|check\|gc\)', code, re.M):
    D.append("the guard that accepts subcommands does not accept `gc`: the verb would be "
             "refused as invalid usage before a single line of it runs")
if not re.search(r'^\s*gc\)\s+do_gc\s*;;', code, re.M):
    D.append("no branch of the dispatch maps `gc` to do_gc: the subcommand would be accepted "
             "and then do nothing at all, which is the worst of the three ways to be missing")
if not body_of("do_gc"):
    D.append("aegis-image has no do_gc function: the verb that prunes the registry is not there, "
             "and the registry keeps every image ever built")

# ── 2. dry by default ────────────────────────────────────────────────
# GC_ACT is the whole difference between saying and doing. It has to
# open at 0, and the ONLY thing that may set it to 1 is a person typing
# --yes: an environment variable or a default of 1 would turn «explain
# the plan» into «delete» for every caller that never asked.
assigns = [(i, m.group(1)) for i, l in enumerate(lines)
           for m in [re.search(r'\bGC_ACT=([^\s;)]*)', l)] if m]
if not assigns:
    D.append("nothing in aegis-image assigns GC_ACT: the flag that separates explaining a plan "
             "from carrying it out does not exist")
else:
    if assigns[0][1] != "0":
        D.append("the first assignment of GC_ACT is «%s» and not 0: the command would delete by "
                 "default, and deleting images is not an operation that happens on its own"
                 % assigns[0][1])
    for i, value in assigns:
        if value == "1" and "--yes" not in lines[i]:
            D.append("GC_ACT is set to 1 on a line that does not carry --yes (line %d): "
                     "something other than a person asking turns this command into a delete" % (i + 1))
        if value not in ("0", "1"):
            D.append("GC_ACT is assigned «%s»: it is a two-state flag and anything else is a "
                     "third state nobody guarded" % value)

# ── 3. one place deletes, and it refuses twice before it does ────────
# The two refusals live INSIDE the deleter and not at its call site.
# A guard at the call site has to be written again by whoever adds the
# next one, and the one who forgets is the one nobody notices — the
# class, not the case.
deleters = [fn for fn in re.findall(r'^([a-z_][a-z0-9_]*)\(\)', code, re.M)
            if "-X DELETE" in body_of(fn)]
if not deleters:
    D.append("nothing in aegis-image issues a DELETE against the registry: the manifests are "
             "never unlinked, so the collector has nothing to collect and nothing is ever freed")
elif len(deleters) > 1:
    D.append("%d functions issue a DELETE against the registry (%s): the guards would have to be "
             "repeated in each of them, and the copy that forgets one is the copy nobody notices"
             % (len(deleters), ", ".join(deleters)))
else:
    dbody = body_of(deleters[0]).splitlines()
    where_curl = next((i for i, l in enumerate(dbody) if "-X DELETE" in l), len(dbody))
    before = "\n".join(dbody[:where_curl])
    if not re.search(r'\(\(\s*GC_ACT\s*==\s*1\s*\)\)', before):
        D.append("%s issues the DELETE without asking whether this run was told to act: the dry "
                 "run would delete, and the whole point of the default is that it does not"
                 % deleters[0])
    if "gc_planned_prune" not in before:
        D.append("%s deletes without consulting the plan: what the instance fixes by digest, what "
                 "images.txt declares, what the cluster is running and the newest images of each "
                 "repository are KEEP rows of that plan, and without reading it this function will "
                 "delete whatever it is handed — including the image that is serving traffic"
                 % deleters[0])

planned = body_of("gc_planned_prune")
if not planned:
    D.append("aegis-image has no gc_planned_prune: the deleter has nothing to check a candidate "
             "against, so «the plan said so» stops being a fact anybody can verify")
elif 'PRUNE' not in planned:
    D.append("gc_planned_prune does not require the plan's verdict to be PRUNE: a KEEP row would "
             "satisfy it, which is the same as having no protection at all")

# ── 4. the protected set is DERIVED, from all three places it lives ──
# The instance's manifests answer «what does this platform fix», the
# list answers «what does aegis image check promise», and the cluster
# answers «what is running right now» — and only the cluster can answer
# for the tenants, whose overlays live in their own repositories and not
# on this disk. Any one of the three missing is a class of image the
# pruner would happily delete.
pins = body_of("gc_pins")
if not pins:
    D.append("aegis-image has no gc_pins: there is no protected set, so the pruner has nothing to "
             "subtract and every image in the registry is a candidate")
else:
    if "$PLATFORM_DIR" not in pins:
        D.append("gc_pins does not read $PLATFORM_DIR: what this instance fixes by digest would "
                 "not be protected, and a digest pinned in a manifest is in use however old its tag is")
    if not re.search(r'(^|[^_a-z])entries\b', pins):
        D.append("gc_pins does not read the declared list: `aegis image check` promises the "
                 "registry serves every destination of images.txt, and pruning one would make this "
                 "same command break its own promise")
    if "kubectl" not in pins:
        D.append("gc_pins never asks the cluster what it is running: the tenants' overlays live in "
                 "the organisations' repositories and not on this disk, so without that question "
                 "the image of a pod that is serving traffic is a candidate for deletion")
    if not re.search(r'-n\s+"\$live"', pins):
        D.append("gc_pins does not check that the cluster actually answered: an unanswered read "
                 "would come out as «nothing is running» and every tenant image would become a "
                 "candidate — the emptiest possible protected set produced by the loudest possible "
                 "failure")

scan = body_of("gc_scan_manifests")
if not scan:
    D.append("aegis-image has no gc_scan_manifests: the pins written in the instance's manifests "
             "are read by nothing")
elif "python3" not in scan:
    D.append("the scan of the instance's manifests is not python: a pipeline that dies mid-way "
             "prints nothing, and «nothing is pinned» is the one wrong answer this command must "
             "never get (the lesson of check 166)")

# ── 5. a scan that dies takes the command with it ────────────────────
# Rule 6 of this tree, and it is why the scanner is a program and not a
# pipeline: an empty protected set and a registry with nothing pinned
# look identical from the caller's side, and one of them deletes
# everything.
if pins and not re.search(r'gc_scan_manifests[^\n]*\n?[^\n]*\|\|\s*die', pins):
    D.append("gc_pins does not stop when the scan of the instance's manifests fails: a scan that "
             "prints nothing and a tree that pins nothing are the same thing to whatever reads it, "
             "and one of the two deletes what is running")

gcbody = body_of("do_gc")
if gcbody:
    if not re.search(r'gc_plan[^\n]*\|\|\s*die', gcbody):
        D.append("do_gc does not stop when the plan cannot be computed: an empty plan file is a "
                 "plan with no KEEP rows, and the deleter's guard reads that file")
    # ORDER. The protected set has to exist before the plan is computed:
    # a plan built first would subtract an empty file and call everything
    # a candidate.
    i_pins = gcbody.find("gc_pins")
    i_plan = gcbody.find("gc_plan")
    if i_pins < 0 or i_plan < 0:
        D.append("do_gc does not both build the protected set and compute a plan: those two are "
                 "the whole decision")
    elif i_pins > i_plan:
        D.append("do_gc computes the plan before it builds the protected set: the plan would "
                 "subtract a file that is not there yet, which is subtracting nothing")

# ── 6. the planner subtracts, and the signatures travel with it ──────
plan = body_of("gc_plan")
if not plan:
    D.append("aegis-image has no gc_plan: nothing decides what is a candidate, and a delete with "
             "no plan behind it is a delete with no reason behind it")
else:
    if "gc-protected.tsv" not in plan:
        D.append("gc_plan is not given the protected set: it would rank images by age and nothing "
                 "else, and the oldest image of a repository is very often the one pinned in a "
                 "manifest")
    for token in ("prot_digest", "prot_tag"):
        if token not in plan:
            D.append("the planner never consults %s: one of the two ways an image is protected "
                     "(by digest, by tag) is not being subtracted" % token)
    # cosign publishes a signature as the TAG `sha256-<hex>.sig`, so
    # `--delete-untagged` marks it live and leaves its blobs where they
    # are. If the planner does not carry the companions of a pruned
    # digest, the prune frees less than it says and leaves a signature
    # of nothing behind.
    if not re.search(r'sha256-\(\[0-9a-f\]\{64\}\)', plan):
        D.append("the planner does not derive the signature companions from the digest "
                 "(`sha256-<hex>.<suffix>`): cosign stores them as TAGS, so --delete-untagged "
                 "marks them live and leaves their blobs — an image pruned without its companion "
                 "frees less than it claims and leaves a signature of nothing")
    if "verdicts.get(parent)" not in plan:
        D.append("the planner does not tie a companion's verdict to the manifest it signs: a "
                 "signature must go when its image goes and must stay when its image stays, and "
                 "nothing else decides it")

# ── 7. the retention default is one number, written in two places ────
# The doc is where the policy is argued and the code is where it is
# enforced. They are allowed to be two files; they are not allowed to
# say two different numbers, and the day they do it is the doc that
# gets believed and the code that acts.
m = re.search(r'^GC_KEEP_DEFAULT=(\d+)', code, re.M)
keep = None
if not m:
    D.append("aegis-image declares no GC_KEEP_DEFAULT: the retention policy is not a number "
             "anybody can read, argue with, or check against the documentation")
else:
    keep = m.group(1)
if not doc.is_file():
    D.append("seed/platform/docs/protocols/images.md is not there: the retention policy has "
             "nowhere to be argued")
elif keep is not None:
    text = doc.read_text(encoding="utf-8")
    declared = re.search(r'\*\*Default `--keep`:\*\*\s*(\d+)', text)
    if not declared:
        D.append("images.md does not declare the retention default in the shape this check reads "
                 "(`**Default `--keep`:** N`): a policy that is only in the code is a policy "
                 "nobody can disagree with")
    elif declared.group(1) != keep:
        D.append("images.md says the default retention is %s and aegis-image keeps %s: the "
                 "operator would plan a prune against the number that is not the one running"
                 % (declared.group(1), keep))

for line in D:
    print(line)
print("__KEEP__ %s" % (keep or "?"), file=sys.stderr)
print("__DELETERS__ %d" % len(deleters), file=sys.stderr)
