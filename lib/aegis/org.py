"""aegis-org — one organization's contract, made real.

Implements docs/protocols/organization.md. It reads a contract from
`orgs/<name>.yaml` and writes the manifests into
`k8s/organizations/org-<name>/`.

IT DOES NOT TALK TO THE CLUSTER. It does not import kubernetes, does not
invoke kubectl, does not read a kubeconfig. It writes files in the repo
and it is done; the one who deploys is ArgoCD, after a human reviews the
diff and commits. That is not purism: it is what makes running this safe
at any moment, because the worst that can happen is an ugly diff nobody
commits.

It is in python3 and not in bash for one concrete reason: a schema has
to be validated and a render has to be deterministic. In bash that ends
up being sed over YAML, which is the repo's Disease A ("YAML as a
string"). python3 and not yq, by rule C7.
"""
import argparse
import difflib
import hashlib
import json
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit("pyyaml is missing (python3-yaml)")

from . import cli, markers, paths

# ── Class E: not one command name written by hand ────────────────────
# In v2 this file had 15 of them (and the whole tree ~155). Each one is
# a promise that ages: the day the command is called something else, the
# messages —and worse, the COMMENTS of the generated manifests, which
# the operator reads months later— go on saying the old name. They are
# not translated one by one: they are derived from a single one, which
# comes from argv[0].
CMD_ORG        = cli.cmd("org")
CMD_ORG_APPLY  = cli.cmd("org apply")
CMD_SECRET     = cli.cmd("secret create")
CMD_CHECK      = cli.cmd("check")
CMD_SYNC_ROOT  = cli.cmd("sync root")

# PLATFORM_ROOT is the INSTANCE, not the product.
#
# Until 2026-08-23 this line said `dirname(dirname(__file__))`, and it
# was right while the command lived in <instance>/platform/bin/: two
# levels up gave <instance>/platform. On moving the code to the product
# (02 §1) the SAME line went on compiling and started pointing at
# <product>, looking for orgs/ and k8s/ where they are not. Nothing
# would have warned: it is the register's C1/C2 «dependency invisible to
# a grep», with a date on it. Now a single resolver decides it, the same
# one bash uses (lib/paths.sh).
PLATFORM_ROOT = str(paths.platform_dir())
ORGS_DIR = os.path.join(PLATFORM_ROOT, "orgs")
K8S_DIR = os.path.join(PLATFORM_ROOT, "k8s", "organizations")
PLANS = os.path.join(PLATFORM_ROOT, "plans.yaml")
EDGE = os.path.join(PLATFORM_ROOT, "edge.yaml")
SERVICES = os.path.join(PLATFORM_ROOT, "services.yaml")
ROUTES = os.path.join(PLATFORM_ROOT, "ai", "routes.yaml")
AI_TASKS = os.path.join(PLATFORM_ROOT, "ai", "tasks.yaml")
AI_REGISTRY = os.path.join(PLATFORM_ROOT, "k8s", "base", "ai-system", "registro.yaml")
ROUTES_K8S = os.path.join(PLATFORM_ROOT, "k8s", "base", "ai-system", "routes.yaml")
AI_DIR = os.path.join(PLATFORM_ROOT, "k8s", "base", "ai-system")
TENANTS_K8S = os.path.join(PLATFORM_ROOT, "k8s", "argocd-apps", "tenants.yaml")
PROVISION_JS = os.path.join(PLATFORM_ROOT, "ai", "aprovisionar-bucket.mjs")
GARAGE_DIR = os.path.join(PLATFORM_ROOT, "k8s", "base", "garage-system")
PROVISION_K8S = os.path.join(GARAGE_DIR, "aprovisionar.yaml")
GARAGE_KUSTOMIZATION = os.path.join(GARAGE_DIR, "kustomization.yaml")
GARAGE_SECRETGEN = os.path.join(GARAGE_DIR, "secret-generator.yaml")
APPPROJECTS_K8S = os.path.join(PLATFORM_ROOT, "k8s", "bootstrap", "appprojects-tenants.yaml")
ARGOCD_SECRETGEN = os.path.join(PLATFORM_ROOT, "k8s", "base", "platform", "argocd-secrets",
                                "secret-generator.yaml")
def platform_repo():
    """The platform repo's URL, read from the instance's conf.

    In v2 this was a literal with placeholders —
    `git@github.com:__GH_OWNER__/__PLATFORM_REPO__.git`— because
    aegis-org travelled INSIDE the seed and init rendered it together
    with the manifests: the program was an artifact too. With the code
    in the product that stops making sense (the product is not
    rendered) and it would besides be exactly what check 86 forbids: an
    instance baked into the code.
    """
    c = paths.read_conf()
    owner, repo = c.get("GH_OWNER"), c.get("PLATFORM_REPO")
    if not owner or not repo:
        raise SystemExit(
            f"I cannot derive the platform repo: GH_OWNER/PLATFORM_REPO is missing "
            f"from {paths.conf()} (did you run the wizard?)")
    return f"git@github.com:{owner}/{repo}.git"
MAIN_TF = os.path.join(PLATFORM_ROOT, "tofu", "envs", "cloudflare-tunnel", "main.tf")
JENKINS_VALUES = os.path.join(PLATFORM_ROOT, "k8s", "base", "platform", "jenkins", "values.yaml")
VMAGENT_VALUES = os.path.join(PLATFORM_ROOT, "k8s", "base", "observability", "vmagent", "values.yaml")
JENKINSFILE_TPL = os.path.join(PLATFORM_ROOT, "docs", "protocols", "templates", "Jenkinsfile.app")
BASE_CONSUMERS = os.path.join(PLATFORM_ROOT, "base-images", "consumers.txt")
STAGING_DIR = os.path.join(PLATFORM_ROOT, ".aegis-app")

CONTRACT_VERSION = 1
VALID_NAME = re.compile(r"^[a-z][a-z0-9-]{2,29}$")
TYPES = {"estatico", "http", "postgres", "worker"}
# The ones that come out of an image somebody COMPILES AND SIGNS. The
# rest are provided by the platform (postgres comes from services.yaml),
# and that difference is what decides whether the contract needs a
# `repo`.
TYPES_WITH_IMAGE = {"estatico", "http", "worker"}
# `internet` came in on 2026-08-21 with org-shop: its API talks to
# Webpay (Transbank) and it was the FIRST tenant app that needs to reach
# the outside world — the vocabulary had no way of saying it and the
# symptom was an ECONNREFUSED from the CNI halfway through a purchase.
# It does not demand a block at the organization level (unlike
# bucket/ai/postgres): it is a capability of the service, not a resource
# the platform provides.
USES = {"ai", "bucket", "postgres", "internet"}

# The port on which the platform EXPECTS each type that does not declare
# one. It is not a convenient default: it is part of the contract. A
# front listening somewhere else starts up fine and never receives
# traffic — a silent failure, which is the worst kind.
STATIC_PORT = 8080


def _type_coherence(n, kind, s):
    """A `tipo` that restricts nothing is not a type, it is a label.

    Up to here the field was validated against a list and afterwards
    nobody consumed it: a public `worker` on port 443 could be declared
    and the generator said yes. These rules are what make the type mean
    something.
    """
    has = lambda k: s.get(k) is not None

    if kind == "estatico":
        # NO `usa`, and this is the only rule here that is about
        # SECURITY and not about coherence: a static front has no server
        # side in which to keep a credential. Everything handed to it
        # ends up published in the bundle the browser downloads.
        # Whatever needs to talk to the AI or to the bucket goes behind
        # an `http`, which is exactly the BFF's role.
        if s.get("usa"):
            raise Invalid(
                f"service {n!r} is estatico and declares usa: {s['usa']}.\n"
                f"  A static front has NOWHERE to keep a credential: whatever is\n"
                f"  handed to it travels to the browser. Whatever needs AI or bucket\n"
                f"  goes behind an `http` service (the BFF pattern).")
        if has("puerto"):
            raise Invalid(
                f"service {n!r} is estatico and declares puerto {s['puerto']}.\n"
                f"  Static ones are served by the platform on {STATIC_PORT}, which is the\n"
                f"  only one the edge's NetworkPolicy lets in.")
        if not has("publico"):
            raise Invalid(
                f"service {n!r} is estatico and does not declare `publico`.\n"
                f"  A front nobody can visit is not a front.")

    elif kind == "http":
        if not has("puerto"):
            raise Invalid(
                f"service {n!r} is http and does not declare `puerto`.\n"
                f"  The port is part of the contract: without it the platform does not\n"
                f"  know where to send the traffic and the failure would be silent.")

    elif kind == "worker":
        # A worker does not listen. If it had a port or a public path it
        # would be something else and it would have to be called by its
        # own name.
        for field in ("puerto", "publico"):
            if has(field):
                raise Invalid(
                    f"service {n!r} is worker and declares `{field}`.\n"
                    f"  A worker does not listen: it processes. If it needs to serve\n"
                    f"  requests, the type is `http`.")

    elif kind == "postgres":
        # It is provided by the PLATFORM: signed image, disk, credential
        # and policies come out of services.yaml, not out of a tenant's
        # repo.
        if has("repo"):
            raise Invalid(
                f"service {n!r} is postgres and declares `repo`.\n"
                f"  Databases are provided by the platform (services.yaml): signed\n"
                f"  image, disk and credential. A repo here means something else was\n"
                f"  intended.")
        for field in ("puerto", "publico"):
            if has(field):
                raise Invalid(
                    f"service {n!r} is postgres and declares `{field}`.\n"
                    f"  The port is fixed by the platform and a database is NEVER\n"
                    f"  published: it is reached from inside the namespace and from\n"
                    f"  nowhere else.")
        if s.get("usa"):
            raise Invalid(
                f"service {n!r} is postgres and declares usa: {s['usa']}.\n"
                f"  A database does not consume services: it lends them.")


def capabilities():
    """The capabilities that can be asked for are the ones ai/routes.yaml
    knows how to serve TODAY, not a list written here.

    The previous version had the set by hand and it included `embeddings`
    and `transcripcion`, which still have no engine. A contract that
    asked for them passed this validation and afterwards kept the gateway
    from STARTING — the generator gave its blessing to something the
    platform cannot deliver, which is the most expensive way of being
    wrong: the error shows up far away from the cause."""
    r = yaml.safe_load(open(ROUTES, encoding="utf-8")) or {}
    return set((r.get("capacidades") or {}).keys())

red = "\033[31m"; green = "\033[32m"; yellow = "\033[33m"; grey = "\033[90m"; off = "\033[0m"
if not sys.stdout.isatty():
    red = green = yellow = grey = off = ""


class Invalid(Exception):
    """The contract is no good. It aborts BEFORE writing anything (rule I5)."""


# ──────────────────────────────────────────────────────────────────
# Validation
#
# Unknown fields are an ERROR, they are not ignored. A typo in
# `almacenamineto:` has to fail loudly; ignoring it would switch the
# bucket off without anybody finding out, which is the worst way to
# fail.
# ──────────────────────────────────────────────────────────────────

def _only(d, allowed, where):
    extra = set(d) - allowed
    if extra:
        raise Invalid(f"{where}: unknown field(s): {', '.join(sorted(extra))}")


def _require(d, field, where):
    if field not in d:
        raise Invalid(f"{where}: the mandatory field '{field}' is missing")
    return d[field]


def validate(c, plans):
    if not isinstance(c, dict):
        raise Invalid("the contract is not a YAML mapping")
    _only(c, {"version", "organizacion", "dominio", "cuota", "repo",
              "almacenamiento", "ai", "servicios"}, "contract")

    # The version is MANDATORY and the unknown is rejected. A contract
    # with no version is NOT "v1 by default": it is an error. Assuming
    # the version is how an old contract ends up rendered with new rules.
    v = _require(c, "version", "contract")
    if v != CONTRACT_VERSION:
        raise Invalid(f"version {v!r} unknown (this tool speaks v{CONTRACT_VERSION})")

    name = _require(c, "organizacion", "contract")
    if not isinstance(name, str) or not VALID_NAME.match(name):
        raise Invalid(f"organizacion {name!r}: it must be [a-z][a-z0-9-]{{2,29}}")

    # `dominio` is NOT mandatory, and the real check is further down: it
    # is needed if —and only if— some service is `publico`. A hostname
    # exists in order to serve something; an organization that only has
    # a database and a bucket has nobody to expose. Demanding it anyway
    # forced people to invent a name, and an invented CNAME is a CNAME
    # nobody later knows why is there.

    quota = _require(c, "cuota", "contract")
    if quota not in plans["cuota"]:
        raise Invalid(f"cuota {quota!r} does not exist. There is: {', '.join(sorted(plans['cuota']))}\n"
                      f"  If a new one is needed, A PLAN IS ADDED to plans.yaml.\n"
                      f"  Numbers do not go in the contract (§3 of the protocol).")

    storage = c.get("almacenamiento") or {}
    _only(storage, {"bucket"}, "almacenamiento")
    # The VALUE, not just the key. Anything that is not a boolean is
    # read as false further on (`storage.get("bucket")` for truth), so
    # `bucket: {}` validates fine and means "no bucket" IN SILENCE:
    # no Job, no credential, no error. It happened to me while writing
    # the generator's test on 2026-08-04.
    if "bucket" in storage and not isinstance(storage["bucket"], bool):
        raise Invalid(
            f"almacenamiento.bucket: true or false was expected, not {storage['bucket']!r}\n"
            f"  The bucket is not configured from the contract: its name, its\n"
            f"  endpoint and its key are decided by the platform. Here all that is\n"
            f"  said is whether the organization wants one.")

    ai = c.get("ai")
    if ai is not None:
        _only(ai, {"plan", "tareas"}, "ai")
        plan = _require(ai, "plan", "ai")
        if plan not in plans["ai"]:
            raise Invalid(f"ai.plan {plan!r} does not exist. There is: {', '.join(sorted(plans['ai']))}")
        for t in ai.get("tareas") or []:
            _only(t, {"nombre", "capacidad", "prompt"}, "ai.tareas[]")
            _require(t, "nombre", "ai.tareas[]")
            cap = _require(t, "capacidad", "ai.tareas[]")
            available = capabilities()
            if cap not in available:
                raise Invalid(
                    f"capacidad {cap!r} is not served today. There is: {', '.join(sorted(available))}\n"
                    f"  An organization names CAPABILITIES, never models nor\n"
                    f"  providers (§5 of the protocol). If you see a model name\n"
                    f"  here, the contract is badly written.\n"
                    f"  If the capability is the right one and the engine is missing, it\n"
                    f"  is added to ai/routes.yaml AFTER implementing it — not before.")

    services = _require(c, "servicios", "contract")
    if not services:
        raise Invalid("contract: 'servicios' empty — an organization with no services is nothing")
    seen = set()
    has_postgres = any(s.get("tipo") == "postgres" for s in services)
    for s in services:
        # NO `version`. It was allowed and nobody consumed it: a
        # contract could declare `version: "17"` on its database and the
        # generator ignored it, leaving whoever wrote it believing they
        # had pinned something. The version of a service provided by the
        # platform is decided by services.yaml, and that is what it is
        # for.
        _only(s, {"nombre", "tipo", "repo", "puerto", "publico", "usa"}, "servicios[]")
        n = _require(s, "nombre", "servicios[]")
        if n in seen:
            raise Invalid(f"service {n!r} declared twice")
        seen.add(n)
        kind = _require(s, "tipo", "servicios[]")
        if kind not in TYPES:
            raise Invalid(f"service {n!r}: tipo {kind!r} unknown. There is: {', '.join(sorted(TYPES))}")
        _type_coherence(n, kind, s)
        for u in s.get("usa") or []:
            if u not in USES:
                raise Invalid(f"service {n!r}: usa {u!r} unknown ({' | '.join(sorted(USES))})")
            if u == "bucket" and not storage.get("bucket"):
                raise Invalid(f"service {n!r} declares usa:[bucket] but the organization "
                              f"did not ask for almacenamiento.bucket")
            if u == "ai" and ai is None:
                raise Invalid(f"service {n!r} declares usa:[ai] but the organization "
                              f"has no ai section")
            if u == "postgres" and not has_postgres:
                raise Invalid(f"service {n!r} declares usa:[postgres] but the organization "
                              f"did not declare any service of type postgres")

    # ── repo: only if some service IS BUILT ───────────────────────
    #
    # It used to say "with no repo there is nothing to deploy", and that
    # was true when every service came out of a build. Since #41 it
    # stopped being true: a `postgres` is provided by the platform from
    # services.yaml, and a bucket is provisioned by a Job. A contract of
    # pure infrastructure was rejected for a reason that was no longer
    # true.
    #
    # And it blocked the natural order, which is the reverse of the one
    # it demanded: first the database and the bucket, then the app that
    # uses them. It forced people to invent an empty repo just to be
    # able to start.
    built = [s for s in services if s["tipo"] in TYPES_WITH_IMAGE]
    if built and not c.get("repo") and not any(s.get("repo") for s in built):
        which = ", ".join(f"{s['nombre']} ({s['tipo']})" for s in built)
        raise Invalid(
            f"'repo' is required —at the organization level or in the service— because "
            f"these services are BUILT: {which}.\n"
            f"  The types {', '.join(sorted(TYPES_WITH_IMAGE))} come out of an image somebody\n"
            f"  has to compile and sign. `postgres` does not: it is provided by the\n"
            f"  platform from services.yaml, and for that no repo is needed.")

    # ── dominio: only if something is PUBLIC ──────────────────────
    public = [s["nombre"] for s in services if s.get("publico")]
    if public and not c.get("dominio"):
        raise Invalid(
            f"'dominio' is required: {', '.join(public)} declare(s) `publico` and without a\n"
            f"  hostname nobody can arrive. The edge's CNAME is DERIVED from this\n"
            f"  field (§2 of the edge protocol); without it the service starts up\n"
            f"  fine and never receives traffic, which is the worst kind of failure.")
    if c.get("dominio") and not public:
        raise Invalid(
            f"the contract declares dominio {c['dominio']!r} but no service is\n"
            f"  `publico`. That CNAME would point at a site that does not exist. If the\n"
            f"  app is not there yet, the domain is added together with it.")

    # ── two services cannot claim the same path ───────────────────
    # Ever since the IngressRoute is DERIVED from these fields (#54), a
    # repeated `publico` is not a documentation slip: they are two
    # traefik rules with the same match. Traefik picks one and the other
    # never receives traffic, with no error anywhere.
    claimed = {}
    for s in services:
        if not s.get("publico"):
            continue
        if (owner := claimed.get(s["publico"])) is not None:
            raise Invalid(
                f"{owner!r} and {s['nombre']!r} declare the same `publico: "
                f"{s['publico']}'.\n"
                f"  ONE routing rule per service comes out of that: with the same path,\n"
                f"  traefik keeps one and the other never receives traffic. There is\n"
                f"  no error to give it away — the app starts up healthy and stays mute.")
        claimed[s["publico"]] = s["nombre"]
    return c


