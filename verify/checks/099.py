"""Check 099 — the console writes one contract, in one place, or nothing.

The console reads. Now one screen of it writes, and that is the moment
a tool stops being safe by construction and starts being safe by
promise. The promise is small on purpose and it is `aegis org`'s own:

    it writes ONE contract into orgs/, it does not commit, it does not
    push, it does not apply, and it does not touch the cluster.

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
READ_ONLY = {
    "org list", "org schema", "org plan", "org validate", "repos list",
    "tenant show", "traffic show", "capacity show", "builds show",
    "check", "edge check", "data remote status",
}
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
                                  for r in READ_ONLY))
if unknown:
    findings.append(f"the console invokes {unknown}, which is not on the list of commands "
                    f"that only read: a console that changes something outside this "
                    f"process is no longer a thing you can run at any moment")
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
print(f"SCOPE: one contract written against a fixture tree and the whole tree compared, "
      f"{len(invoked)} aegis command(s) invoked and {len(spawned)} program(s) spawned, "
      f"none of them able to change anything outside this process")
