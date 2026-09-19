"""Check 099 — the console writes files in this instance, or nothing.

The console reads. Now two screens of it write, and that is the moment
a tool stops being safe by construction and starts being safe by
promise. The promise is small on purpose and it is `aegis org`'s own:

    it writes files in this instance — a contract into orgs/, what the
    contract derives, and since 2026-09-16 a plan into plans.yaml — it
    does not commit, it does not push, it does not apply, and it does
    not touch the cluster.

That is what makes a file in a working tree harmless — ArgoCD reads the
remote, so nothing runs until somebody commits. Every part of that
sentence can be broken by a change that looks like an improvement, and
none of them would fail: the console would go on working, and the only
difference would be what it had already done by the time anybody
noticed.

So the real function is run against a real tree, and the tree is
compared before and after. Not «does it write the right file» — WHAT
ELSE DID IT TOUCH. And then the source is read for the other half: a
console that invoked `org apply` or `git commit` would pass a check that
only counted files, because on a fixture with no cluster those commands
would have failed quietly.
"""
import ast
import importlib.machinery
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
SERVER = os.path.join(ROOT, "libexec", "aegis-console")

if not os.path.isfile(SERVER):
    print("SCOPE: there is no console: this check has no subject")
    sys.exit(0)

# The aegis commands this console is allowed to invoke. THE LIST LIVES
# HERE, in the check, because it is not a fact about the program: it is
# the policy the program is held to. Every one of them reads; none of
# them changes anything. `org plan` is the interesting entry — its whole
# job is to say what `apply` WOULD do, without doing it.
# What the console is allowed to invoke, and it is TWO lists now.
#
# The first only reads. The second WRITES FILES IN THIS INSTANCE and
# nothing else — `aegis org` promises it in its own module, `aegis
# secret` never invokes kubectl at all, and `aegis quota` (2026-09-16,
# a plan of your own from the console) has no subprocess in it: it
# edits plans.yaml textually and puts the result through the
# generator's own shape check. The same property the console already
# had, so taking them on changes no promise. `quota remove` is NOT
# here on purpose: the console adds and changes, and never removes.
READ_ONLY = {
    "org list", "org schema", "org plan", "org validate", "repos list",
    "tenant show", "traffic show", "capacity show", "builds show",
    "check", "edge check", "data remote status", "builds show --org",
    "quota list",
    # The two the Updates page draws (2026-09-18). `update inventory`
    # derives the pins from the platform checkout and asks public
    # registries; `update status` reads one file this instance wrote.
    # Neither writes, commits or touches the cluster — and the two verbs
    # of that command that DO (`window`, `rollback`) are deliberately
    # not here, and are caught by the blunt half below if the console
    # ever builds a call to them out of variables.
    "update inventory", "update status",
}
WRITES_FILES_HERE = {"org apply", "secret create", "quota add", "quota set"}
ALLOWED = READ_ONLY | WRITES_FILES_HERE

# Words that name a change this console may never make, wherever they
# appear as CODE. The list above cannot catch a call built out of
# variables —`cli.run_json(verb, *args)` hands the AST nothing to read—
# and that hole was open the day `finish_contract` was written. This is
# the blunt half, and blunt is what works here: a console that never
# spells `delete`, `destroy`, `restore`, `rotate` or `sync` cannot do
# any of them by accident.
#
# `init` is deliberately NOT here: it is a directory of this product
# (`init/aegis-init.conf.example`) and a blunt rule has to say where it
# stops. `aegis init` from a console would be caught by the list above
# anyway, which sees every literal invocation.
FORBIDDEN_WORDS = {"delete", "destroy", "restore", "rotate", "sync", "move",
                   "app", "backup", "rollback"}