# ──────────────────────────────────────────────────────────────────
# Render
#
# Text templates and not yaml.dump() on purpose: the comments that
# explain WHY each thing is the way it is are worth as much as the YAML,
# and yaml.dump erases them. The cost is writing the templates by hand;
# the benefit is that the generated file can be READ.
# ──────────────────────────────────────────────────────────────────

# The header of what is derived and the rest of the sentinels live in
# lib/aegis/markers.py: the one that WRITES them and the one that
# RECOGNISES them have to use the same string, and in v2 it was copied
# eight times (class B of the register, rule 5.6).
HEADER = markers.HEADER


def _hash(text):
    """Fingerprint of the contract AND OF THE GENERATOR that renders it.

    Including the generator is not over-caution: without it, changing a
    template here leaves the hash intact while the output changes, and
    guard I3 reads that as "somebody edited the file by hand" and
    refuses to write. It happened on 2026-08-03 when the
    ignoreDifferences was taken out: the guard blocked its own change.

    With the generator inside, touching a template changes the hash of
    ALL the generated files —which is the truth: they are different— and
    the rewrite proceeds. What I3 still catches is what it has to catch:
    same contract and same generator, different content = a human hand.
    """
    mine = open(os.path.abspath(__file__), "rb").read()
    return hashlib.sha256(text.encode() + b"\x00" + mine).hexdigest()[:16]


def render_bundle(c, plans, h):
    org = c["organizacion"]
    ns = f"org-{org}"
    quota = plans["cuota"][c["cuota"]]
    lines = [HEADER.format(org=org, hash=h)]
    lines.append(f"""\
#
# Namespace, quota and the identity images are pulled with.
---
apiVersion: v1
kind: Namespace
metadata:
  name: {ns}
  labels:
    # THIS LABEL IS THE SECURITY BOUNDARY, not a classification. It is
    # what puts the namespace inside the scope of Kyverno's webhook:
    # without it, unsigned images would get in here and NOTHING would
    # warn. It happened on 2026-07-27 with org-portafolio and
    # org-ecommerce, which were born outside the scope and admitted a
    # public busybox.
    aegis.dev/part-of: aegis-tenants
    pod-security.kubernetes.io/enforce: restricted
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: {ns}-quota
  namespace: {ns}
spec:
  # Plan `{c["cuota"]}` from plans.yaml. The numbers are NOT edited
  # here: you change the plan, or you change the contract's `cuota`.
  hard:""")
    for k in ("requests.cpu", "requests.memory", "limits.cpu", "limits.memory",
              "pods", "persistentvolumeclaims", "requests.storage"):
        # By hand and not with yaml.safe_dump: for a lone scalar,
        # safe_dump emits the end-of-document marker `...`, which split
        # the stream in the middle of the ResourceQuota. A K8s quantity
        # ALWAYS goes in quotes — `2` unquoted is an integer and the
        # apiserver rejects the object.
        lines.append(f'    {k}: "{quota[k]}"')
    lines.append(f"""\
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: {ns}
# The tenant does NOT use the K8s API: the app runs, it is not
# administered. A compromised pod cannot talk to the apiserver. An app
# that DOES need the API asks for it at pod level, where it stays
# visible in its own manifest.
automountServiceAccountToken: false
imagePullSecrets:
  # Pattern A: the platform provides the HOW of pulling; apps do not
  # declare registry credentials.
  - name: regcred-internal
""")
    return "\n".join(lines)


def render_data(c, h):
    """The services the PLATFORM provides, not a tenant's repo.

    Today only postgres. It comes out of services.yaml, which is the
    table of "what each type is fulfilled with" — the same role
    ai/routes.yaml plays for the AI capabilities.
    """
    dbs = [s for s in c["servicios"] if s["tipo"] == "postgres"]
    if not dbs:
        return None

    org = c["organizacion"]
    ns = f"org-{org}"
    cat = yaml.safe_load(open(SERVICES, encoding="utf-8"))
    t = cat["tipos"]["postgres"]
    image = f"{cat['registro']}/{t['imagen']}@{t['digest']}"

    parts = [HEADER.format(org=org, hash=h), f"""\
#
# The databases of this organization.
#
# ONE DATABASE PER ORGANIZATION, never shared. A `DROP` on one cannot
# touch its neighbour, and the RAM cost of an idle postgres is
# negligible next to that guarantee.
#
# The image goes BY DIGEST (services.yaml). With a tag, Kyverno would
# append the digest on admission and desired != live forever; the
# obvious way out —ignoreDifferences on the image— TURNS OFF auto-sync.
# With the digest in git the mutation is a no-op. That is finding #36."""]

    for s in sorted(dbs, key=lambda x: x["nombre"]):
        n = s["nombre"]
        app = f"{org}-{n}"
        parts.append(f"""\
---
# Headless: every replica gets DNS of its own. With a single replica
# it makes no difference, but a plain Service in front of a StatefulSet
# is the kind of shortcut nobody dares to change later.
apiVersion: v1
kind: Service
metadata:
  name: {n}
  namespace: {ns}
  labels: {{app: {app}, aegis.dev/component: datos}}
spec:
  clusterIP: None
  selector: {{app: {app}}}
  ports:
    - {{name: postgres, port: {t['puerto']}, targetPort: {t['puerto']}}}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {n}
  namespace: {ns}
  labels: {{app: {app}, aegis.dev/component: datos}}
spec:
  serviceName: {n}
  # ONE replica. Postgres is not replicated by setting replicas: 2 —
  # that gives two different databases fighting over the same disk.
  # Real high availability is another decision and another operator.
  replicas: 1
  selector:
    matchLabels: {{app: {app}}}
  template:
    metadata:
      labels: {{app: {app}, aegis.dev/component: datos}}
    spec:
      # The tenant does not talk to the Kubernetes API.
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: {t['uid']}
        runAsGroup: {t['uid']}
        # fsGroup so the PVC is born writable by that UID: without
        # this, start-up dies on "permission denied" over PGDATA and
        # the message looks nothing like the cause.
        fsGroup: {t['uid']}
        seccompProfile: {{type: RuntimeDefault}}
      containers:
        - name: postgres
          image: {image}
          ports:
            - {{name: postgres, containerPort: {t['puerto']}}}
          env:
            # The credential NEVER in the manifest: it comes from the
            # SOPS-encrypted secret that secret-generator.yaml lists.
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef: {{name: {n}-credenciales, key: password}}
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef: {{name: {n}-credenciales, key: usuario}}
            - name: POSTGRES_DB
              value: {org}
            # PGDATA in a SUBDIRECTORY of the volume, not at the root:
            # an ext4's `lost+found` makes initdb refuse to start over
            # a directory that is "not empty".
            - {{name: PGDATA, value: /var/lib/postgresql/data/pgdata}}
          volumeMounts:
            - {{name: datos, mountPath: /var/lib/postgresql/data}}
            # /tmp and /run writable because the root filesystem is
            # not: postgres needs the unix socket and temporary files.
            - {{name: tmp, mountPath: /tmp}}
            - {{name: run, mountPath: /var/run/postgresql}}
          # `pg_isready` and not a generic TCP check: the port opens
          # before the database accepts queries, and a probe that only
          # looks at the port calls ready a service that still refuses
          # everything.
          readinessProbe:
            exec: {{command: ["pg_isready", "-U", "$(POSTGRES_USER)", "-d", "{org}"]}}
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            exec: {{command: ["pg_isready", "-U", "$(POSTGRES_USER)", "-d", "{org}"]}}
            initialDelaySeconds: 30
            periodSeconds: 20
            failureThreshold: 3
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {{drop: [ALL]}}
            readOnlyRootFilesystem: true
          resources:
            requests: {{cpu: 100m, memory: 256Mi}}
            limits: {{cpu: "1", memory: 1Gi}}
      volumes:
        - name: tmp
          emptyDir: {{}}
        - name: run
          emptyDir: {{}}
  volumeClaimTemplates:
    # apiVersion, kind and volumeMode are filled in by the apiserver
    # by default. They go DECLARED: without them desired != live on
    # every refresh and the StatefulSet stays OutOfSync FOREVER.
    # Measured with Garage on 2026-08-04, before the first generated
    # postgres existed.
    #
    # The obvious way out —widening ignoreDifferences to the whole
    # volumeClaimTemplate— turns off auto-sync and, on the way, hides a
    # real change of size or of accessMode (#36). Declaring a default
    # is free; ignoring one is paid for.
    - apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: datos
      spec:
        accessModes: [ReadWriteOnce]
        volumeMode: Filesystem
        resources:
          requests: {{storage: {t['disco']}}}""")
    return "\n".join(parts) + "\n"


def repos_of(c):
    """The repos of a contract, mapped to the name of their Application.

    ONE single source for the two things that depend on this list: the
    Applications that get generated, and the `sourceRepos` of the
    AppProject that fences them in. Computing it twice is how they drift
    apart — and the way it would fail is ugly: the App exists, the
    project does not let it read its own repo, and the error talks about
    permissions and not about the line that was missing.

    The repo can be in the contract (one for the whole organization) or
    in a service (a repo of its own). The validator accepts both, so
    both have to reach the project.
    """
    org = c["organizacion"]
    repos = {}
    if c.get("repo"):
        repos[c["repo"]] = org
    for s in c.get("servicios") or []:
        if s.get("repo"):
            repos.setdefault(s["repo"], f"{org}-{s['nombre']}")
    return repos


def render_apps(c, h):
    """One ArgoCD Application per declared repo.

    Services that share a repo share an Application: the repo brings its
    own kustomize overlay with all its manifests. Two Applications over
    the same object fight over it and leave the app OutOfSync forever —
    one resource, one owner.
    """
    org = c["organizacion"]
    ns = f"org-{org}"
    repos = repos_of(c)

    # With no repos there are no Applications, and then there is no
    # file. Returning just the header produces a YAML with no objects,
    # which kustomize accepts and `kubectl apply` rejects with "no
    # objects passed to apply".
    if not repos:
        return None

    parts = [HEADER.format(org=org, hash=h), """\
#
# The Applications of this organization.
#
# They live here, WITH their organization, and not in argocd-apps/.
# Declaring them on both sides makes two Applications fight over the
# same object and leaves the root App permanently OutOfSync."""]
    for repo, name in sorted(repos.items()):
        parts.append(f"""\
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  # The name of the Application. Until #59 it had to match the Image
  # Updater's namePattern; that component was withdrawn —the digest is
  # written by the pipeline itself since #36/#37— so the name no longer
  # couples with anything on the platform.
  name: {name}
  namespace: argocd
  labels: {{aegis.dev/part-of: aegis-tenants}}
spec:
  # THIS organization's project: it can only read from its repo and
  # can only write in its namespace. cluster-scoped empty.
  project: aegis-tenant-{org}
  source:
    repoURL: {repo}
    targetRevision: main
    path: k8s/overlays/dev
  destination: {{server: https://kubernetes.default.svc, namespace: {ns}}}
  syncPolicy:
    automated: {{selfHeal: true}}
    syncOptions: [ServerSideApply=true]
  # NO ignoreDifferences on the image, and that is deliberate.
  #
  # Having it was the obvious answer to Kyverno rewriting the image to
  # append the verified digest. But it TURNED OFF AUTO-SYNC: if the
  # only difference between git and the cluster is the image, and the
  # image is ignored, ArgoCD sees nothing to do and nothing gets
  # deployed. The app stays green and still. Measured on 2026-08-03
  # (#36): 4 syncs in 8 days, all of them structural changes.
  #
  # The fix is not to ignore the drift: it is NOT TO PRODUCE IT. The
  # pipeline writes the DIGEST into git (the `desplegar` stage), and
  # with that Kyverno's mutation is a no-op —verified on admission,
  # input identical to output— and there is nothing left to ignore.
  #
  # If an organization goes OutOfSync over the image again, it means
  # its pipeline is writing a TAG. The fix goes there, not here.""")
    return "\n".join(parts) + "\n"


