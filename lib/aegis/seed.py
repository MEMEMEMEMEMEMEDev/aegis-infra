"""aegis seed — the half of bringing a seed file over that the copy cannot do.

A file the seed owns can still carry PINS the instance moved: the update
window bumps `targetRevision`, `image:`, the kaniko tag in a pod
template, a FROM digest. Copying the seed's file over would put the
seed's older pins back — a downgrade nobody asked for, dressed as a
fix. So `aegis seed apply` reads the instance's pins before the copy
(`pins.read`), copies and renders, reads them again, and writes every
pin that moved BACK to the instance's value through the same edit the
window uses (`window.rewrite`): the seed's structure, the instance's
versions. A pin the seed added is kept; a pin the seed removed is gone
with the file, and it is said.
"""
import fnmatch
import json
import os
import pathlib
import re
import sys

from . import markers, pins, window

# ── who owns what ────────────────────────────────────────────────────
# THE INSTANCE'S: the seed ships a sample and the instance fills it in,
# or `aegis org apply` / the init / the tenants write it wholesale. They
# differ by construction and they are never brought over. Derived from
# what org.py declares it writes, plus the instance's own data files.
INSTANCE_OWNS = (
    "orgs/*", "plans.yaml", "services.yaml", "edge.yaml",
    "mirror-images/images.txt", "ansible/inventory/group_vars/all.yml",
    "tofu/envs/*", "tofu/secrets/*", "*.enc", "*.enc.yaml", "*.enc.json", ".sops.yaml",
    "k8s/organizations/*", ".aegis-app/*", "k8s/base/storage/*",
    # written wholesale by aegis org apply (lib/aegis/org.py: AI_REGISTRY,
    # ROUTES_K8S, TENANTS_K8S, APPPROJECTS_K8S, PROVISION_K8S,
    # ARGOCD_SECRETGEN, MAIN_TF); ai/routes.yaml and ai/tasks.yaml are
    # READ by it and stay the seed's
    "k8s/base/ai-system/registro.yaml", "k8s/base/ai-system/routes.yaml",
    "k8s/argocd-apps/tenants.yaml", "k8s/bootstrap/appprojects-tenants.yaml",
    "k8s/base/garage-system/aprovisionar.yaml",
    "k8s/base/platform/argocd-secrets/secret-generator.yaml",
    # hand-written content the operator edits (the seed ships them empty)
    "k8s/base/ai-system/prompts.yaml", "mirror-images/trivyignore.yaml", "ai/tasks.yaml",
)
# MIXED: the seed ships the structure and the init's phases APPEND to
# it (a secret entry per phase, a resource the phase turns on). Neither
# side owns the whole file, so it is reported by name and never brought
# over by this command: the two are read by eye.
MIXED = (
    "k8s/base/platform/jenkins-secrets/secret-generator.yaml",
    "k8s/base/platform/jenkins-secrets/kustomization.yaml",
    "k8s/base/garage-system/secret-generator.yaml",
    "k8s/base/garage-system/kustomization.yaml",
    "k8s/base/kyverno-policies/kustomization.yaml",
)
# GENERATED placeholders: rendered by a phase, not by the config
# render, so the seed keeps the marker and the instance carries the
# material. Both are cut to one token before comparing.
# The block keeps its indent: inject_placeholder writes the material at
# the marker's indent, so the marker and the block compare at the same
# column once both are one token.
_PEM = re.compile(r"^([ \t]*)-----BEGIN [A-Z ]+-----\n(?:.*\n)*?[ \t]*-----END [A-Z ]+-----[ \t]*$", re.M)
_PEM_MARK = re.compile(r"__(?:[A-Z_]*_PEM|COSIGN_PUB)__")
_HASH = re.compile(r"\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}")
_HASH_MARK = re.compile(r"__OBS_NTFY_[A-Z]+_HASH__")
# SEED-OWNED WITH A DERIVED BLOCK INSIDE: the structure is the seed's,
# the block between the markers is the instance's. Compared with the
# block cut out; brought over with the instance's block spliced back.
DERIVED_BLOCKS = {
    "k8s/base/platform/jenkins/values.yaml": markers.JOBS_BLOCK_PATTERN,
    "k8s/base/observability/vmagent/values.yaml": markers.PROBES_BLOCK_PATTERN,
    "base-images/consumers.txt": markers.CONSUMERS_BLOCK_PATTERN,
}
# A PIN LINE is a version or a digest the update window moves. A file
# whose only differences are pin lines is the instance being newer than
# the seed on purpose, not a seed change the instance lacks.
PIN_LINE = re.compile(r"^\s*(-\s*)?(image|targetRevision|tag|digest):|@sha256:[0-9a-f]{64}|executor:v[0-9]")