# `window` is NOT here, and the reason is worth writing down rather than
# leaving as an omission somebody later "fixes". `aegis update window`
# is exactly the kind of change this list exists to keep out — but the
# word is also ordinary English on the screen that draws what the last
# update window did, and a blunt rule that fires on its own page is a
# rule somebody switches off. It is covered by the list of allowed
# invocations above, which sees every literal call; what the blunt half
# adds is only the calls built out of variables, and `rollback` is the
# one of the pair that is not also a noun.
# Programs that change something outside this process. They are looked
# for in CALLS and never in the text: the first version of this check
# grepped the source for the words and went red on its own comment,
# which is the mistake this repo has filed six times — a check that
# reads prose as if it were code. `git` and `kubectl` are named here
# rather than derived because they are the two ways out of this
# process that matter, and both are things the console must never be.
FORBIDDEN_PROGRAMS = ("kubectl", "helm", "argocd", "sops", "age")
# git is the exception, and it is an honest one: the capture asks it
# which commit produced a case, which reads. The subcommand is what
# decides, so the ones that only look are named and everything else —
# commit, push, add, tag, checkout, reset — is a change.
GIT_THAT_ONLY_LOOKS = ("rev-parse", "log", "status", "show", "diff", "describe",
                       "config", "remote")

findings = []