def render_netpol(c, h):
    org = c["organizacion"]
    ns = f"org-{org}"
    parts = [HEADER.format(org=org, hash=h), f"""\
#
# Network isolation. EVERYTHING denied except what the contract
# granted.
#
# What a service does not declare in `usa:`, it cannot reach. Not by
# convention nor by code review: because the kernel does not allow it.
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: {ns}
spec:
  podSelector: {{}}
  policyTypes: [Ingress, Egress]
---
# Ingress ONLY from the edge, and only to 8080. The port is part of
# the contract: an app listening somewhere else starts up fine and
# never receives traffic — a silent failure.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-edge-ingress
  namespace: {ns}
spec:
  podSelector: {{}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: {{kubernetes.io/metadata.name: infra-edge}}
      ports:
        - {{protocol: TCP, port: 8080}}
---
# Between pods of the SAME organization it is allowed: a front end
# talking to its own backend is the normal case, and forcing it to be
# declared one by one only produces policies nobody maintains.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intra-namespace
  namespace: {ns}
spec:
  podSelector: {{}}
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - podSelector: {{}}
  egress:
    - to:
        - podSelector: {{}}
---
# DNS. Without this nothing resolves and the symptom looks nothing
# like the cause.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: {ns}
spec:
  podSelector: {{}}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: {{kubernetes.io/metadata.name: kube-system}}
      ports:
        - {{protocol: UDP, port: 53}}
        - {{protocol: TCP, port: 53}}"""]

    for s in sorted(c["servicios"], key=lambda x: x["nombre"]):
        label = f"{org}-{s['nombre']}"
        for u in sorted(s.get("usa") or []):
            if u == "ai":
                parts.append(f"""\
---
# {s['nombre']} -> AI gateway, INTERNAL DOOR (8081).
#
# The internal door and the public one are different PORTS, not routes:
# that way the separation is imposed by the kernel and not by an `if`
# in the code. A tenant pod cannot reach the public door, nor forge
# client headers.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-{s['nombre']}-a-ai-gateway
  namespace: {ns}
spec:
  podSelector:
    matchLabels: {{app: {label}}}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: {{kubernetes.io/metadata.name: ai-system}}
          podSelector:
            matchLabels: {{app: ai-gateway}}
      ports:
        - {{protocol: TCP, port: 8081}}""")
            elif u == "postgres":
                # Explicit egress even though `allow-intra-namespace`
                # would already allow it: this policy does not ADD
                # permission, it DOCUMENTS the dependency. The day
                # intra-namespace gets closed —which is where it should
                # be heading— what the contract declares is what will go
                # on working.
                parts.append(f"""\
---
# {s['nombre']} -> the organization's database.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-{s['nombre']}-a-postgres
  namespace: {ns}
spec:
  podSelector:
    matchLabels: {{app: {label}}}
  policyTypes: [Egress]
  egress:
    - to:
        - podSelector:
            matchLabels: {{aegis.dev/component: datos}}
      ports:
        - {{protocol: TCP, port: 5432}}""")
            elif u == "bucket":
                parts.append(f"""\
---
# {s['nombre']} -> shared S3 storage (Garage).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-{s['nombre']}-a-garage
  namespace: {ns}
spec:
  podSelector:
    matchLabels: {{app: {label}}}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: {{kubernetes.io/metadata.name: garage-system}}
      ports:
        - {{protocol: TCP, port: 3900}}""")
            elif u == "internet":
                parts.append(f"""\
---
# {s['nombre']} -> internet, ONLY 443 and ONLY outside the private
# ranges.
#
# Born with org-shop (2026-08-21): the payment gateway lives outside
# and no other use covered it. Two deliberate cuts:
#   - port 443 only: what a tenant app has to speak to the world is
#     HTTPS; opening more is opening just in case.
#   - except on the private ranges: without it, «internet» would also
#     be a pass to the whole cluster by pod/service IP, skipping every
#     policy above. The kernel knows nothing about intentions.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-{s['nombre']}-a-internet
  namespace: {ns}
spec:
  podSelector:
    matchLabels: {{app: {label}}}
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]
      ports:
        - {{protocol: TCP, port: 443}}""")
    return "\n".join(parts) + "\n"


def render_routes(c, h):
    """The organization's IngressRoute, derived from the contract.

    Until #54 each app's repo wrote this by hand, repeating what the
    contract already said (`dominio` + `publico`). Two reasons for
    bringing it here, and the second weighs more than the first:

    1. If the two copies disagree, the failure mode is the worst one:
       the CNAME exists, the network allows it, the pod runs, and the
       visitor receives a 404. Nothing is down and no check turns red.

    2. ISOLATION. An AppProject can only filter by *kind*, never by the
       value of a field, so as long as the tenant can create
       IngressRoutes it can claim another organization's `Host`.
       MEASURED on 2026-08-06: org-blog claimed a hostname, org-ejemplo
       claimed THE SAME one, both were admitted without a complaint and
       traefik ended up serving org-ejemplo's. The legitimate owner has
       no defence. With the routing here, the kind goes into the tenant
       project's blacklist and the theft stops being expressible.

    In exchange, the platform IMPOSES the naming convention: the Service
    of a service `X` is called `<org>-X` and listens on 8080 — the same
    8080 that allow-edge-ingress opens, so that there is ONE number in
    the whole system and not one per layer.

    Since #81/#90 it also emits the edge's THREE middlewares and hooks
    them onto every route. They go in the organization's namespace and
    not in infra-edge because traefik runs WITHOUT `allowCrossNamespace`
    (measured in its args on 2026-08-13): a cross-namespace reference
    does not fail loudly — it is ignored, and the route is left with no
    protection and everything green.
    """
    org = c["organizacion"]
    ns = f"org-{org}"
    if not c.get("dominio"):
        return None
    # The validator already guarantees that dominio and `publico` go
    # together; this is only so as not to depend on that order from here.
    public_svcs = [s for s in c["servicios"] if s.get("publico")]
    if not public_svcs:
        return None

    # From the MOST specific to the least: traefik evaluates in order,
    # and a bare Host rule would capture /api before anybody looked at
    # it. Sorting by descending length leaves `/` at the end by
    # construction, with no special case for somebody to have to
    # remember later.
    public_svcs.sort(key=lambda s: (-len(s["publico"]), s["nombre"]))

    parts = [HEADER.format(org=org, hash=h), f"""\
#
# The routing of this organization — DERIVED from `dominio` and from
# the contract's `publico:` entries. The app's repo no longer writes
# it: it cannot, IngressRoute sits in its project's
# namespaceResourceBlacklist.
#
# ── THE THREE EDGE MIDDLEWARES (#81, #90) ─────────────────────────
#
# Until 2026-08-13 the cluster had ZERO middlewares and the public
# sites did not send a single security header: the only thing coming
# back was `server: cloudflare`. With demos open to the internet that
# stops being cosmetic.
#
# They go in THIS namespace and not in infra-edge: traefik runs without
# `allowCrossNamespace`, so a cross-namespace reference does not blow
# up — it is ignored in silence and the route is left bare, all green.
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: {org}-cabeceras
  namespace: {ns}
  labels: {{aegis.dev/part-of: aegis-organizaciones}}
spec:
  headers:
    # forceSTSHeader is MANDATORY here and not a preference: TLS is
    # terminated by Cloudflare, so traefik sees plain HTTP and without
    # this it would NEVER emit STS. The header would come out absent
    # and the check would say «configured» — Disease E.
    forceSTSHeader: true
    stsSeconds: 15552000            # 180 days
    stsIncludeSubdomains: false     # there are subdomains we do not own
    # no `preload`: getting into the browsers' preload list is
    # practically irreversible, and this is a portfolio still in
    # development.
    contentTypeNosniff: true
    browserXssFilter: false         # obsolete, with bugs of its own
    referrerPolicy: strict-origin-when-cross-origin
    # frame-ancestors is the REAL defence against clickjacking; the
    # X-Frame-Options below is for the old browsers that do not look at
    # CSP. Measured: the 4 sites serve ZERO iframes, so 'none' breaks
    # nothing of what exists today.
    #
    # A full CSP (default-src/script-src) is NOT declared, on purpose:
    # the portfolio serves 3 inline scripts (hydration of the Astro
    # islands) and a `script-src 'self'` would kill them in the
    # browser, with no error in any log of the cluster. That is work to
    # be measured site by site; it is declared, not faked.
    contentSecurityPolicy: "frame-ancestors 'none'"
    customResponseHeaders:
      X-Frame-Options: "DENY"
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: {org}-ritmo
  namespace: {ns}
  labels: {{aegis.dev/part-of: aegis-organizaciones}}
spec:
  rateLimit:
    # Per VISITOR, not per site. This is the part that can be got
    # wrong without noticing: traefik sees cloudflared as its peer —a
    # single pod IP— so a naive criterion would tip the whole internet
    # into one bucket and a busy visitor would starve everybody else.
    #
    # Here it works because the `web` entrypoint carries
    # forwardedHeaders.trustedIPs=10.42.0.0/16, and with that the
    # default strategy resolves the real visitor's IP. MEASURED on
    # 2026-08-13: the origin receives `XFF: 186.9.x.x, 10.42.0.206` —
    # the public IP first, cloudflared's pod IP after it.
    #
    # And it resists forgery by construction: Cloudflare APPENDS the
    # real IP at the end of whatever XFF the client sends, and traefik
    # takes the last UNTRUSTED one. Inventing entries on the left does
    # not move the result.
    average: 50                     # sustained req/s per visitor
    burst: 100                      # a page load is ~20-50
    period: 1s
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: {org}-cuerpo
  namespace: {ns}
  labels: {{aegis.dev/part-of: aegis-organizaciones}}
spec:
  buffering:
    # ONLY the request. `maxResponseBodyBytes` is absent on purpose:
    # buffering the RESPONSE would break the streaming of the AI chat
    # (SSE), and the symptom —«the chat is stuck thinking»— looks
    # nothing at all like the cause.
    maxRequestBodyBytes: 10485760   # 10 MiB
    memRequestBodyBytes: 1048576    # 1 MiB in RAM, the rest to disk
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: {org}-ruteo
  namespace: {ns}
  labels: {{aegis.dev/part-of: aegis-organizaciones}}
spec:
  # `web` AND `websecure`, both profiles, one manifest. Under
  # EDGE=cloudflare the tunnel delivers plain HTTP on `web` and nothing
  # ever reaches 443, so `websecure` is inert. Under EDGE=local there is
  # no tunnel: the host's bridge hands 443 straight to traefik, which
  # serves it with the wildcard of aegis' own internal CA (the default
  # TLSStore of k8s/base/ingress/edge-tls). Listing both is what lets the
  # SAME route serve both edges — the alternative was a placeholder in
  # every routes.yaml, which check 049 reads literally and check 003
  # would have to grow an owner for.
  entryPoints: [web, websecure]
  routes:"""]
    for s in public_svcs:
        # PathPrefix only when the path is not the root: `PathPrefix(/)`
        # matches everything and would turn the rule into a bare Host
        # written the long way.
        path = s["publico"]
        match = f"Host(`{c['dominio']}`)"
        if path != "/":
            match += f" && PathPrefix(`{path}`)"
        # The middlewares go PER ROUTE and not once per IngressRoute
        # because traefik has no «middlewares of the IngressRoute»: they
        # are declared on each rule. Repeating them here is not
        # duplication — a route without the list is a route without
        # protection.
        parts.append(f"""\
    # {s['nombre']} — `publico: {path}` in the contract
    - kind: Rule
      match: {match}
      middlewares:
        - {{name: {org}-cabeceras}}
        - {{name: {org}-ritmo}}
        - {{name: {org}-cuerpo}}
      services:
        - {{name: {org}-{s['nombre']}, port: 8080}}""")
    return "\n".join(parts) + "\n"


def render_kustomization(c, h, secrets):
    org = c["organizacion"]
    parts = [HEADER.format(org=org, hash=h), """\
#
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - bundle.yaml
  - netpol.yaml"""]
    # Conditional for the same reason as in garage-system: kustomize
    # FAILS if a listed resource does not exist on disk. Listing
    # apps.yaml when the organization has no repo yet would break the
    # whole render, and the error would point at kustomize and not at
    # the contract.
    if any(s.get("repo") for s in c["servicios"]) or c.get("repo"):
        parts.append("  - apps.yaml")
    if any(s["tipo"] == "postgres" for s in c["servicios"]):
        parts.append("  - datos.yaml")
    if c.get("dominio") and any(s.get("publico") for s in c["servicios"]):
        parts.append("  - routes.yaml")
    if secrets:
        parts.append("generators:\n  - secret-generator.yaml")
    return "\n".join(parts) + "\n"


def render_secret_generator(c, h, secrets):
    org = c["organizacion"]
    parts = [HEADER.format(org=org, hash=h), f"""\
#
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: org-{org}-secrets
  annotations:
    config.kubernetes.io/function: |
      exec: {{path: ksops}}
# EXPLICIT LIST (A7): no globs. A glob silently takes in any .enc.yaml
# that happens to land in the directory.
files:"""]
    for s in secrets:
        parts.append(f"  - {s}")
    return "\n".join(parts) + "\n"


def secrets_of(c):
    """Which secrets this organization needs, in stable order."""
    s = ["secret-regcred-internal.enc.yaml"]
    if c.get("ai") is not None:
        s.append("secret-ai-gateway-key.enc.yaml")
    if (c.get("almacenamiento") or {}).get("bucket"):
        s.append("secret-garage.enc.yaml")
    # One per database and not one per organization: two databases with
    # the same credential are one database with two names.
    for b in sorted(x["nombre"] for x in c["servicios"] if x["tipo"] == "postgres"):
        s.append(f"secret-{b}-credenciales.enc.yaml")
    return s


def render(c, plans, raw):
    h = _hash(raw)
    secrets = secrets_of(c)
    output = {
        "bundle.yaml": render_bundle(c, plans, h),
        "netpol.yaml": render_netpol(c, h),
        "kustomization.yaml": render_kustomization(c, h, secrets),
    }
    # apps.yaml ONLY if there is some repo. With no repos the file came
    # out with the header and not one object inside: `kubectl apply`
    # answers "no objects passed to apply". A generated file that
    # produces nothing is noise somebody later reads looking for why it
    # is not deploying.
    if (apps := render_apps(c, h)) is not None:
        output["apps.yaml"] = apps
    if (data := render_data(c, h)) is not None:
        output["datos.yaml"] = data
    if (routes := render_routes(c, h)) is not None:
        output["routes.yaml"] = routes
    if secrets:
        output["secret-generator.yaml"] = render_secret_generator(c, h, secrets)
    return output, secrets


# ──────────────────────────────────────────────────────────────────
# Apply
# ──────────────────────────────────────────────────────────────────

def _without_hash(t):
    return markers.without_hash(t)