def instance_owns(rel):
    return any(fnmatch.fnmatch(rel, pat) for pat in INSTANCE_OWNS)


def is_mixed(rel):
    return rel in MIXED


def _normalised(text, rel):
    """FROM lines are the instance's (`aegis ai bases` resolves them);
    a derived block is the instance's; both are cut before comparing."""
    text = re.sub(r"^FROM .*$", "FROM __NORMALISED__", text, flags=re.M)
    text = _PEM.sub(r"\1__PEM__", text)
    text = _PEM_MARK.sub("__PEM__", text)
    text = _HASH.sub("__HASH__", text)
    text = _HASH_MARK.sub("__HASH__", text)
    pat = DERIVED_BLOCKS.get(rel)
    if pat:
        text = pat.sub("__DERIVED_BLOCK__", text)
    return text


def classify(rendered_seed, platform_dir):
    """Every file the seed ships, against the instance's copy.

    Returns a dict of lists: same (count), owned, pinned, added, differs.
    """
    seed = pathlib.Path(rendered_seed); inst = pathlib.Path(platform_dir)
    out = {"same": 0, "owned": [], "mixed": [], "pinned": [], "added": [], "differs": []}
    for f in sorted(p for p in seed.rglob("*") if p.is_file() and ".git" not in p.parts):
        rel = str(f.relative_to(seed))
        if rel.endswith(".tpl"):
            continue
        g = inst / rel
        if instance_owns(rel) or is_mixed(rel):
            if g.is_file() and _normalised(f.read_text(errors="replace"), rel) != _normalised(g.read_text(errors="replace"), rel):
                out["mixed" if is_mixed(rel) else "owned"].append(rel)
            continue
        if not g.is_file():
            out["added"].append(rel); continue
        a = _normalised(f.read_text(errors="replace"), rel).splitlines()
        b = _normalised(g.read_text(errors="replace"), rel).splitlines()
        if a == b:
            out["same"] += 1; continue
        import difflib
        changed = [ln[2:] for ln in difflib.ndiff(a, b) if ln[:2] in ("- ", "+ ")]
        if changed and all(PIN_LINE.search(ln) for ln in changed):
            out["pinned"].append(rel)
        else:
            out["differs"].append(rel)
    return out


def splice_block(platform_dir, rel, instance_text_before):
    """After a seed copy, put the instance's DERIVED block back."""
    pat = DERIVED_BLOCKS.get(rel)
    if not pat:
        return False
    theirs = pat.search(instance_text_before)
    if not theirs:
        return False
    f = pathlib.Path(platform_dir) / rel
    now = f.read_text()
    if not pat.search(now):
        return False
    f.write_text(pat.sub(lambda m: theirs.group(0), now, count=1))
    return True