# ── what it actually writes ──────────────────────────────────────────
env_before = dict(os.environ)
home = tempfile.mkdtemp(prefix="aegis-099-")
try:
    shutil.copytree(os.path.join(ROOT, "seed", "platform"), os.path.join(home, "platform"))
    # EVERY POINTER AT AN INSTANCE IS CLEARED. verify/lib.sh exports
    # PLATFORM_DIR, and it wins over AEGIS_HOME — the mistake check 129
    # made on its first run, which was to measure the real instance and
    # report the result as proof about a fixture.
    for k in [k for k in os.environ if k.startswith("AEGIS_") or k == "PLATFORM_DIR"]:
        del os.environ[k]
    os.environ["AEGIS_HOME"] = home
    os.environ["AEGIS_ROOT"] = ROOT
    sys.path.insert(0, os.path.join(ROOT, "lib"))

    loader = importlib.machinery.SourceFileLoader("aegis_console_probe", SERVER)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    console = importlib.util.module_from_spec(spec)
    loader.exec_module(console)

    if not hasattr(console, "write_contract"):
        print("the console has no importable write: the rule about what it writes "
              "cannot be exercised, only read")
        print("SCOPE: the write was not reachable")
        sys.exit(0)

    def tree():
        return {os.path.relpath(os.path.join(dp, f), home): os.path.getmtime(
                    os.path.join(dp, f))
                for dp, _dn, fn in os.walk(home) for f in fn}

    GOOD = ("version: 1\norganizacion: probando\ndominio: probando.example.test\n"
            "cuota: pequena\nservicios:\n  - nombre: web\n    tipo: estatico\n"
            "    publico: /\n    repo: git@github.com:owner/probando-web.git\n")
    BAD = ("version: 1\norganizacion: Mal Nombre\ncuota: pequena\n"
           "servicios:\n  - {nombre: web, tipo: estatico, publico: /}\n")

    before = tree()
    target, why = console.write_contract(GOOD)
    after = tree()
    created = sorted(set(after) - set(before))
    touched = sorted(k for k in set(after) & set(before) if after[k] != before[k])

    if why:
        findings.append(f"a contract the validator accepts is refused by the console: "
                        f"{why}")
    elif created != [os.path.join("platform", "orgs", "probando.yaml")]:
        findings.append(f"writing one contract created {created or 'nothing'}: this "
                        f"console writes one file in orgs/ and nothing else, and every "
                        f"other path it touches is something nobody agreed to")
    if touched:
        findings.append(f"writing one contract modified files that already existed: "
                        f"{touched}")

    # AND IT DOES NOT WRITE OVER ONE THAT EXISTS. Creating an
    # organization that is already there is not a create; it is an edit,
    # and an edit that arrives disguised as a create is how somebody
    # loses a contract they spent an afternoon on.
    was = open(os.path.join(home, "platform", "orgs", "probando.yaml"),
               encoding="utf-8").read() if not why else None
    again_target, again_why = console.write_contract(
        GOOD.replace("cuota: pequena", "cuota: grande"))
    if again_target or not again_why:
        findings.append("writing a contract for an organization that already has one is "
                        "allowed: an edit arrived disguised as a create")
    if was is not None:
        now = open(os.path.join(home, "platform", "orgs", "probando.yaml"),
                   encoding="utf-8").read()
        if now != was:
            findings.append("the refused second write changed the contract that was "
                            "already there anyway")

    # An invalid contract writes NOTHING. Validating after writing would
    # leave a file the generator refuses sitting in the repo.
    before = tree()
    bad_target, bad_why = console.write_contract(BAD)
    after = tree()
    if bad_target or not bad_why:
        findings.append("a contract the validator refuses is written anyway")
    if set(after) - set(before):
        findings.append(f"a refused contract still left {sorted(set(after) - set(before))} "
                        f"behind: it is validated after being written, not before")

    # ── THE CONSOLE'S PATH IS THE CLI'S PATH ─────────────────────────
    # The strongest thing this check can say, now that the console does
    # more than write one file: what it leaves behind has to be exactly
    # what somebody doing it by hand leaves behind. Not «it wrote
    # something reasonable» — the SAME tree. A console that is a second
    # way of producing a platform repo is a second thing to keep in
    # step; one that is the same way with fewer keystrokes is not.
    if hasattr(console, "finish_contract"):
        target = os.path.join(home, "platform", "orgs", "probando.yaml")
        before = tree()
        console.finish_contract(target)
        by_console = set(tree()) - set(before)

        # And now the same, by hand, on a copy of the tree as it was.
        twin = tempfile.mkdtemp(prefix="aegis-099-twin-")
        try:
            shutil.copytree(os.path.join(ROOT, "seed", "platform"),
                            os.path.join(twin, "platform"))
            for extra in ("aegis.conf",):
                src = os.path.join(home, extra)
                if os.path.isfile(src):
                    shutil.copy(src, os.path.join(twin, extra))
            twin_contract = os.path.join(twin, "platform", "orgs", "probando.yaml")
            with open(twin_contract, "w", encoding="utf-8") as fh:
                fh.write(GOOD)
            env = {k: v for k, v in os.environ.items()
                   if not (k.startswith("AEGIS_") or k == "PLATFORM_DIR")}
            env.update({"AEGIS_HOME": twin, "AEGIS_ROOT": ROOT})
            base = {os.path.relpath(os.path.join(dp, f), twin)
                    for dp, _d, fn in os.walk(twin) for f in fn}
            subprocess.run([os.path.join(ROOT, "bin", "aegis"), "org", "apply",
                            twin_contract], capture_output=True, text=True,
                           env=env, cwd=twin)
            by_hand = {os.path.relpath(os.path.join(dp, f), twin)
                       for dp, _d, fn in os.walk(twin) for f in fn} - base
        finally:
            shutil.rmtree(twin, ignore_errors=True)

        only_console = sorted(by_console - by_hand)
        only_hand = sorted(by_hand - by_console)
        if only_console:
            findings.append(f"the console left {only_console}, which doing it by hand does "
                            f"not: it is a second way of producing a platform repository, "
                            f"and a second way is a second thing to keep in step")
        if only_hand:
            findings.append(f"doing it by hand leaves {only_hand} and the console does not: "
                            f"whoever used the screen has an organization that is missing "
                            f"something, and nothing told them")
finally:
    shutil.rmtree(home, ignore_errors=True)
    os.environ.clear()
    os.environ.update(env_before)

# ── and what it never invokes ────────────────────────────────────────
with open(SERVER, encoding="utf-8") as fh:
    source = fh.read()
tree_ast = ast.parse(source)

invoked = set()
for node in ast.walk(tree_ast):
    if not isinstance(node, ast.Call):
        continue
    fn = node.func
    if not (isinstance(fn, ast.Attribute) and fn.attr in ("run", "run_json")):
        continue
    words = [a.value for a in node.args if isinstance(a, ast.Constant)
             and isinstance(a.value, str)]
    if words:
        invoked.add(" ".join(words[:2]).strip())