def apply_contract(path, write):
    raw = open(path, encoding="utf-8").read()
    plans = yaml.safe_load(open(PLANS, encoding="utf-8"))
    c = validate(yaml.safe_load(raw), plans)
    org = c["organizacion"]
    dest = os.path.join(K8S_DIR, f"org-{org}")
    output, secrets = render(c, plans, raw)

    print(f"\norganization {green}{org}{off}  ·  contract v{c['version']}  ·  "
          f"cuota {c['cuota']}" + (f"  ·  ai {c['ai']['plan']}" if c.get("ai") else ""))
    print(f"{grey}destination: k8s/organizations/org-{org}/{off}\n")

    changes = 0
    generated = set(output)
    for name in sorted(output):
        file_path = os.path.join(dest, name)
        new = output[name]
        if not os.path.exists(file_path):
            print(f"  {green}+{off} {name}  {grey}(new){off}")
            changes += 1
            if write:
                os.makedirs(dest, exist_ok=True)
                open(file_path, "w", encoding="utf-8").write(new)
            continue
        old = open(file_path, encoding="utf-8").read()
        if old == new:
            print(f"  {grey}={off} {name}")
            continue
        # I3: if the file was edited by hand, refuse and show what
        # changed. The truth is the contract, not the file — but
        # overwriting somebody's work without showing it is worse than
        # not generating.
        if markers.is_generated(old) and _without_hash(old) != _without_hash(new):
            old_mark = [l for l in old.splitlines() if l.startswith("# hash:")]
            new_mark = [l for l in new.splitlines() if l.startswith("# hash:")]
            if old_mark == new_mark:
                print(f"  {red}!{off} {name}  {red}EDITED BY HAND{off} "
                      f"{grey}(same contract, different content){off}")
                for l in list(difflib.unified_diff(
                        old.splitlines(), new.splitlines(),
                        "on disk", "generated", lineterm=""))[:40]:
                    print(f"      {grey}{l}{off}")
                print(f"      {yellow}not overwritten. Check whether the change belongs in the contract.{off}")
                changes += 1
                continue
        print(f"  {yellow}~{off} {name}")
        changes += 1
        if write:
            open(file_path, "w", encoding="utf-8").write(new)

    # I4: convergence. What the generator no longer produces is surplus.
    if os.path.isdir(dest):
        for name in sorted(os.listdir(dest)):
            if name in generated or name.endswith(".enc.yaml"):
                continue
            print(f"  {red}-{off} {name}  {grey}(the contract no longer produces it){off}")
            changes += 1
            if write:
                os.remove(os.path.join(dest, name))

    missing = [s for s in secrets
               if not os.path.exists(os.path.join(dest, s))]
    if missing:
        print(f"\n  {yellow}secrets that are missing{off}")
        for s in missing:
            print(f"    · {s}")
        # The exact command, not "create the secrets". This generator
        # deliberately does NOT create them: it writes manifests and
        # does not handle cryptographic material, and separating the two
        # is what makes it safe to run without thinking about it.
        print(f"  {grey}they are created with:{off}  {CMD_SECRET} {path}")
        print(f"  {grey}they are created if missing and NEVER regenerated: reapplying rotates nothing{off}")

    if not changes:
        print(f"\n{green}no changes{off} — it already converges\n")
        return 0
    if write:
        print(f"\n{green}{changes} change(s) written.{off} Review the diff and commit.\n")
    else:
        print(f"\n{yellow}{changes} change(s).{off} Nothing written (this was `plan`).\n")
    return 0


# ──────────────────────────────────────────────────────────────────
# The edge
#
# tofu's `public_hostnames` is DERIVED: platform (edge.yaml) + the
# `dominio:` of ALL the contracts. Nobody edits that list by hand.
#
# The failure mode this removes is the worst of all: if a hostname is
# missing, it simply DOES NOT EXIST. No error, no alarm, nothing red —
# the cluster's IngressRoute is perfect and nobody arrives. It already
# happened with ai.__ROOT_DOMAIN__ (#35) and nearly happened with blog.
#
# ALL of orgs/*.yaml is read and not only the contract being applied:
# the list belongs to the whole instance, not to one organization.
# Applying a single one and rewriting the list with it would erase the
# rest.
# ──────────────────────────────────────────────────────────────────

HOSTNAMES_PATTERN = re.compile(r"^(\s*)public_hostnames\s*=\s*\[[^\]]*\]", re.M)


def edge_labels():
    edge = yaml.safe_load(open(EDGE, encoding="utf-8"))
    root = edge["root_domain"]
    labels = list(edge.get("platform") or [])
    from_contracts = []
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8"))
        dom = (c or {}).get("dominio")
        if not dom:
            continue
        if not dom.endswith("." + root):
            raise Invalid(
                f"{name}: dominio {dom!r} is not under {root!r}.\n"
                f"  The edge can only create CNAMEs inside its own zone. A domain\n"
                f"  from another zone needs another decision, not one more entry.")
        from_contracts.append(dom[: -(len(root) + 1)])
    # Stable order: platform first (in the declared order), then the
    # tenants alphabetically. Without this the diff changes according to
    # the filesystem and breaks I1.
    for e in sorted(from_contracts):
        if e not in labels:
            labels.append(e)
    return labels


def apply_edge(write):
    labels = edge_labels()
    line = 'public_hostnames = [' + ", ".join(f'"{e}"' for e in labels) + "]"
    tf = open(MAIN_TF, encoding="utf-8").read()
    m = HOSTNAMES_PATTERN.search(tf)
    if not m:
        raise Invalid(f"I could not find `public_hostnames = [...]` in {MAIN_TF}")
    new = HOSTNAMES_PATTERN.sub(lambda mm: mm.group(1) + line, tf, count=1)
    print(f"\nedge  {grey}(tofu/envs/cloudflare-tunnel/main.tf){off}")
    if new == tf:
        print(f"  {grey}={off} public_hostnames  {grey}{len(labels)} hostnames{off}")
        return 0
    print(f"  {yellow}~{off} public_hostnames -> {', '.join(labels)}")
    if write:
        open(MAIN_TF, "w", encoding="utf-8").write(new)
        # It does NOT say "the job does it by itself". It used to, and
        # since #46 that is false: the state travels encrypted with the
        # age key and the age key does not enter CI, so CI cannot apply.
        # An instruction that promises something happens by itself is
        # worse than not having it — the hostname does not exist and
        # nobody is waiting for it.
        print(f"  {yellow}the CNAME does not exist until you run this:{off}")
        print(f"  {grey}  SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key \\{off}")
        print(f"  {grey}    tofu/tofu-apply.sh -chdir=envs/cloudflare-tunnel apply{off}")
        print(f"  {grey}  (afterwards, commit the re-encrypted state){off}")
    return 0


# ──────────────────────────────────────────────────────────────────
# Delete
#
# The protocol's weakest point, and it is better said than discovered:
# `prune` is OMITTED across the whole platform (A19). Taking files out
# of git takes NOTHING out of the cluster. A `delete` that only touched
# git would leave the namespace, its data and its quota running, and the
# organization would look deleted.
#
# That is why they are two separate steps, and in this order:
#
#   1. the GIT part, which is reversible: the generated files are taken
#      out and the derivations (edge, routes) stop naming it on their own.
#   2. the CLUSTER part, which is NOT reversible: the commands are
#      PRINTED and not executed.
#
# Step 2 is not automated because deleting a namespace takes the data
# with it, and that cannot happen through a command run with a
# mistyped name. The day there is prune with confirmation, it may
# change.
# ──────────────────────────────────────────────────────────────────


def delete_org(name, write):
    if not VALID_NAME.match(name):
        raise Invalid(f"{name!r} is not a valid organization name")

    contract_path = None
    for ext in (".yaml", ".yml"):
        p = os.path.join(ORGS_DIR, name + ext)
        if os.path.exists(p):
            contract_path = p
            break
    dest = os.path.join(K8S_DIR, f"org-{name}")
    if contract_path is None and not os.path.isdir(dest):
        raise Invalid(
            f"neither orgs/{name}.yaml nor k8s/organizations/org-{name}/ exists.\n"
            f"  Nothing to delete. If the organization is alive in the cluster but\n"
            f"  not in git, it is an orphan: `{CMD_CHECK}` reports it.")
    # The contract is read NOW, before step 1 deletes it from disk: step
    # 2 needs it in order to name the Applications.
    contract = (yaml.safe_load(open(contract_path, encoding="utf-8")) or {}) \
        if contract_path else None

    ns = f"org-{name}"
    print(f"\norganization {red}{name}{off}  ·  {grey}delete{off}")

    # ── step 1: git ────────────────────────────────────────────────
    print(f"\n{grey}1) in git (reversible){off}")
    to_remove = []
    if contract_path:
        to_remove.append(contract_path)
    if os.path.isdir(dest):
        for f in sorted(os.listdir(dest)):
            to_remove.append(os.path.join(dest, f))

    encrypted = [q for q in to_remove if q.endswith(".enc.yaml")]
    for q in to_remove:
        rel = os.path.relpath(q, PLATFORM_ROOT)
        mark = f"  {red}-{off}"
        extra = f"  {yellow}(encrypted secret){off}" if q.endswith(".enc.yaml") else ""
        print(f"{mark} {rel}{extra}")

    if encrypted:
        print(f"\n  {yellow}MIND the .enc.yaml files.{off} {grey}Deleting them from the repo REVOKES NOTHING:\n"
              f"  the credential goes on being valid wherever it is accepted. Revoking is\n"
              f"  step 2, and it goes BEFORE deleting the file if you care about being\n"
              f"  able to audit it afterwards.{off}")

    if write:
        for q in to_remove:
            os.remove(q)
        if os.path.isdir(dest) and not os.listdir(dest):
            os.rmdir(dest)
        print(f"\n  {green}removed from git.{off} {grey}The edge and the routes are re-derived below:\n"
              f"  its hostname and its plan disappear on their own because they come\n"
              f"  out of the contracts, not out of a separate list.{off}")
    else:
        print(f"\n  {yellow}nothing written{off} {grey}(this was `plan-delete`){off}")

    # ── step 2: the cluster ────────────────────────────────────────
    print(f"\n{grey}2) in the cluster{off} {red}— NOT executed{off}")
    print(f"{grey}   Review every line. They are ordered from least to most destructive, and\n"
          f"   the namespace one goes last because it takes the data with it.{off}\n")

    # The names of the Applications come out of the CONTRACT, by the
    # same rule as render_apps. Saying "check which one" would be
    # handing the operator back a job the contract has already solved,
    # and it is precisely at that step where a name picked by eye
    # deletes another organization's app.
    #
    # MIND the order: if `escribir`, step 1 HAS ALREADY DELETED the file
    # — the copy left in memory is read, not the disk. Read from disk
    # here it blew up with FileNotFoundError exactly on the real run
    # (with `plan-delete` it worked, which is the worst way to fail).
    apps = []
    if contract_path and contract is not None:
        c = contract
        if c.get("repo"):
            apps.append(name)
        for s in c.get("servicios") or []:
            if s.get("repo"):
                apps.append(f"{name}-{s['nombre']}")
    apps_cmd = (" ".join(f"kubectl delete application -n argocd {a};" for a in sorted(set(apps)))
                if apps else
                "# the contract is gone: look at which ones are left with\n"
                "    #   kubectl get applications -n argocd -l aegis.dev/part-of=aegis-tenants")

    steps = [
        ("the Applications, FIRST: while they live, they recreate whatever you delete",
         apps_cmd),
        # The document DOES get removed on its own since #19:
        # appprojects-tenants.yaml is derived and this very run re-derives
        # it without the organization. What does not happen on its own is
        # taking it out of the CLUSTER: ArgoCD deliberately does not
        # manage the AppProjects (W-06 / R1-B), so the usual rule A19
        # holds — taking it out of git does not take it out of here.
        ("the organization's AppProject (the generator already removed the document)",
         f"kubectl delete appproject aegis-tenant-{name} -n argocd"),
        # The encrypted file is removed by this very run (it is derived),
        # but that REVOKES NOTHING: the deploy key stays authorized in
        # GitHub until it is deleted over there. It is the same
        # distinction as with the bucket and with the Garage key —
        # taking the credential out of the repo is not the same as
        # withdrawing the third party's permission.
        ("its deploy key in GitHub (the generator already removed the file)",
         f"# gh repo deploy-key list -R <owner>/<repo>\n"
         f"    # gh repo deploy-key delete -R <owner>/<repo> <id>"),
        ("its AI tasks and its key (shared files, by hand)",
         f"# k8s/base/ai-system/registro.yaml   -> remove the tasks '{name}.*'\n"
         f"    # k8s/base/ai-system/secret-ai-keys.enc.yaml -> remove its entry\n"
         f"    #   (sops k8s/base/ai-system/secret-ai-keys.enc.yaml)"),
        ("its bucket, IF it had storage",
         f"# the bucket lives in the shared Garage: deleting it is a separate\n"
         f"    # decision and with a backup taken first"),
        ("the namespace and EVERYTHING it contains, the data included",
         f"kubectl delete namespace {ns}"),
    ]
    for i, (what, cmd) in enumerate(steps, 1):
        print(f"  {i}. {what}")
        print(f"    {grey}{cmd}{off}\n")

    print(f"{yellow}The PVCs can outlive the namespace{off} {grey}depending on the reclaimPolicy.\n"
          f"Check it AFTERWARDS, which is when it shows:{off}")
    print(f"  {grey}kubectl get pv | grep {ns}{off}\n")
    return 0


# ──────────────────────────────────────────────────────────────────
# Migrate
#
# TODAY ONLY v1 EXISTS, and this command says so instead of pretending.
#
# It exists all the same, and not as a TODO, because the mandatory
# `--to` and the explicit rejection are what prevents the bad
# alternative: that somebody bumps `version: 2` by hand in a contract
# and the generator renders it with v1's rules without saying anything.
# `validate` already rejects an unknown version; this gives the operator
# the right place to ask.
#
# MIGRATIONS is the register of translators. When v2 exists, an entry
# (1, 2) -> function is added, and the rest of this code does not
# change.
# ──────────────────────────────────────────────────────────────────

MIGRATIONS = {}  # (from, to) -> callable(contract_dict) -> dict


def migrate(contracts, dest):
    known = sorted({CONTRACT_VERSION} | {v for _, v in MIGRATIONS})
    if dest not in known:
        print(f"{red}✗{off} version {dest} of the contract does not exist.\n"
              f"  Versions this generator knows how to render: "
              f"{', '.join(str(v) for v in known)}.\n"
              f"\n"
              f"  A new version is justified ONLY if the contract changes (§8).\n"
              f"  Changing a plan's numbers, adding a capability to the routes or\n"
              f"  changing what a type is implemented with are NOT a new version: that\n"
              f"  is why they live outside the contract, in plans.yaml, ai/routes.yaml\n"
              f"  and services.yaml.", file=sys.stderr)
        return 1

    rc = 0
    for path in contracts:
        try:
            c = yaml.safe_load(open(path, encoding="utf-8"))
        except FileNotFoundError:
            print(f"{red}✗{off} does not exist: {path}", file=sys.stderr)
            rc = 1
            continue
        current = (c or {}).get("version")
        if current == dest:
            print(f"{grey}={off} {path}  {grey}already on v{dest}{off}")
            continue
        step = MIGRATIONS.get((current, dest))
        if step is None:
            print(f"{red}✗{off} {path}: there is no translator from v{current} to v{dest}",
                  file=sys.stderr)
            rc = 1
            continue
        # When it exists: apply the translator, SHOW THE DIFF and write
        # only if the operator confirms. Never automatic on apply.
        raise Invalid("translator registered but not implemented")
    return rc


# ──────────────────────────────────────────────────────────────────
# The ROUTES the gateway consumes
# ──────────────────────────────────────────────────────────────────
#
# Three sources, one file:
#
#   ai/routes.yaml   -> capabilities (what each promise is served with)
#   plans.yaml     -> plans (the ceilings, with a name)
#   orgs/*.yaml     -> tenants (which plan each organization has)
#
# The tenant->plan map is DERIVED from the contracts and is not written
# by hand anywhere. Writing it twice is a guarantee that one day they
# will say different things, and the symptom would be one organization
# with another's budget without anybody having decided that.