def pin_lines(platform_dir, pins_map, files):
    """For each file about to be copied, the exact LINES that carry a pin
    and the value they carry: {rel: [(line_text, value), …]}.

    PER SITE, not per pin. A pin can live in seventeen Jenkinsfiles at
    once (the kaniko executor tag does); `pins.read` reports one current
    value for the pin, taken from wherever it reads first. Copy ONE of
    those files from the seed and the pin-level comparison sees the same
    current value in the sixteen others and says «unchanged», while the
    copied file quietly carries the seed's older tag. Measured 2026-09-20
    on the first real `aegis seed apply`: base-images/Jenkinsfile came
    back on kaniko v1.23.2 beside sixteen files on v1.24.0.
    """
    files = {str(f) for f in files}
    out = {}
    for pin in pins_map.values():
        val = pin.current or pin.digest
        if not val:
            continue
        for rel, lineno in pin.where:
            if rel not in files:
                continue
            f = pathlib.Path(platform_dir) / rel
            if not f.is_file():
                continue
            lines = f.read_text(encoding="utf-8").splitlines()
            if 1 <= lineno <= len(lines) and val in lines[lineno - 1]:
                out.setdefault(rel, []).append((lines[lineno - 1], val))
    return out


def repin_lines(platform_dir, snapshot):
    """After the copy: every line that is the old pin line with only the
    token changed gets the old line back. Returns what was restored."""
    restored = []
    for rel, entries in snapshot.items():
        f = pathlib.Path(platform_dir) / rel
        if not f.is_file():
            continue
        text = f.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)
        for old_line, val in entries:
            if any(ln.rstrip("\n") == old_line for ln in lines):
                continue                                   # still there
            pat = re.compile("^" + re.escape(old_line).replace(re.escape(val), r"(\S+)") + "$")
            for i, ln in enumerate(lines):
                m = pat.match(ln.rstrip("\n"))
                if m and m.group(1) != val:
                    lines[i] = old_line + ("\n" if ln.endswith("\n") else "")
                    restored.append(f"{rel}: {m.group(1)} → {val}")
                    break
        f.write_text("".join(lines), encoding="utf-8")
    return restored


def repin(platform_dir, before, files):
    """Put the instance's pins back into `files` after a seed copy.

    `before` is the pin dictionary taken before the copy. Returns
    (restored, gone): the pins written back, and the pins of those
    files that no longer exist in the copied tree.
    """
    after = pins.read(str(platform_dir))
    files = {str(f) for f in files}
    restored, gone = [], []
    for key, old in before.items():
        if not any(rel in files for rel, _ in old.where):
            continue
        new = after.get(key)
        if new is None:
            gone.append(old.key)
            continue
        if new.current == old.current and new.digest == old.digest:
            continue
        try:
            window.rewrite(platform_dir, new,
                           version=old.current if new.current != old.current else None,
                           digest=old.digest if new.digest != old.digest else None)
            restored.append(f"{old.key} {new.current or new.digest} → {old.current or old.digest}")
        except window.RefusedEdit as e:            # the line changed shape: say it, keep going
            gone.append(f"{old.key} (could not be written back: {e})")
    return restored, gone