# The source lists some of what it reads as data (SOURCES, ORG_SOURCES)
# rather than as call arguments, so those strings are collected too:
# a command named in a list is a command this console runs.
for node in ast.walk(tree_ast):
    if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id.endswith("SOURCES") for t in node.targets):
        for elt in ast.walk(node.value):
            if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                line = elt.value.replace("{org}", "").replace("--org", "").strip()
                invoked.add(" ".join(line.split()[:2]).strip())

unknown = sorted(v for v in invoked
                 if v and not any(v == r or r.startswith(v) or v.startswith(r)
                                  for r in ALLOWED))
if unknown:
    findings.append(f"the console invokes {unknown}, which is neither a command that only "
                    f"reads nor one of the four that write files in this instance: a "
                    f"console that changes something outside this process is no longer a "
                    f"thing you can run at any moment")

# THE BLUNT HALF, over every string the source uses as code. Docstrings
# are skipped, because a check that reads prose as code is the mistake
# this repository has filed seven times — the seventh being this very
# file, on 2026-09-12.
docstrings = set()
for node in ast.walk(tree_ast):
    if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        body = getattr(node, "body", None) or []
        if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) \
                and isinstance(body[0].value.value, str):
            docstrings.add(id(body[0].value))
said = {n.value for n in ast.walk(tree_ast)
        if isinstance(n, ast.Constant) and isinstance(n.value, str)
        and id(n) not in docstrings}
spoken = sorted(FORBIDDEN_WORDS & said)
if spoken:
    findings.append(f"the console's code carries {spoken} as a string: every one of them "
                    f"names a change this screen may never make, and a call built out of "
                    f"variables is a call no list of invocations can see")
# Anything spawned directly, as opposed to through cli.run. The console
# has no business starting a program of its own: `git commit` is one
# line away from here and it is the line that would make this screen
# unsafe.
spawned = set()
for node in ast.walk(tree_ast):
    if not isinstance(node, ast.Call):
        continue
    fn = node.func
    name = fn.attr if isinstance(fn, ast.Attribute) else getattr(fn, "id", "")
    if name not in ("run", "Popen", "call", "check_call", "check_output", "system"):
        continue
    if isinstance(fn, ast.Attribute) and isinstance(fn.value, ast.Name) \
            and fn.value.id == "cli":
        continue                      # that path is measured above
    for arg in node.args:
        words = [e.value for e in ([arg] if isinstance(arg, ast.Constant)
                                   else getattr(arg, "elts", []))
                 if isinstance(e, ast.Constant) and isinstance(e.value, str)]
        if not words:
            continue
        program = os.path.basename(words[0])
        # `-C <dir>` and its kin sit between the program and the verb,
        # so the verb is the first word that is not a flag or its value.
        rest = [w for w in words[1:] if not w.startswith("-")]
        spawned.add(program)
        if program in FORBIDDEN_PROGRAMS:
            findings.append(f"the console starts `{program}`: touching the cluster or the "
                            f"secrets is not this screen's, and the whole safety of it is "
                            f"that it stops at the file")
        if program == "git":
            verb = next((w for w in rest if w in GIT_THAT_ONLY_LOOKS
                         or not os.path.sep in w), None)
            if verb is not None and verb not in GIT_THAT_ONLY_LOOKS:
                findings.append(f"the console runs `git {verb}`: what makes a file in a "
                                f"working tree harmless is that nobody committed it, and "
                                f"committing is the operator's")
        break                          # the argv is the first argument

for f in findings:
    print(f)
print(f"SCOPE: one contract written and finished against a fixture tree, the whole tree "
      f"compared against doing it by hand, {len(invoked)} aegis command(s) invoked and "
      f"{len(spawned)} program(s) spawned, none able to change anything outside this machine")