def routes_json():
    routes = yaml.safe_load(open(ROUTES, encoding="utf-8")) or {}
    plans = yaml.safe_load(open(PLANS, encoding="utf-8"))

    caps = routes.get("capacidades") or {}
    if not caps:
        raise Invalid(f"{ROUTES}: no capabilities — no task could be served")

    tenants = {}
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        ai = c.get("ai")
        if not ai:
            continue  # an organization with no AI does not appear in the routes
        # The key is the NAMESPACE, not the contract's short name: the
        # gateway identifies the tenant by what the API key carries, and
        # that is `org-<name>`. Using the short name here would leave
        # every organization without a recognised plan — and with no
        # recognised plan it falls back to the smallest one, in silence.
        tenants[f"org-{c['organizacion']}"] = ai["plan"]

    doc = {
        "version": 1,
        # sort_keys in json.dumps is not enough: the nested dicts are
        # built here and the insertion order would be the filesystem's.
        "capacidades": {k: caps[k] for k in sorted(caps)},
        "planes": {k: plans["ai"][k] for k in sorted(plans["ai"])},
        "tenants": {k: tenants[k] for k in sorted(tenants)},
    }
    return json.dumps(doc, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def ai_registry_json():
    """The register of AI tasks, derived from the contracts.

    WHAT COMES FROM WHERE, which is the division that matters:

      from the contract   the task's name, its capability, its prompt
                          and —what really had to be derived— the TENANT
      from ai/tasks.yaml  the class and the numeric ceilings

    The tenant was the dangerous coupling. Until #60 you had to remember
    to write it by hand in registro.yaml, and if it was missing the
    gateway answered 403 `tarea_prohibida` with the organization having
    key, network and plan in order: nothing on the contract's side
    turned red. It is the same shape as #54's IngressRoute, one level up.

    The numbers are NOT derived and that is deliberate: they are
    per-task fine tuning and the contract has no honest way of
    expressing them without becoming a configuration file. Same
    criterion as plans.yaml.
    """
    cfg = yaml.safe_load(open(AI_TASKS, encoding="utf-8"))
    classes = cfg.get("clases") or {}
    overrides = cfg.get("tareas") or {}
    rt = yaml.safe_load(open(ROUTES, encoding="utf-8"))
    caps = rt.get("capacidades") or {}

    tasks = {}
    for fname in sorted(os.listdir(ORGS_DIR)):
        if not fname.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, fname),
                                encoding="utf-8")) or {}
        ai = c.get("ai")
        if not ai:
            continue
        org = c["organizacion"]
        for task in (ai.get("tareas") or []):
            key = f"{org}.{task['nombre']}"
            override = overrides.get(key) or {}
            cls = override.get("clase", "interactive")
            if cls not in classes:
                raise Invalid(
                    f"the task {key!r} uses the class {cls!r}, which is not in\n"
                    f"  ai/tasks.yaml. The ones there are: {', '.join(sorted(classes))}")
            cap = task["capacidad"]
            if cap not in caps:
                raise Invalid(
                    f"the task {key!r} asks for the capability {cap!r}, which is not in\n"
                    f"  ai/routes.yaml. The ones there are: {', '.join(sorted(caps))}")
            # A task on the CPU lane (class `cpu`, #26) carries NO
            # prompt: it does not generate text. Coherence is demanded
            # in both directions — a prompt on an embeddings task is
            # somebody confused, and a text task with no prompt is a
            # register the gateway will reject on load. Better here,
            # where the one who finds out is the one editing the
            # contract.
            if cls == "cpu":
                if task.get("prompt"):
                    raise Invalid(
                        f"the task {key!r} is of class cpu and declares a prompt.\n"
                        f"  Tasks on the CPU lane do not generate text: no prompt.")
            elif not task.get("prompt"):
                raise Invalid(
                    f"the task {key!r} declares no prompt, and its class ({cls})\n"
                    f"  generates text: the prompt is mandatory.")
            e = dict(classes[cls])
            e.update({k: v for k, v in override.items() if k != "clase"})
            tasks[key] = {
                "clase": cls,
                "capacidad": cap,
                "engine": caps[cap]["engine"],
                # DERIVED: a task can be invoked ONLY by the
                # organization whose contract declares it. It used to be
                # a hand-written list.
                "tenants": [f"org-{org}"],
                "prompt": task.get("prompt", ""),
                "max_output_tokens": e["max_output_tokens"],
                "max_context_tokens": e["max_context_tokens"],
                "max_input_chars": e["max_input_chars"],
                "temperature": e["temperature"],
                "stop": e.get("stop", []),
                "peso": e["peso"],
            }
    return json.dumps({"version": 1, "tareas": tasks},
                      indent=2, ensure_ascii=False) + "\n"


def render_ai_registry():
    body = ai_registry_json()
    h = hashlib.sha256(body.encode()).hexdigest()[:16]
    indented = "\n".join("    " + l if l.strip() else ""
                         for l in body.rstrip("\n").split("\n"))
    return f"""{markers.BANNER}
# hash: {h}
#
# Comes out of the `ai.tareas` of each contract in orgs/ (nombre,
# capacidad, prompt and the authorized TENANT) + ai/tasks.yaml (clase
# and ceilings) + ai/routes.yaml (which engine serves each capacidad).
#
# THE PROMPTS ARE NOT HERE: they are hand-written content and live in
# prompts.yaml, next door. Mixing them in guaranteed the generator
# would end up overwriting what somebody wrote.
#
# To change it, edit the SOURCE and run `{CMD_ORG_APPLY}`.
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-registro
  namespace: ai-system
  labels:
    aegis.dev/component: ai
data:
  registro.json: |
{indented}
"""


def apply_ai_registry(write):
    rc = _without_ai_subsystem("AI registry")
    if rc is not None:
        return rc
    new = render_ai_registry()
    print(f"\nAI registry  {grey}(k8s/base/ai-system/registro.yaml){off}")
    try:
        old = open(AI_REGISTRY, encoding="utf-8").read()
    except FileNotFoundError:
        old = None
    if old == new:
        print(f"  {grey}={off} AI tasks")
        return 0
    print(f"  {yellow}~{off} AI tasks" if old else f"  {green}+{off} AI tasks")
    if write:
        open(AI_REGISTRY, "w", encoding="utf-8").write(new)
    return 0


def render_routes_k8s():
    body = routes_json()
    h = hashlib.sha256(body.encode()).hexdigest()[:16]
    indented = "\n".join("    " + l if l.strip() else "" for l in body.rstrip("\n").split("\n"))
    return f"""{markers.BANNER}
# hash: {h}
#
# Comes out of ai/routes.yaml (capabilities) + plans.yaml (plans) +
# the `ai.plan` of each contract in orgs/ (tenants).
#
# To change it, edit the SOURCE and run `{CMD_ORG_APPLY}`.
# Editing this by hand works until the next run, which overwrites it.
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-ruteo
  namespace: ai-system
  labels:
    aegis.dev/part-of: aegis-platform
    aegis.dev/component: ai-ruteo
data:
  ruteo.json: |
{indented}
"""


def render_tenants():
    """The Application that deploys each organization's INFRASTRUCTURE,
    derived from the contracts.

    It used to be a hand-written file, and that is why registering an
    organization still had a manual step: write the contract, run the
    generator... and remember to add twenty lines here. The symptom of
    forgetting is the worst possible one: everything generated,
    everything committed, and NOTHING deployed, without a single error.

    Mind what this Application deploys and what it does not. What goes
    here is the infrastructure (namespace, quota, netpols, secrets),
    with the `aegis-platform` project. The organization's APPS come from
    their own repos and use its `aegis-tenant-*`, which can only write
    in its namespace: that separation is the permission boundary and it
    is not mixed.
    """
    orgs = []
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        orgs.append(c["organizacion"])

    parts = [markers.BANNER + f"""
# One Application per CONTRACT in orgs/. It is re-derived on every
# `{CMD_ORG_APPLY}`, so adding an organization is writing its
# contract and nothing else.
#
# The inherited ones —organizations older than the generator— live in
# tenants-heredados.yaml, by hand and on purpose: mixing them in here
# would make the next run delete them in silence.
#
# CreateNamespace=true: the Namespace is in the bundle, but ArgoCD
# needs it to exist before it can apply the rest into it; without this
# option there is a race on the first sync.
#
# REMINDER: root does NOT have automated (ADR-0012). Adding an App here
# does not create it by itself — you have to sync root:  {CMD_SYNC_ROOT}"""]

    for org in orgs:
        parts.append(f"""\
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: org-{org}
  namespace: argocd
  labels: {{aegis.dev/part-of: aegis-platform}}
spec:
  # It is NOT `aegis-platform`. This App deploys the SUBSTRATE of an
  # organization —namespace, quota, network, secrets— and that is a
  # third kind: neither platform nor tenant. Its project narrows
  # cluster-scoped down to `Namespace` (under aegis-platform it
  # inherited '*') and looks for orphans, which under aegis-platform
  # did not happen (#47).
  project: aegis-organizaciones
  source:
    repoURL: {platform_repo()}
    targetRevision: main
    path: k8s/organizations/org-{org}
  destination: {{server: https://kubernetes.default.svc, namespace: org-{org}}}
  syncPolicy:
    automated: {{selfHeal: true}}
    syncOptions: [ServerSideApply=true, CreateNamespace=true]
  ignoreDifferences:
    # The apiserver adds a `status` block INSIDE each of a
    # StatefulSet's volumeClaimTemplates. It is observed state, not
    # configuration: there is no way to declare it, and without this an
    # organization with a database stays OutOfSync forever.
    #
    # The scope is as narrow as it can be: ONLY the .status of those
    # entries. NOT the whole /spec/volumeClaimTemplates, which is the
    # usual shortcut and would hide a change of size or of accessMode.
    #
    # And the image is NOT ignored. That is the other shortcut, and it
    # TURNS OFF auto-sync (#36): if the only difference is the image
    # and the image is ignored, ArgoCD sees nothing to do. Here it is
    # not needed, because everything generated goes by digest.
    - group: apps
      kind: StatefulSet
      jqPathExpressions:
        - '.spec.volumeClaimTemplates[]?.status'""")
    return "\n".join(parts) + "\n"


# ── the tenant AppProjects, derived ───────────────────────────────────
#
# The AppProject IS an organization's permission boundary: it says which
# repo it can read from, which namespace it can write in, and that it
# cannot touch anything cluster-scoped. It was written by hand, and the
# failure mode is one of the ugly ones: if it is missing, the
# Application starts and ArgoCD says "project not found" — loud, yes,
# but only at deploy time, when the contract, the repo, the pipeline and
# the push have already been done.
#
# And there is a worse mode, which is the one that really motivates
# this: repeating the block by hand DRIFTS. It was verified on
# 2026-08-05 in the cluster — `aegis-tenant-canary` was the only one of
# the four without `orphanedResources`, so the canary's app was never
# evaluated and `{CMD_CHECK}` counted it as "nothing orphaned". A block
# copied three times gets updated twice.
#
# Deriving it closes both things at once: the project exists when the
# contract exists, and the four blocks are identical by construction and
# not by discipline.
#
# WHAT IS NOT DERIVED, and why it stays by hand:
#   aegis-bootstrap, aegis-platform  — they belong to the substrate, not
#     to any organization. They do not come out of any contract because
#     there is no contract they could come out of.
#   aegis-tenant-canary              — the canary belongs to the
#     PLATFORM. It lives in org-canary but has no contract: it is the
#     proof that the tenant's path works, so it cannot depend on it.
#   aegis-tenant-ecommerce           — inherited, older than the
#     generator. Same criterion as tenants-heredados.yaml: mixing it in
#     here would make the next run delete it in silence.

def render_appprojects():
    """One AppProject per organization THAT HAS A REPO.

    The condition is not "one per contract": it is one per contract
    whose apps come from a repo of their own. An organization of pure
    infrastructure —a database and a bucket, like org-ejemplo in its
    stage 1— has no external Application, and a project with no
    `sourceRepos` fences nothing in: it is an object that is not used,
    which is exactly what I4 orders swept away.

    The day that organization declares `repo:`, the project appears in
    the same run as its Application. That coupling is the point.
    """
    projects = []
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        repos = sorted(repos_of(c))
        if repos:
            projects.append((c["organizacion"], repos))

    parts = [markers.BANNER + f"""
# One AppProject per CONTRACT that declares a repo. It is re-derived
# on every `{CMD_ORG_APPLY}`.
#
# The substrate projects (aegis-bootstrap, aegis-platform) and the ones
# that do not come out of a contract (aegis-tenant-canary,
# aegis-tenant-ecommerce) live by hand in appprojects.yaml, next door.
# Mixing them in here would make the next run delete them in silence.
#
# ONE AppProject PER ORGANIZATION, not one shared across destinations.
# The difference matters: with a single project listing the three
# namespaces, an ecommerce app could deploy into the portfolio's
# namespace by changing one line in its own repo. The project IS the
# boundary, and a boundary with three open gates is not a boundary.
#
# NO App MANAGES THESE, on purpose (W-06 / R1 path B). They are applied
# with kubectl before root: (a) it avoids the AppProject-vs-Application
# race inside a single sync, and (b) it closes the privilege-escalation
# vector of an App that edits projects. That is why they live outside
# k8s/argocd-apps/, which is the App-of-Apps path."""]

    if not projects:
        parts.append("#\n# (no contract declares a repo yet)")
        return "\n".join(parts) + "\n"

    for org, repos in projects:
        listing = "\n".join(f"    - {r}" for r in repos)
        parts.append(f"""\
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: aegis-tenant-{org}
  namespace: argocd
  labels: {{aegis.dev/part-of: aegis-platform}}
spec:
  description: apps of organization {org} — ONLY its repo, ONLY org-{org}, ZERO cluster-scoped
  # The repos the contract declares: the organization's own and the
  # ones each service declared for itself. Enumerated, never '*'.
  sourceRepos:
{listing}
  destinations:
    - {{server: https://kubernetes.default.svc, namespace: org-{org}}}
  # THE R1-B fix: deny-all cluster-scoped. Writing in an app's repo no
  # longer grants access to the whole cluster.
  clusterResourceWhitelist: []
  # And inside its namespace, no self-scaling and no changing its own
  # limits: those are set by the platform (App org-{org}).
  namespaceResourceBlacklist:
    - {{group: "", kind: ResourceQuota}}
    - {{group: "", kind: LimitRange}}
    - {{group: rbac.authorization.k8s.io, kind: Role}}
    - {{group: rbac.authorization.k8s.io, kind: RoleBinding}}
    # And it CANNOT write its own routing (#54). This is the one that
    # is not obvious: the four above protect the organization from
    # itself; this one protects THE OTHERS from it.
    #
    # An AppProject filters by *kind*, never by the value of a field,
    # so there is no way to say "IngressRoutes yes, but only with YOUR
    # Host". As long as the tenant could create one, it could claim the
    # neighbour's hostname. MEASURED on 2026-08-06: org-blog claimed a
    # host, org-ejemplo claimed THE SAME one, both admitted without a
    # complaint, and traefik ended up serving the second one's. The
    # legitimate owner had no defence and no warning.
    #
    # The only way to bound it by kind is for the kind not to belong to
    # it: the routing is derived by the platform from the contract
    # (routes.yaml, App org-{org}) and here the pen is taken away.
    - {{group: traefik.io, kind: IngressRoute}}
    # And Middleware for the SAME reason, added with #81/#90
    # (2026-08-13). The derived routing hooks three middlewares onto
    # every route —cabeceras, ritmo, cuerpo— and they live in the
    # tenant's namespace. Without this line, the tenant could declare a
    # Middleware with the same name and empty contents: same name, same
    # reference from the IngressRoute it does not control, and the rate
    # limit would disappear without the route changing at all.
    #
    # It is exactly the shape of the Host theft above: you do not steal
    # your own resource, you overwrite the one another references by
    # name.
    - {{group: traefik.io, kind: Middleware}}
  # WARN about what is left over, without deleting it (A19 / #31).
  #
  # `prune` is omitted across the whole platform on purpose: taking
  # something out of git does NOT take it out of the cluster. The
  # decision is right —a badly aimed prune takes data with it— but it
  # leaves a blind spot: nobody finds out what stayed alive. It already
  # happened with NetworkPolicies deleted from git that went on being
  # applied for days.
  #
  # `warn: true` closes that hole without adding risk: ArgoCD marks the
  # orphans as a condition of the app, and the operator decides.
  # Detection, not prevention, and it is accepted as such.
  orphanedResources:
    warn: true
    ignore:
      # The kube-controller-manager creates it in EVERY namespace; it
      # comes out of no git and never will. Without this exception the
      # warning would show up in every organization forever, and a
      # permanent warning kills the signal just as an absence does —
      # which is Disease E and the reason this mechanism exists.
      - group: ""
        kind: ConfigMap
        name: kube-root-ca.crt""")
    return "\n".join(parts) + "\n"