if __name__ == "__main__":
    # aegis-seed drives this in two calls: `snapshot` writes the pins
    # before the copy to a file, `repin` reads it back afterwards.
    verb, platform, state = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
    if verb == "classify":
        # classify <rendered-seed> <platform> → JSON
        print(json.dumps(classify(sys.argv[2], sys.argv[3])))
    elif verb in ("steps", "report"):
        # the two printers: the house document, or the text. Both read
        # the classification from stdin, so the command stays thin.
        c = json.load(sys.stdin)
        rc = 1 if (c["added"] or c["differs"]) else 0
        if verb == "steps":
            steps = []
            for x in c["pinned"]:
                steps.append({"step": f"seed:{x}", "state": "already",
                              "por_que": "differs only in pinned versions: the instance moved them "
                                         "(the update window), the seed did not change the file"})
            for x in c["owned"]:
                steps.append({"step": f"seed:{x}", "state": "already",
                              "por_que": "the instance owns this file: it differs by construction "
                                         "and is never brought over"})
            for x in c["mixed"]:
                steps.append({"step": f"seed:{x}", "state": "notice",
                              "por_que": "the seed ships the structure and the init's phases append "
                                         "to it: it differs, and the two are read by eye, never "
                                         "brought over by this command"})
            for x in c["added"]:
                steps.append({"step": f"seed:{x}", "state": "wrong",
                              "por_que": "the seed ships it and the instance lacks it"})
            for x in c["differs"]:
                steps.append({"step": f"seed:{x}", "state": "wrong",
                              "por_que": "the seed changed it and the change is not here yet"})
            steps.append({"step": "seed:same", "state": "already", "cuantos": c["same"]})
            print(json.dumps({"steps": steps, "rc": rc}, ensure_ascii=False, indent=1))
        else:
            tty = os.isatty(1)
            def col(code, text):
                return f"\033[{code}m{text}\033[0m" if tty else text
            print(col("90", f"{c['same']} file(s) of the seed are the same here"))
            if c["owned"]:
                print(col("90", "owned by this instance, differ by construction, never brought over:"))
                for x in c["owned"]:
                    print(f"  {x}")
            if c["mixed"]:
                print(col("90", "the seed ships the structure and the phases append to it (read by eye, never brought over here):"))
                for x in c["mixed"]:
                    print(f"  {x}")
            if c["pinned"]:
                print(col("90", "differ only in pinned versions (the instance moved them; the seed did not change the file):"))
                for x in c["pinned"]:
                    print(f"  {x}")
            if c["added"]:
                print(col("1;33", "the seed ships these and the instance lacks them:"))
                for x in c["added"]:
                    print(col("33", f"  + {x}"))
            if c["differs"]:
                print(col("1;31", "the seed changed these and the change is not here yet:"))
                for x in c["differs"]:
                    print(col("31", f"  ~ {x}"))
            if rc == 0:
                print(col("32", "everything the seed owns is here already"))
            else:
                print(col("90", "bring one over (copy AND render, the instance's pins and derived blocks kept, then a commit you read and push):"))
                print(col("90", "  " + os.environ.get("AEGIS_CMD", "aegis") + " seed apply <path>... --yes"))
        sys.exit(rc)
    elif verb == "owns":
        # owns <any> <rel>... → rc 1 if any is the instance's, printing it
        bad = [r for r in sys.argv[3:] if instance_owns(r) or is_mixed(r)]
        for r in bad:
            print(r)
        sys.exit(1 if bad else 0)
    elif verb == "block-snapshot":
        # block-snapshot <platform> <state> <rel>... → the instance's derived blocks
        blocks = {}
        for rel in sys.argv[4:]:
            f = platform / rel
            if rel in DERIVED_BLOCKS and f.is_file():
                blocks[rel] = f.read_text()
        state.write_text(json.dumps(blocks))
    elif verb == "block-splice":
        blocks = json.loads(state.read_text()) if state.is_file() else {}
        for rel, before in blocks.items():
            if splice_block(platform, rel, before):
                print(f"derived block kept: {rel}")
    elif verb == "snapshot":
        before = pins.read(str(platform))
        state.write_text(json.dumps({"pins": {k[0] + ":" + k[1]: {"cls": p.cls, "name": p.name, "current": p.current,
                                                                  "digest": p.digest, "where": p.where}
                                             for k, p in before.items()},
                                     "lines": pin_lines(platform, before, sys.argv[4:])}))
    elif verb == "repin":
        raw = json.loads(state.read_text())
        before = {(v["cls"], v["name"]): pins.Pin(v["cls"], v["name"], v["current"],
                                                  [tuple(w) for w in v["where"]], v["digest"])
                  for v in raw["pins"].values()}
        # lines first (per site), then the pin model (what the lines missed)
        for r in repin_lines(platform, raw.get("lines", {})):
            print(f"repin: {r}")
        restored, gone = repin(platform, before, sys.argv[4:])
        for r in restored:
            print(f"repin: {r}")
        for g in gone:
            print(f"gone: {g}", file=sys.stderr)