def apply_appprojects(write):
    new = render_appprojects()
    print(f"\nprojects  {grey}(k8s/bootstrap/appprojects-tenants.yaml){off}")
    try:
        old = open(APPPROJECTS_K8S, encoding="utf-8").read()
    except FileNotFoundError:
        old = None
    if old == new:
        print(f"  {grey}={off} organization AppProjects")
        return 0
    print(f"  {yellow}~{off} organization AppProjects" if old
          else f"  {green}+{off} organization AppProjects")
    if write:
        os.makedirs(os.path.dirname(APPPROJECTS_K8S), exist_ok=True)
        open(APPPROJECTS_K8S, "w", encoding="utf-8").write(new)
        # ArgoCD does not manage them (see the file's header), so nobody
        # is going to apply them on their own. Saying it here and not in
        # the documentation: the step you have to remember is the step
        # that gets forgotten, and the edge has already been paid for
        # twice on that account.
        print(f"  {yellow}!{off} the project does not exist in the cluster until you run this:")
        print(f"    {grey}kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml{off}")
        print(f"    {grey}(it goes BEFORE {CMD_SYNC_ROOT}: an Application whose{off}")
        print(f"    {grey} project does not exist stays in 'project not found'){off}")
    return 0


# ── the argocd-secrets generator, derived ─────────────────────────────
#
# The same problem as garage-system, and discovered the same way: a
# SHARED file in which one had to remember to add a line per
# organization. The two that were there —portafolio and blog— had been
# written by hand, and the failure mode was worse than garage's: not
# only did nobody list them automatically, but NOBODY WAS CREATING THEM.
# On a new instance the age key is a different one, everything init
# produces is re-encrypted, and those two were left encrypted with a key
# that no longer exists (#48).
#
# The repository credential belongs to the ORGANIZATION even though it
# lives in ArgoCD's namespace: it comes out of its `repo:` and it
# disappears with it. Being in a platform file is what kept `delete`
# from reaching it.

def render_argocd_secretgen():
    # The PLATFORM ones, which do not come out of any contract. Each
    # one's comment says which phase produces it, because that is the
    # information needed when something does not show up.
    fixed = [
        ("secret-ops-stack-repo.enc.yaml",
         "phase 15 (pipe also applies it in phase 30 — KSOPS ADOPTS it later)"),
        ("secret-github-webhook.enc.yaml", "phase 15 (HMAC — A27)"),
        # The canary's deploy key. It was the LAST one with WRITE
        # permission, and it had it only so that the Image Updater could
        # push its write-back. With that component withdrawn (#59), it
        # becomes READ ONLY, like the blog's and the portfolio's (#49).
        ("secret-hello-aegis-repo.enc.yaml", "phase 15 (READ-ONLY deploy key)"),
    ]
    # secret-regcred-image-updater.enc.yaml WAS HERE, withdrawn in #59
    # along with the component. It was the credential the updater used
    # to read the registry and discover new tags; with no updater there
    # is nobody to use it, and a secret nobody consumes is surface with
    # nothing in return (I4).
    lines = [
        *markers.FRAME,
        "# TEMPORARY RULE (run #4, the bug that stalled phase 35): this App",
        "# syncs in phase 35 — an entry whose .enc.yaml is generated in a LATER",
        "# phase breaks the WHOLE kustomize build (it is atomic) and NOT ONE of",
        "# the App's secrets is created, not even the ones already in the repo.",
        "apiVersion: viaduct.ai/v1",
        "kind: ksops",
        "metadata:",
        "  name: argocd-secrets",
        "  annotations:",
        "    config.kubernetes.io/function: |",
        "      exec: {path: ksops}",
        "# EXPLICIT LIST (A7): no globs. The difference from before is that",
        "# this list is derived by the generator, not by a person.",
        "files:",
    ]
    for filename, why in fixed:
        lines.append(f"  # {why}")
        lines.append(f"  - {filename}")

    # And one repository credential per repo of each contract.
    repos = []
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        repos += [f"secret-{n}-repo.enc.yaml" for n in repos_of(c).values()]
    if repos:
        lines.append(
            "  # The deploy key ArgoCD READS each organization's repo with.\n"
            f"  # It comes from its `repo:` and is created by `{CMD_SECRET}`,\n"
            "  # which also prints the public half so it can be registered on\n"
            "  # GitHub. Without registering it, the App stays in 'repository\n"
            "  # not accessible'.")
        lines += [f"  - {r}" for r in sorted(repos)]
    return "\n".join(lines) + "\n"


def apply_argocd(write):
    new = render_argocd_secretgen()
    print(f"\ncredentials  {grey}(k8s/base/platform/argocd-secrets/secret-generator.yaml){off}")
    try:
        old = open(ARGOCD_SECRETGEN, encoding="utf-8").read()
    except FileNotFoundError:
        old = None
    if old == new:
        print(f"  {grey}={off} repository deploy keys")
        return 0
    print(f"  {yellow}~{off} repository deploy keys" if old
          else f"  {green}+{off} repository deploy keys")
    if write:
        open(ARGOCD_SECRETGEN, "w", encoding="utf-8").write(new)

    # I4: the credential of an organization that is no longer there is
    # SURPLUS. It is not deleted on its own and the reason is said out
    # loud: taking it out of the repo does NOT revoke the deploy key in
    # GitHub, which is where it really grants access.
    expected = set()
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        expected |= {f"secret-{n}-repo.enc.yaml" for n in repos_of(c).values()}
    fixed_repos = {"secret-ops-stack-repo.enc.yaml", "secret-hello-aegis-repo.enc.yaml"}
    d = os.path.dirname(ARGOCD_SECRETGEN)
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if not (f.startswith("secret-") and f.endswith("-repo.enc.yaml")):
            continue
        if f in fixed_repos or f in expected:
            continue
        print(f"  {red}-{off} {f}  {yellow}(credential of an organization that is no longer there){off}")
        print(f"    {grey}Deleting it from the repo does NOT revoke the deploy key: that is\n"
              f"    `gh repo deploy-key delete` against GitHub.{off}")
        if write:
            os.remove(os.path.join(d, f))
    return 0


def orgs_with_bucket():
    """The organizations that declared `almacenamiento.bucket`, sorted.

    One single source for the THREE things that depend on that list: the
    provisioning Jobs, the credential mirrors the secret-generator has
    to list, and whether or not the kustomization brings in
    aprovisionar.yaml. Computing it three times is how they drift apart.
    """
    orgs = []
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        if (c.get("almacenamiento") or {}).get("bucket"):
            orgs.append(c["organizacion"])
    return sorted(orgs)


# ── garage-system's WIRING, derived ───────────────────────────────────
#
# garage-system's kustomization.yaml and secret-generator.yaml were
# written by hand, and the generator wrote files INSIDE that directory
# that neither of the two referenced:
#
#   aprovisionar.yaml              -> was not in `resources`
#   secret-garage-<org>.enc.yaml   -> was not in `files`
#
# The symptom of both was the worst possible one: `aegis org apply` said
# everything had gone well, the files stayed in git, and nothing
# happened in the cluster. No error, anywhere. It is Disease E — a
# signal that does not tell "it worked" from "it was not evaluated".
#
# The cure is not remembering to edit two more files: it is that the
# wiring COMES OUT of the contracts, like the edge and the routes. A
# generated file nobody lists is a file that does not exist.
#
# The EXPLICIT LIST (A7) is kept: there are still no globs, only that
# now the list is written by the generator instead of by a person.

def render_garage_kustomization():
    any_buckets = bool(orgs_with_bucket())
    resources = ["bundle.yaml", "netpol.yaml"]
    if any_buckets:
        # Conditional on purpose: kustomize FAILS if a `resources` entry
        # points at a file that does not exist, and aprovisionar.yaml
        # only exists when some organization asked for a bucket.
        resources.append("aprovisionar.yaml")
    lines = [
        *markers.FRAME,
        "# Comes out of the set of contracts: `aprovisionar.yaml` is listed",
        "# only when some organization declared `almacenamiento.bucket`,",
        "# because kustomize fails if a listed resource does not exist.",
        "apiVersion: kustomize.config.k8s.io/v1beta1",
        "kind: Kustomization",
        "resources:",
    ]
    lines += [f"  - {r}" for r in resources]
    lines += ["generators:", "  - secret-generator.yaml"]
    return "\n".join(lines) + "\n"


def render_garage_secretgen():
    fixed = [
        ("secret-garage-credentials.enc.yaml",
         "rpc_secret and admin_token of the shared Garage. Created by\n"
         f"  # `{CMD_SECRET}` if they are missing, and NEVER regenerated:\n"
         "  # rotating them with the cluster up leaves the node unable to\n"
         "  # talk to itself."),
        ("secret-regcred-internal.enc.yaml",
         "Read credential for the internal registry, to pull the image."),
    ]
    lines = [
        *markers.FRAME,
        "apiVersion: viaduct.ai/v1",
        "kind: ksops",
        "metadata:",
        "  name: garage-system-secrets",
        "  annotations:",
        "    config.kubernetes.io/function: |",
        "      exec: {path: ksops}",
        "# EXPLICIT LIST (A7): no globs. A glob silently takes in any",
        "# .enc.yaml that lands in the directory. The difference from before",
        "# is that this list is derived by the generator, not by a person.",
        "files:",
    ]
    for filename, why in fixed:
        lines.append(f"  # {why}")
        lines.append(f"  - {filename}")
    orgs = orgs_with_bucket()
    if orgs:
        lines.append(
            "  # Mirror of each organization's S3 key. The SAME material as\n"
            "  # in its namespace: the app consumes it over there, and the\n"
            "  # provisioning Job IMPORTS it from here. The other way round\n"
            "  # —the Job generating it— every run would give a different one.")
        for org in orgs:
            lines.append(f"  - secret-garage-{org}.enc.yaml")
    return "\n".join(lines) + "\n"


def apply_garage(write):
    """garage-system's wiring, derived from the set of contracts."""
    rc = 0
    print(f"\ngarage   {grey}(k8s/base/garage-system/){off}")
    for path, new, what in (
            (GARAGE_KUSTOMIZATION, render_garage_kustomization(), "kustomization.yaml"),
            (GARAGE_SECRETGEN, render_garage_secretgen(), "secret-generator.yaml")):
        try:
            old = open(path, encoding="utf-8").read()
        except FileNotFoundError:
            old = None
        if old == new:
            print(f"  {grey}={off} {what}")
            continue
        print(f"  {yellow}~{off} {what}" if old else f"  {green}+{off} {what}")
        if write:
            os.makedirs(GARAGE_DIR, exist_ok=True)
            open(path, "w", encoding="utf-8").write(new)

    # I4: the mirror of an organization that no longer exists is
    # SURPLUS. Without this an S3 credential is left alive in git for a
    # deleted organization — it happened with `conbucket`, a test
    # contract from 2026-08-04 whose mirror outlived the deletion and
    # ended up committed.
    expected = {f"secret-garage-{o}.enc.yaml" for o in orgs_with_bucket()}
    if os.path.isdir(GARAGE_DIR):
        for f in sorted(os.listdir(GARAGE_DIR)):
            if not (f.startswith("secret-garage-") and f.endswith(".enc.yaml")):
                continue
            if f == "secret-garage-credentials.enc.yaml" or f in expected:
                continue
            print(f"  {red}-{off} {f}  {yellow}(mirror of an organization that is no longer there){off}")
            print(f"    {grey}Deleting it from the repo does NOT revoke the key in Garage: that is\n"
                  f"    `garage key delete` against the store.{off}")
            if write:
                os.remove(os.path.join(GARAGE_DIR, f))
    return rc


def render_provisioning():
    """The Jobs that give each organization its bucket and its permission.

    They run in garage-system and not in the organization's namespace
    because they need the storage's ADMIN TOKEN: whoever holds it can
    grant themselves access to anybody's bucket, so it does not come
    down into a tenant namespace. The organization's key IS on both
    sides —`aegis-secret` writes it with the same material— because its
    app consumes it and this Job imports it.
    """
    cat = yaml.safe_load(open(SERVICES, encoding="utf-8"))
    b = cat["bucket"]
    image = f"{cat['registro']}/{b['aprovisionador']['imagen']}@{b['aprovisionador']['digest']}"

    with_bucket = orgs_with_bucket()
    if not with_bucket:
        return None

    script = open(PROVISION_JS, encoding="utf-8").read()
    indented = "\n".join("    " + l if l.strip() else "" for l in script.rstrip("\n").split("\n"))

    parts = [markers.BANNER + f"""
# One Job per organization that declared `almacenamiento.bucket`.
#
# The script is ai/aprovisionar-bucket.mjs, which lives as a FILE and
# not embedded in the generator: that way it can be run by hand against
# a test Garage, which is how it was verified before this was written.
#
# IT RUNS AS A SYNC HOOK, not as a loose resource. A Job is immutable:
# reapplying it with any change fails. With `hook-delete-policy:
# BeforeHookCreation` each sync deletes the previous one and creates
# the new one, and since the script is idempotent that also REPAIRS —
# if somebody deletes a bucket, the next sync recreates it.
apiVersion: v1
kind: ConfigMap
metadata:
  name: aprovisionar-bucket
  namespace: garage-system
  labels: {{aegis.dev/component: garage}}
data:
  aprovisionar.mjs: |
{indented}"""]

    for org in with_bucket:
        parts.append(f"""\
---
apiVersion: batch/v1
kind: Job
metadata:
  name: aprovisionar-bucket-{org}
  namespace: garage-system
  labels: {{aegis.dev/component: garage}}
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  # Three attempts and it gives up. A Job that retries forever turns a
  # configuration error into background noise.
  backoffLimit: 3
  template:
    metadata:
      labels:
        aegis.dev/component: garage
        # The label that opens the NetworkPolicy towards the ADMIN
        # port. It is granted per POD and not per namespace precisely
        # so this Job has it and not everything running beside it.
        aegis.dev/rol: aprovisionar-bucket
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile: {{type: RuntimeDefault}}
      containers:
        - name: aprovisionar
          # nodejs-distroless, already mirrored and signed. Node speaks
          # HTTP without a single dependency: pulling and signing a new
          # image just to talk to an API would be one more link in the
          # supply chain in exchange for nothing. And no shell, which
          # is exactly what you want in a pod holding the admin token.
          image: {image}
          args: ["/app/aprovisionar.mjs"]
          env:
            - {{name: GARAGE_ADMIN, value: "{b['admin']}"}}
            - {{name: ORG, value: "{org}"}}
            - {{name: BUCKET, value: "{org}"}}
            - name: GARAGE_ADMIN_TOKEN
              valueFrom:
                secretKeyRef: {{name: garage-credentials, key: admin_token}}
            # The SAME material the organization has in its own
            # namespace. It is imported, not asked for: if Garage
            # generated the key, every run would give a different one
            # and it would have to be written back somewhere.
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef: {{name: garage-{org}, key: AWS_ACCESS_KEY_ID}}
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef: {{name: garage-{org}, key: AWS_SECRET_ACCESS_KEY}}
          volumeMounts:
            - {{name: script, mountPath: /app, readOnly: true}}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {{drop: [ALL]}}
            readOnlyRootFilesystem: true
          resources:
            requests: {{cpu: 20m, memory: 32Mi}}
            limits: {{cpu: 200m, memory: 128Mi}}
      volumes:
        - name: script
          configMap: {{name: aprovisionar-bucket}}""")
    return "\n".join(parts) + "\n"


def apply_provisioning(write):
    new = render_provisioning()
    print(f"\nbuckets  {grey}(k8s/base/garage-system/aprovisionar.yaml){off}")
    try:
        old = open(PROVISION_K8S, encoding="utf-8").read()
    except FileNotFoundError:
        old = None
    if new is None:
        if old is None:
            print(f"  {grey}={off} no organization asked for a bucket")
            return 0
        # I4: what the set of contracts no longer produces is surplus.
        print(f"  {red}-{off} aprovisionar.yaml  {grey}(nobody asks for a bucket any more){off}")
        if write:
            os.remove(PROVISION_K8S)
        return 0
    if old == new:
        print(f"  {grey}={off} provisioning Jobs")
        return 0
    print(f"  {yellow}~{off} provisioning Jobs" if old
          else f"  {green}+{off} provisioning Jobs")
    if write:
        os.makedirs(os.path.dirname(PROVISION_K8S), exist_ok=True)
        open(PROVISION_K8S, "w", encoding="utf-8").write(new)
    return 0


# ── the Jenkins jobs, derived ─────────────────────────────────────────
#
# Hole #2 of the onboarding map (caminos/design.md §2a): each new app
# demanded copying ~20 lines of job-dsl by hand into the JCasC values.
# The failure mode of forgetting is the usual one: the contract is
# there, the repo is there, and no build ever runs — with nothing red,
# because a job that does not exist cannot fail.
#
# The block goes INSIDE values.yaml, between markers, and not in a
# configScript of its own: JCasC runs with ErrorOnConflict (A30) and two
# sources declaring the `jobs:` key abort the whole boot. Outside the
# markers, what is written by hand survives: hello-aegis-mb belongs to
# the canary (org-canary has NO contract — it is the proof that the
# tenant's path works, so it cannot depend on it) and ai-gateway-mb
# belongs to the PLATFORM. They migrate into the block the day their org
# has a contract, not before (debt noted in design §2a). The three that
# DID have a contract —portafolio, blog, ejemplo— migrated here on
# 2026-08-19, after verifying first that the derived text reproduced the
# manual one character by character.

JOBS_BLOCK_START = markers.JOBS_BLOCK_START
JOBS_BLOCK_END = markers.JOBS_BLOCK_END
# Without re.S: `(?:.*\n)*?` eats whole lines and cannot run past the
# closing marker even if the block is empty.
JOBS_BLOCK_PATTERN = markers.JOBS_BLOCK_PATTERN
# The multibranch plugin does not speak URLs: it speaks
# owner/repository. The two forms a `repo:` can bring are accepted (ssh
# and https) and the rest is rejected — a repo outside GitHub needs
# another branchSource, which is another decision, not one more entry.
GITHUB_REPO_PATTERN = re.compile(
    r"^(?:git@github\.com:|https://github\.com/)([^/]+)/([^/]+?)(?:\.git)?$")


def jenkins_jobs():
    """(name, owner, repository) for each repo of each contract.

    The job's name is that of its Application (repos_of): one repo, one
    job, one App — the SAME key in Jenkins and in ArgoCD, so that a
    build's log and a deployment's state can be matched without a
    translation table. Stable alphabetical order: values.yaml's diff
    does not depend on the filesystem (I1).
    """
    jobs = []
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        for repo, app_name in repos_of(c).items():
            m = GITHUB_REPO_PATTERN.match(repo)
            if not m:
                raise Invalid(
                    f"{name}: repo {repo!r} is not on GitHub.\n"
                    f"  The multibranch job is declared with the owner/repository of the\n"
                    f"  github-branch-source plugin; a repo on another host needs another\n"
                    f"  branchSource — that is another decision, not one more entry here.")
            jobs.append((app_name, m.group(1), m.group(2)))
    return sorted(jobs)


def render_jobs_block():
    lines = [JOBS_BLOCK_START]
    lines.append(f"""\
          # One multibranch job per repo declared in a contract in
          # orgs/. The job's name is its Application's: one repo, one
          # job, one App — the same key in Jenkins and in ArgoCD.
          # This block is re-derived WHOLE on every run of
          # {CMD_ORG}: whatever is edited between the markers does
          # not survive the next one.""")
    for n, owner, repo in jenkins_jobs():
        lines.append(f"""\
          - script: >
              multibranchPipelineJob('{n}-mb') {{
                displayName('{n} (multibranch)')
                branchSources {{
                  github {{
                    id('{n}-gh')
                    repoOwner('{owner}')
                    repository('{repo}')
                    scanCredentialsId('github-token')
                  }}
                }}
                orphanedItemStrategy {{
                  discardOldItems {{ numToKeep(10) }}
                }}
                // The same timer the platform's own job carries: a net
                // under EDGE=cloudflare, and the ONLY thing that
                // notices a push under EDGE=local, where GitHub cannot
                // reach the edge to deliver a webhook. Without it a
                // tenant's repo would have no CI at all on a local
                // edge, while hello-aegis did — a difference nobody
                // asked for and nothing would have reported.
                triggers {{
                  periodicFolderTrigger {{
                    interval('2m')
                  }}
                }}
                configure {{ node ->
                  def traits = node / sources / data / 'jenkins.branch.BranchSource' / source / traits
                  traits << 'org.jenkinsci.plugins.github__branch__source.BranchDiscoveryTrait' {{
                    strategyId(1)
                  }}
                }}
              }}""")
    lines.append(JOBS_BLOCK_END)
    return "\n".join(lines)


# ── each organization's watch, derived ────────────────────────────────
#
# Until 2026-08-22 an organization was born ISOLATED and BLIND: the
# contract derived namespace, quota, routes, netpols, secrets, jobs and
# signature — and not one watch target. Measured that day: shop had been
# alive for a day and if its API had started returning 500 to every
# customer, nothing would have fired. Not one platform alert named a
# tenant application.
#
# The cause runs deep and is noted in RUTA: ALL of the protocols'
# vocabulary talks about TRANSITIONS (done/already/not-evaluable, the
# boundary, plan/apply, each phase's gates). Nothing talked about
# permanent state. It was verified that something had been set up
# correctly, never that it was still working.
#
# This derives the target; the RULES that consume it are generic and
# live in rules/vmalert-rules.yaml (one rule for all tenants, not N
# copies). That is why adding an organization does not add alerts: it
# adds a target, and the alerts that already exist cover it.
#
# The `dominio:` is probed and NOT the platform hostnames: those sit
# behind Cloudflare Access and their 302 to the login would count as a
# success — the error init's check 90 exists to forbid.
PROBES_BLOCK_START = markers.PROBES_BLOCK_START
PROBES_BLOCK_END = markers.PROBES_BLOCK_END
PROBES_BLOCK_PATTERN = markers.PROBES_BLOCK_PATTERN


def tenant_probes():
    """One (organizacion, dominio) per contract that declares something public.

    Without `dominio:` there is nothing to probe from outside. Stable
    alphabetical order: the values' diff does not depend on the
    filesystem.
    """
    probes = []
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        dom, org = c.get("dominio"), c.get("organizacion")
        if not dom or not org:
            continue
        # With no `publico:` service there is no path a customer could
        # walk, and probing it would give a 404 forever.
        if not any(s.get("publico") for s in (c.get("servicios") or [])):
            continue
        probes.append((org, dom))
    return sorted(probes)


def render_probes_block():
    lines = [PROBES_BLOCK_START]
    lines.append(f"""\
    # One probe per organization with a domain and a public path. It
    # measures the COMPLETE path a customer walks: DNS, edge, tunnel,
    # traefik, middlewares and the app. Everything else measures
    # pieces.
    # This block is re-derived WHOLE on every {CMD_ORG_APPLY}.""")
    probes = tenant_probes()
    if not probes:
        lines.append("    # (no organization declares a domain with a public path)")
    for org, dom in probes:
        lines.append(f"""\
    - job_name: sitio-{org}
      metrics_path: /probe
      params: {{module: [sitio_publico]}}
      static_configs:
        - targets: ["https://{dom}/"]
          labels: {{organizacion: {org}}}
      relabel_configs:
        - source_labels: [__address__]
          target_label: __param_target
        - source_labels: [__param_target]
          regex: "https?://([^/]+).*"
          target_label: instance
          replacement: "$1"
        - target_label: __address__
          replacement: blackbox.observability.svc:9115""")
    lines.append(PROBES_BLOCK_END)
    return "\n".join(lines)


def apply_probes(write):
    text = open(VMAGENT_VALUES, encoding="utf-8").read()
    if not PROBES_BLOCK_PATTERN.search(text):
        raise Invalid(
            f"I could not find the derived block's markers in {VMAGENT_VALUES}.\n"
            f"  These two lines have to exist (with their indentation of 4\n"
            f"  spaces, inside scrape_configs):\n"
            f"{PROBES_BLOCK_START}\n"
            f"{PROBES_BLOCK_END}\n"
            f"  Without them there is no way of knowing what is derived and what is a\n"
            f"  person's, and overwriting blind is worse than not generating.")
    probes = tenant_probes()
    new = PROBES_BLOCK_PATTERN.sub(lambda _: render_probes_block(), text, count=1)
    print(f"\nprobes  {grey}(k8s/base/observability/vmagent/values.yaml){off}")
    if new == text:
        print(f"  {grey}={off} tenant probes  {grey}{len(probes)} probe(s){off}")
        return 0
    print(f"  {yellow}~{off} tenant probes -> "
          f"{', '.join(o for o, _ in probes) or '(none)'}")
    if write:
        open(VMAGENT_VALUES, "w", encoding="utf-8").write(new)
        # The same warning as the edge's and jenkins', for the same
        # reason: the step you have to remember is the one that gets
        # forgotten.
        print(f"  {grey}the probe does not exist until you commit + sync:\n"
              f"  vmagent reloads its config when the values reaches the cluster{off}")
    return 0


def apply_jenkins(write):
    text = open(JENKINS_VALUES, encoding="utf-8").read()
    if not JOBS_BLOCK_PATTERN.search(text):
        raise Invalid(
            f"I could not find the derived block's markers in {JENKINS_VALUES}.\n"
            f"  These two lines have to exist (with their indentation of 10\n"
            f"  spaces, inside the aegis-jobs configScript):\n"
            f"{JOBS_BLOCK_START}\n"
            f"{JOBS_BLOCK_END}\n"
            f"  Without them there is no way of knowing what is derived and what is a\n"
            f"  person's, and overwriting blind is worse than not generating.")
    names = [n for n, _, _ in jenkins_jobs()]
    new = JOBS_BLOCK_PATTERN.sub(lambda _: render_jobs_block(), text, count=1)
    print(f"\njenkins  {grey}(k8s/base/platform/jenkins/values.yaml){off}")
    if new == text:
        print(f"  {grey}={off} tenant jobs  {grey}{len(names)} job(s){off}")
        return 0
    print(f"  {yellow}~{off} tenant jobs -> {', '.join(f'{n}-mb' for n in names) or '(none)'}")
    if write:
        open(JENKINS_VALUES, "w", encoding="utf-8").write(new)
        # The values is a GitOps artifact: the job does not exist in
        # Jenkins until this change reaches the cluster and JCasC's
        # sidecar reloads the seed. Saying it here and not in the
        # documentation, for the same reason as the edge: the step you
        # have to remember is the one that gets forgotten.
        print(f"  {grey}the job does not exist in Jenkins until you commit + sync:\n"
              f"  JCasC reloads the seed only when the values reaches the cluster{off}")
    return 0


# ── the consumers of each base image, derived ─────────────────────────
#
# On 2026-08-26 a CVE in the shared nginx base left four static fronts
# frozen for a day: the fix was one FROM line, and it had to be bumped
# BY HAND in four repos, one pull request each, by whoever remembered
# which repos stood on that base. The base-images job now does that
# edit itself — after building, scanning and signing a base it clones
# every consumer and rewrites its FROM — and the one thing it needs is
# the list of consumers. That list is not knowledge anybody should
# keep: the contracts already say it.
#
# Which repos are in it is decided by the service TYPE, but only up
# to a point. While aegis-base-nginx was the only base, the type was
# the whole answer: a `estatico` service is by definition served by
# that base on STATIC_PORT (the rule in _type_coherence forbids it a
# port precisely because the base decides it), so "the repos of the
# static services" WAS "the consumers of aegis-base-nginx". On
# 2026-08-27 aegis-base-node joined for the node backends, and the
# type stopped being enough: a backend is `http` whether it is node or
# not (the seed's own template app is Go), and the contract has no
# field that says which base — nor should it: the ONLY place that
# knows is the repo's Containerfile, in its FROM line. So the list
# names every repo that BUILDS AN IMAGE, one list for every base, and
# the job decides per member by grepping each repo for
# `aegis-base-<member>@sha256:` — a listed repo whose Containerfile
# names no such base is skipped with a notice, never failed. That
# asymmetry is deliberate: a repo listed for nothing costs one clone
# and one line of log; a consumer NOT listed is exactly the hole this
# file exists to close (the FROM nobody bumped).
#
# The repo string is written EXACTLY as the contract carries it
# (git@… or https://…): the pipeline normalises both forms, and
# rewriting it here would be a second normaliser to keep in step with
# the first.

CONSUMERS_BLOCK_START = markers.CONSUMERS_BLOCK_START
CONSUMERS_BLOCK_END = markers.CONSUMERS_BLOCK_END
CONSUMERS_BLOCK_PATTERN = markers.CONSUMERS_BLOCK_PATTERN
# There used to be a BASE_CONSUMER_TYPES = {"estatico"} here, "so that
# the second base is one line". The second base killed the distinction
# instead: with two bases and no contract field naming either, the only
# type-level fact that survives is "this service comes out of an image
# somebody builds" — and that set already has a name.
BASE_CONSUMER_TYPES = TYPES_WITH_IMAGE


def base_consumers():
    """The repos of every service that builds an image, sorted and unique.

    Every image-bearing type (TYPES_WITH_IMAGE), not only `estatico`:
    since 2026-08-27 there are two owned bases (nginx for the static
    fronts, node for the node backends) and the contract cannot say
    which one a repo stands on — only its Containerfile can. So this is
    ONE list for every base, and the base-images job sorts it out per
    member by grepping each repo for `aegis-base-<member>@sha256:`; a
    listed repo that names no base is skipped with a notice. Over-
    listing is cheap; a consumer left OUT is the FROM nobody bumps,
    which is the failure this file was created to end. `postgres` stays
    out because it has no repo and no Containerfile to bump.

    A service's repo is resolved the way repos_of does it — the service's
    own `repo`, or the organization's when the service has none — so
    the list can never name a repo the AppProject would not let in.
    Sorted, unique: one repo with a front and its API is one clone, and
    the file's diff does not depend on the filesystem (I1).
    """
    repos = set()
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        for s in c.get("servicios") or []:
            if s.get("tipo") not in BASE_CONSUMER_TYPES:
                continue
            repo = s.get("repo") or c.get("repo")
            if repo:
                repos.add(repo)
    return sorted(repos)


def render_consumers_block():
    """The block, and NOTHING but URLs inside it.

    Unlike the jobs and probes blocks this one carries no explanatory
    comment and no "(none)" line: the pipeline reads the file with
    grep and every non-comment line is a repository it will clone.
    With zero consumers the two sentinels sit adjacent.
    """
    return "\n".join([CONSUMERS_BLOCK_START, *base_consumers(), CONSUMERS_BLOCK_END])


def apply_base_consumers(write):
    if not os.path.isfile(BASE_CONSUMERS):
        raise Invalid(
            f"{BASE_CONSUMERS} does not exist.\n"
            f"  The seed ships it (base-images/consumers.txt) and the base-images\n"
            f"  job reads it to know which repos to rewrite after a base is rebuilt.\n"
            f"  Without it the bump is back to being a hand edit in every consumer.")
    text = open(BASE_CONSUMERS, encoding="utf-8").read()
    if not CONSUMERS_BLOCK_PATTERN.search(text):
        raise Invalid(
            f"I could not find the derived block's markers in {BASE_CONSUMERS}.\n"
            f"  These two lines have to exist (at column 0, this file is not YAML):\n"
            f"{CONSUMERS_BLOCK_START}\n"
            f"{CONSUMERS_BLOCK_END}\n"
            f"  Without them there is no way of knowing what is derived and what is a\n"
            f"  person's, and overwriting blind is worse than not generating.")
    repos = base_consumers()
    new = CONSUMERS_BLOCK_PATTERN.sub(lambda _: render_consumers_block(), text, count=1)
    print(f"\nbase-consumers  {grey}(base-images/consumers.txt){off}")
    if new == text:
        print(f"  {grey}={off} base consumers  {grey}{len(repos)} repo(s){off}")
        return 0
    print(f"  {yellow}~{off} base consumers -> {', '.join(repos) or '(none)'}")
    if write:
        open(BASE_CONSUMERS, "w", encoding="utf-8").write(new)
        # The same warning as jenkins': the job reads the file from the
        # platform repo's main, not from this working tree.
        print(f"  {grey}the base-images job reads the list from git, not from here:\n"
              f"  it takes effect once this change is committed + pushed{off}")
    return 0


# ── each service's Jenkinsfile, instantiated ──────────────────────────
#
# The canonical template (docs/protocols/templates/Jenkinsfile.app) has
# ONE single CHANGEME in 452 lines: the image's name. Making a person
# copy the whole file in order to edit that line invites the opposite
# error — editing what is NOT theirs: the pins, the limits and the
# secrets are a contract with the platform (its own header says so).
#
# It is instantiated into the staging area .aegis-app/<org>/<svc>/ and
# NOT into a versioned directory: this file's destination is THE APP's
# repo (journeys §3 — `aegis app apply` pushes it only into an empty
# repo), and versioning here a copy of what lives over there would
# repeat platform/'s historical mistake: two copies, and the one nobody
# looks at rots. That is why .aegis-app/ is in the .gitignore.
#
# NO I3 guard here, on purpose: once pushed, the Jenkinsfile's truth
# lives in the app's repo; the staging area is regenerable material and
# re-deriving overwrites it without asking.

def services_to_instantiate():
    """(org, service) for each service that is BUILT from a repo.

    A `postgres` does not appear: it is provided by the platform and has
    no pipeline. The condition is having an image to compile AND a repo
    to take it from — its own or the organization's.
    """
    out = []
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        for s in c.get("servicios") or []:
            if s.get("tipo") in TYPES_WITH_IMAGE and (s.get("repo") or c.get("repo")):
                out.append((c["organizacion"], s["nombre"]))
    return sorted(out)


def apply_jenkinsfiles(write):
    tpl = open(JENKINSFILE_TPL, encoding="utf-8").read()
    # If the template loses its CHANGEME —or grows another one— this
    # replace would stop instantiating what it is believed to
    # instantiate. Better to shout here than to discover it on the first
    # build with the wrong image.
    found = tpl.count("'CHANGEME-app'")
    if found != 1:
        raise Invalid(
            f"{JENKINSFILE_TPL}: I expected exactly ONE 'CHANGEME-app' and there are "
            f"{found}.\n"
            f"  This derivation instantiates that single marker; if the template\n"
            f"  changed shape, both things have to be updated together.")
    print(f"\njenkinsfiles  {grey}(.aegis-app/ — staging, gitignored){off}")

    expected = {}
    for org, svc in services_to_instantiate():
        # IMAGE = '<org>-<svc>' (caminos §2b): the convention of the
        # live reference (ejemplo-front, ejemplo-api). The blog and the
        # portfolio are older and publish 'blog'/'portafolio' for their
        # front; their repos are not touched from here — the staging
        # area is never pushed over somebody else's history.
        expected[os.path.join(org, svc, "Jenkinsfile")] = \
            tpl.replace("'CHANGEME-app'", f"'{org}-{svc}'")

    for rel in sorted(expected):
        file_path = os.path.join(STAGING_DIR, rel)
        new = expected[rel]
        try:
            old = open(file_path, encoding="utf-8").read()
        except FileNotFoundError:
            old = None
        if old == new:
            print(f"  {grey}={off} {rel}")
            continue
        print(f"  {yellow}~{off} {rel}" if old is not None else f"  {green}+{off} {rel}")
        if write:
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            open(file_path, "w", encoding="utf-8").write(new)

    # I4: the staging area of a service that no longer derives from any
    # contract is SURPLUS. ONLY the Jenkinsfile is removed —which is
    # what this derivation produces— and the directories left empty: the
    # day the staging area also holds skeletons from `aegis app new`,
    # those are not ours to delete.
    if os.path.isdir(STAGING_DIR):
        for org in sorted(os.listdir(STAGING_DIR)):
            org_dir = os.path.join(STAGING_DIR, org)
            if not os.path.isdir(org_dir):
                continue
            for svc in sorted(os.listdir(org_dir)):
                jf = os.path.join(org_dir, svc, "Jenkinsfile")
                rel = os.path.join(org, svc, "Jenkinsfile")
                if not os.path.exists(jf) or rel in expected:
                    continue
                print(f"  {red}-{off} {rel}  {grey}(no contract produces it any more){off}")
                if write:
                    os.remove(jf)
                    for d in (os.path.join(org_dir, svc), org_dir):
                        if os.path.isdir(d) and not os.listdir(d):
                            os.rmdir(d)
    return 0


def apply_tenants(write):
    new = render_tenants()
    print(f"\ntenants  {grey}(k8s/argocd-apps/tenants.yaml){off}")
    try:
        old = open(TENANTS_K8S, encoding="utf-8").read()
    except FileNotFoundError:
        old = None
    if old == new:
        print(f"  {grey}={off} organization Applications")
        return 0
    print(f"  {yellow}~{off} organization Applications" if old
          else f"  {green}+{off} organization Applications")
    if write:
        open(TENANTS_K8S, "w", encoding="utf-8").write(new)
        print(f"  {grey}root has no automated: for it to exist, "
              f"{CMD_SYNC_ROOT}{off}")
    return 0


def orgs_with_ai():
    """The organizations whose contract declares `ai:`, sorted.

    The CONTRACT is asked and not the tree: the contract is the one that
    PROMISES, and a promise the instance cannot keep is precisely what
    has to be seen.
    """
    orgs = []
    for name in sorted(os.listdir(ORGS_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(ORGS_DIR, name), encoding="utf-8")) or {}
        if c.get("ai"):
            orgs.append(c["organizacion"])
    return sorted(orgs)


def _without_ai_subsystem(what):
    """The THREE outcomes of the AI subsystem, said out loud.

    Reproduced on 2026-08-24 against v3's seed: a perfectly valid
    contract WITHOUT an `ai:` block made `aegis org apply` die with a
    traceback —

        FileNotFoundError: .../k8s/base/ai-system/routes.yaml

    — and not at the start, but AFTER having written the organization's
    six manifests. Which is to say it left the tree half done and the
    blame looked like the contract's.

    The cause was that the two AI stages ran ALWAYS, without asking
    whether the subsystem was there. With the decision that AI does not
    travel in the seed (only its documents and its protocol), «it is not
    there» stopped being an anomaly and became the NORMAL shape of a
    freshly-cloned tree.

    But it cannot be skipped in silence, and here is the only line that
    matters: an absence is not a legitimate case until it is told apart
    from an error (rule 3 of the CLI's design).

      · no subsystem and no contracts asking for it  -> DOES NOT APPLY (0)
      · no subsystem and WITH contracts asking       -> FAILS (1)
      · with subsystem                               -> carry on (None)

    The second case is what makes the helper worth it: a contract that
    declares `ai:` on an instance with no AI is not a generation detail,
    it is a promise nobody will be able to keep, and the moment to see
    it is now and not when the front asks for a translation.
    """
    if os.path.isdir(AI_DIR):
        return None
    print(f"\n{what}  {grey}(k8s/base/ai-system/){off}")
    asking = orgs_with_ai()
    if asking:
        print(f"  {red}\u2717{off} {len(asking)} contract(s) declare `ai:` "
              f"({', '.join(asking)}) and this tree does not have the AI subsystem")
        print(f"  {grey}the contract promises something the instance cannot give: "
              f"either the subsystem is brought in, or `ai:` leaves the contract{off}")
        return 1
    print(f"  {grey}\u25cb DOES NOT APPLY: the AI subsystem is not in this "
          f"tree and no contract asks for it{off}")
    return 0


def apply_routes(write):
    rc = _without_ai_subsystem("routes")
    if rc is not None:
        return rc
    new = render_routes_k8s()
    print(f"\nroutes  {grey}(k8s/base/ai-system/routes.yaml){off}")
    try:
        old = open(ROUTES_K8S, encoding="utf-8").read()
    except FileNotFoundError:
        old = None
    if old == new:
        print(f"  {grey}={off} ai-ruteo")
        return 0
    print(f"  {yellow}~{off} ai-ruteo" if old else f"  {green}+{off} ai-ruteo")
    if write:
        open(ROUTES_K8S, "w", encoding="utf-8").write(new)
    return 0


def main():
    p = argparse.ArgumentParser(prog=cli.cmd("org"), description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, help_text in (("plan", "show what would change, without writing"),
                            ("apply", "write the manifests"),
                            ("validate", "only validate the contract")):
        s = sub.add_parser(name, help=help_text)
        s.add_argument("contracts", nargs="+")
    sub.add_parser("edge", help="derive public_hostnames from every contract")
    sub.add_parser("routes", help="derive the ai-ruteo ConfigMap from every contract")
    # `plan-delete` first, and with that name: the order of the help
    # matters when the command next to it destroys things.
    for name, help_text in (("plan-delete", "show what it would delete, without touching anything"),
                            ("delete", "remove from git and SAY what to withdraw from the cluster")):
        s = sub.add_parser(name, help=help_text)
        s.add_argument("orgs", nargs="+", metavar="ORGANIZATION")
    m = sub.add_parser("migrate", help="take a contract to a new version")
    m.add_argument("contracts", nargs="+")
    # `--to` and not `--a`: A5's friction 2 in its smallest form — a
    # loose preposition does not say what it refers to.
    m.add_argument("--to", type=int, required=True, metavar="VERSION",
                   dest="target_version")
    a = p.parse_args()

    if a.cmd == "edge":
        try:
            return apply_edge(write=True)
        except Invalid as e:
            print(f"{red}✗{off} {e}", file=sys.stderr)
            return 1

    if a.cmd == "routes":
        try:
            return apply_routes(write=True)
        except Invalid as e:
            print(f"{red}✗{off} {e}", file=sys.stderr)
            return 1

    if a.cmd == "migrate":
        return migrate(a.contracts, a.target_version)

    if a.cmd in ("delete", "plan-delete"):
        rc = 0
        for name in a.orgs:
            try:
                rc |= delete_org(name, write=(a.cmd == "delete"))
            except Invalid as e:
                print(f"{red}✗ {name}{off}\n  {e}", file=sys.stderr)
                rc = 1
        # Re-derive ALWAYS, on delete too: the hostname and the plan of
        # the organization that left have to disappear in the same run.
        # If they stayed, the edge would go on creating its CNAME and the
        # gateway would go on knowing a tenant that no longer exists.
        if rc == 0:
            for stage, fn in (("edge", apply_edge),
                              ("routes", apply_routes),
                              ("ai-registry", apply_ai_registry),
                              ("projects", apply_appprojects),
                              ("credentials", apply_argocd),
                              ("tenants", apply_tenants),
                              ("buckets", apply_provisioning),
                              ("garage", apply_garage),
                              ("jenkins", apply_jenkins),
                              ("base-consumers", apply_base_consumers),
                              ("probes", apply_probes),
                              ("jenkinsfiles", apply_jenkinsfiles)):
                try:
                    rc |= fn(write=(a.cmd == "delete"))
                except Invalid as e:
                    print(f"{red}✗ {stage}{off}\n  {e}", file=sys.stderr)
                    rc = 1
        return rc

    rc = 0
    for path in a.contracts:
        try:
            if a.cmd == "validate":
                plans = yaml.safe_load(open(PLANS, encoding="utf-8"))
                validate(yaml.safe_load(open(path, encoding="utf-8")), plans)
                print(f"{green}✓{off} {path}")
            else:
                rc |= apply_contract(path, write=(a.cmd == "apply"))
        except Invalid as e:
            print(f"{red}✗ {path}{off}\n  {e}", file=sys.stderr)
            rc = 1
        except FileNotFoundError as e:
            print(f"{red}✗{off} does not exist: {e.filename}", file=sys.stderr)
            rc = 1

    # The edge and the routes ALWAYS, after the organizations. They go
    # here and not as separate commands somebody has to remember to run:
    # remembering is exactly what failed the two previous times.
    #
    # Both derive from ALL the contracts, not from the one just touched:
    # registering an organization changes the whole tenant->plan map, and
    # that file has to be left consistent in the same run or the gateway
    # starts up with an organization it does not know.
    if a.cmd in ("plan", "apply") and rc == 0:
        for stage, fn in (("edge", apply_edge),
                          ("routes", apply_routes),
                          ("ai-registry", apply_ai_registry),
                          ("projects", apply_appprojects),
                          ("credentials", apply_argocd),
                          ("tenants", apply_tenants),
                          ("buckets", apply_provisioning),
                          ("garage", apply_garage),
                          ("jenkins", apply_jenkins),
                          ("base-consumers", apply_base_consumers),
                          ("probes", apply_probes),
                          ("jenkinsfiles", apply_jenkinsfiles)):
            try:
                rc |= fn(write=(a.cmd == "apply"))
            except Invalid as e:
                print(f"{red}✗ {stage}{off}\n  {e}", file=sys.stderr)
                rc = 1
    return rc

