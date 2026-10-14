# Changelog

Nothing here is a promise of a version: `main` is what you clone. This
file says what changed for whoever installs or operates, from which
commit, and what it asks of an instance that already exists.

## 2026-10-14 — what the 2026-10-13 review found, closed one commit at a time

A review of the product on 2026-10-13 (static, with no cluster: the suite
and every tooth, shellcheck, the seed rendered and validated, the Kyverno
CLI over synthetic pods, gitleaks, and a reading of the code behind each
finding) left a list. Each item below is one commit with its check and its
tooth. «Not yet run on a live instance» means exactly that, and each item
says what an instance will have to do.

- **A Secret is encrypted before it enters the platform repo.**
  `make_enc_secret` and phase 15's token block used to move the plaintext
  into the checkout and encrypt it in place, the only way `.sops.yaml`'s
  `path_regex` would match; a sops that failed in between left a cleartext
  Secret under a `*.enc.yaml` name, one `git add -A --no-verify` away from
  GitHub. Now the file is encrypted in tmpfs under the destination's rule
  (sops's `--filename-override`) and only the ciphertext is moved in; and
  `git_commit_if_changes`, the door every phase's commit goes through,
  refuses any staged `*.enc.yaml` or `*.enc.json` that carries no sops
  metadata. Instances: nothing to do; the files already in the repo are
  untouched. Not yet run on a live instance. Check 283.
- **A secret that fails to generate stops the init.** bash turns `errexit`
  off inside a command substitution, and every generator runs inside one:
  a failing `openssl` in `gen_hex32` used to return the path of a 0-byte
  file that `persist_secret` encrypted, roundtripped and kept, and the
  store restored that empty HMAC on every re-run. Every lib that sets
  `errexit` now sets `inherit_errexit` with it, each generator checks the
  size of what it produced, and the store refuses empty material.
  Instances: nothing to do. The option makes a `$( )` die where its parent
  would, so a latent failure the init used to shrug off can now stop a
  phase where it happens: that is the point, and the reason this one is
  owed a full run before it is called done. Not yet run on a live
  instance. Check 284.
- **The copy of the age key the operator reads dies with the phase.** The
  backup ceremony writes the key to tmpfs so that the operator reads it
  from another terminal, never from the pane. That copy sat at
  `/dev/shm/aegis-resguardo-<pid>`, outside the directory the phase's
  EXIT/INT/TERM traps shred, and was removed only after a successful
  validation: a wrong paste, a die in the validator or a Ctrl-C at the
  pause left the root of trust in the clear until the next reboot. The copy
  now lives inside the phase's tmpfs directory, so the same cleanup takes
  it however the phase ends. Instances: nothing to do; the ceremony only
  runs on a fresh phase 10 or a key rotation, and the step reads
  `cat <path>` as before. Not yet run on a live instance. Check 285.
- **The edge's plaintext state dies with the wrapper call, however the
  call ends.** `tofu-apply.sh` decrypts the state for every call and, since
  2026-10-10, re-encrypts and shreds it at the end; but that was the end
  of the script, so a TERM while tofu ran, a second Ctrl-C or a die
  between the decrypt and the end left `terraform.tfstate` in the clear,
  exactly as the 2026-10-09 corpse was found. The re-encrypt and the shred
  now run from an EXIT trap and an INT/TERM trap, once tofu has returned
  the state whole; a state that cannot be proven is still left in place,
  loudly. Instances: `aegis seed diff` shows the wrapper; `aegis seed
  apply` brings it in. Not yet run on a live instance. Check 277, extended
  with a TERM in the middle of an apply.

## 2026-10-13 — the first signed build on a clean Ubuntu, and what it took

The first full run of the series on a clean Ubuntu lab VM (2026-10-12 and
13) reached phase 80 and stopped there four times. Each stop
is a fix in the product, each fix has its check, and none of them asks a
live instance for anything but `git pull` and `aegis seed apply`.

- **The exploited-in-the-wild list ages from the day it was fetched**, not
  from CISA's last release. A list fetched that minute read as «5 days
  old: no debt credit», every HIGH inside its window was blocked, and five
  bases (golang and alpine among them) were held at the door. Both writers
  (the mirror's fetch and the watch's morning fetch) now stamp
  `fetched=<UTC day>`; `verdict.sh` and the ledger age the copy from it.
  Instances: the next `image-watch` morning writes the stamp; nothing to do
  by hand. Checks 255 and 267.
- **Phase 80 says why the canary keeps its public bases** instead of
  ending «FAILED» with nothing else: a bare `_GOLANG="$(…)"` under `set -e`
  made the warning unreachable. Check 282.
- **A resumed phase 80 repoints a canary it already repointed**: the
  pattern only matched `FROM docker.io/library/golang:`, so after a pin
  moved the canary kept the old digest while the log said «repointed». The
  pattern takes any registry path. Check 282.
- **golang 1.26.6 → 1.26.9** in `mirror-images/images.txt`: the canary's
  first signed build carried three HIGH of the 1.26.6 stdlib, fixed in
  1.26.9. Instances: `aegis image request` brings the new digest; apps on
  `__FROM_GOLANG__` get it on their next `aegis org apply`.
- **CI installs age and sops** at the seed's pins: checks 277 and 278 drive
  a real sops and age over a throwaway key and were a FAIL, not a skip,
  on the first push that carried them.
- **Check 264 records gh's session too**: a machine without a `gh` login
  (the public CI) stopped `app apply` before the order the check measures.

## 2026-10-12 — a failed webhook delivery is re-delivered, and the lab VMs verify green

- **Phase 35 re-delivers a failed ArgoCD hook delivery** the way phase 60
  already did, through one helper (`lib/access.sh`'s `hook_delivery_2xx`):
  a 2xx passes, a 400 stops at once, in flight is waited for, anything
  else is re-delivered at most once a minute, and only a delivery NEWER
  than the one the phase marked counts (an old 2xx from a previous run
  proved nothing). Found on that VM: a 502 four seconds after
  cloudflared connected, then 180 s polling a dead delivery. Checks 281
  and 067.
- **The verifier on a lab VM**: a login named after the product (`aegis`)
  names no person, so check 117 is no longer the one red of every lab
  verify; check 120 recognises a home by its shape (`/home/<anyone but
  operator>`, `/Users/<x>`, the dash-encoded scratchpad form) whoever runs
  it, and the synthetic `security-vulns` console case no longer carries a
  lab owner; checks 260 and 272 read what only their `npm` run proved, so
  their teeth bite on a host without npm too.

## 2026-10-10 — four things a live instance wants to know

- **The edge's plaintext state does not outlive the wrapper call.**
  `terraform.tfstate` and its `.backup` had sat in `envs/cloudflare-tunnel`
  since 2026-09-25 with the tunnel token in the clear (measured on the
  home instance, 2026-10-09). `tofu-apply.sh` now shreds the plaintext and
  every backup once the encrypted copy is proven to hold the same state;
  `aegis destroy`, `aegis state` and `aegis rotate` read the encrypted
  copy. Instances: `aegis seed apply tofu/tofu-apply.sh`, then any
  `tofu-apply.sh` call shreds what is lying there. Check 277.
- **The ArgoCD admin password comes from the store, not the installer**
  (#86). A new instance used to be born with the password
  `argocd-initial-admin-secret` carried: outside the store, unmeasurable by
  `aegis rotate check`, absent from a state backup. Phase 30 now generates
  it with `gen_or_restore`, hashes it through htpasswd's stdin and patches
  `argocd-secret` only when the annotation says it holds another one;
  phase 35 logs in through the edge to prove it. Instances: `aegis init
  --only 30` once (sessions are closed by the new `passwordMtime`), and
  the password is read from the store from then on
  (`docs/OPERATE.md`). Check 278.
- **Traefik buffers bodies in a volume with a ceiling.** Orphaned
  `temp-multibuf-*` files piled up to 9.7 GB on the home instance's system
  disk. `TMPDIR` now points at `/buffer`, an emptyDir with `sizeLimit:
  2Gi`: past it the kubelet evicts that replica instead of the disk
  filling. Instances: `aegis seed apply k8s/base/ingress/traefik/values.yaml`
  and a sync of traefik. Check 279.
- **The node defends its disk again.** `eviction-hard` is one map, and a
  kubelet given only `memory.available` switched its disk thresholds off
  on every host since 2026-09-10. The drop-in writes the memory margin
  plus the kubelet's documented disk defaults; phase 20 asks the running
  kubelet; `DiscoDelNodoPorLlenarse` warns at 20 % free. Instances: `aegis
  init --only 20` rewrites the drop-in and restarts k3s. Check 280.

## 2026-10-07 — the books keep their clocks, and a git that cannot answer refuses

- **The ledger**: an image not looked at one morning keeps its first-seen
  clocks as comment lines, so a dateless window never restarts after a bad
  morning; an image the verdict stops says the block's reason, not the
  summary line; an app's events carry the merged findings, not the
  excused scan's. Checks 267 and 269.
- **`tofu-apply.sh`** keeps tofu's errors on stderr and the plan on stdout,
  each through the same value redactor. Check 273.
- **`aegis update` and `aegis app apply`**: a git that asks for credentials
  or hangs is a refusal (`GitTrouble`), not a two-minute wait and a
  traceback. Check 266.
- **`aegis seed apply` brings over an instance-owned file the instance
  lacks**: an older instance never got `vuln-policy/kev.txt`, so the three
  files it did get would have left the Application unable to render.
  Instances older than 2026-10-02: `aegis seed diff` now lists it; `aegis
  seed apply` brings it. Check 225.

## 2026-10-02 — after the vulnerability clock: four fixes from the first runs of the series

- **The round reads each multibranch job inside its own block**: with
  `AI=no` the empty `ai-gateway-mb` repo made «every push built» judge
  the wrong job, and every instance without AI turned red the day it got
  its first app. Check 276.
- **`--help` after a verb is help, and writes nothing**: `aegis state
  backup --help` used to write a real age bundle to a file named
  `--help`. Check 275.
- **A Jenkinsfile's `def` does not shadow a loop variable Groovy already
  holds** (image-watch died at its first step on the Arch lab VM); check 274
  compiles that rule over every Jenkinsfile of the seed.
- **An app inherits its base's scan exceptions on the layers it inherits,
  and only there**: a CVE excused at the mirror came out OVERDUE in the
  app that stands on that base. Checks 267 and 269.
- **Four teeth that had stopped biting** (100, 169, 189, 200), found by
  the first full teeth run of the series, re-aimed.

## 2026-10-02 — a known vulnerability costs a date, not a red build

Until now every scan had one answer: a fixable CRITICAL or HIGH stops.
On 2026-09-30 a clean install died in phase 80 over two OpenSSL CVEs
published the day before, in upstream images nobody here could rebuild.
The platform now tells what a CHANGE brings from what TIME brought
(`seed/platform/docs/protocols/images.md` §1.1, §1.2, §4.1).

- **One policy, one verdict** (`k8s/base/platform/vuln-policy/`): a finding
  the platform lets in has a window from the CVE's publication, 15 days
  for a critical and 30 for a high. One on CISA's exploited-in-the-wild
  list has none.
- **The mirror** lets an image in with debt inside its window and RETAINS
  one past it; a retained image stops the install only if the platform
  itself runs it. An image already mirrored and signed is not judged again
  at the door.
- **A tenant's build** is judged on the layers it adds: what its base
  carries is the platform's, and what already ran passes as debt. A new
  finding of its own still stops it. Existing apps take the new pipeline
  with `aegis app rebase <org>`.
- **image-watch keeps the books**: every finding of what is served, and of
  what runs in the tenants, with its due date and who fixes it. `aegis
  vulns` reads them; `aegis check` reports debt inside its window as a
  notice and only what is overdue or exploited as a failure; the console
  draws them on Security and on each project's card.
- **The alerts are a ladder**: `VulnDebt` (once a day), `VulnDebtDueSoon`,
  `VulnDebtOverdue`, `VulnExploited`. `ImageWithFixableVulns` is gone.
- **The `static` and `service-node` templates** compile, install and test
  in the pipeline's own agent; the image build only copies. Neither needs
  `node:22.23.1-alpine` mirrored any more.
- **`tofu-apply.sh` no longer shows values**: for `plan`, `apply` and
  `destroy` every attribute value and every `[id=…]` reads «(not shown)».
  `aegis destroy` without `--yes` used to print the tunnel's secret, and
  phase 25 wrote it into the install log.
  `AEGIS_TOFU_SHOW_VALUES=1` shows them.
- **The platform repo now has a writer in the cluster every morning**:
  image-watch commits `image-watch/ledger.txt` and
  `k8s/base/platform/vuln-policy/kev.txt` when they change. A clone on
  your machine goes stale overnight: `aegis image request`, `aegis image
  gc` and `aegis update` take the remote in by themselves; before an edit
  by hand, `git pull --ff-only`.
- **If your instance is live**: `aegis seed diff` names what it lacks
  (the `vuln-policy` Application and directory, the two platform
  Jenkinsfiles, `image-watch/ledger.sh`, the alert rules, the alertmanager
  route, `tofu/tofu-apply.sh`); `aegis seed apply` brings it and you push.
  This path has not been run on a live instance yet — the first one will
  be the reference instance, and this entry will say what it took.
  Checks 255 to 273.

## 2026-09-27 — downloads reach the visitor without a copy on the system disk

- The `-cuerpo` sibling of 2026-09-25 only caught `GET`s that announced a
  stream; a plain download of a large file was still buffered — copied in
  full to a `temp-multibuf-*` file in traefik's emptyDir on the system
  disk before its first byte went out. On the home instance that pinned a
  QLC SSD at 90 % busy, slowed the k3s API server to seconds, got traefik
  and kyverno killed by their liveness probes, and cut every download of
  a 3 GB file mid-way. The sibling now covers every `GET` and `HEAD` —
  the methods with no body for the cap to cap — with no header
  condition; `POST`/`PUT`/`PATCH`/`DELETE` keep the 10 MiB cap. Check 251
  requires both methods and refuses a body-carrying one in the sibling.
  Organizations get it on their next `aegis org apply`. An instance that
  already ran into this can purge the leftovers with a rollout restart of
  traefik (the emptyDir goes with the pod).

## 2026-09-25 — SSE and WebSockets reach the visitor

- traefik's `buffering` (each organization's `-cuerpo`, the 10 MiB cap on
  request bodies) also holds the RESPONSE until it ends, so an SSE stream
  never arrived. Every public route now has a sibling for `GET` requests
  with `Accept: text/event-stream` or `Upgrade: websocket`, without that
  middleware (headers and per-visitor rate limit kept). Organizations get
  it on their next `aegis org apply`.

## 2026-09-25 — a tenant build does not hold its layers compressed in memory

- The app Jenkinsfile template runs kaniko with `--compressed-caching=false`.
  A layer of CUDA wheels is several GB; with compression caching kaniko
  held it in memory and was OOMKilled at its 2Gi limit (the build read
  ABORTED). Existing apps get it by re-deriving (`aegis org apply`) and
  pushing the new Jenkinsfile to their repo.

## 2026-09-25 — a service's own secrets: `secretos:` and `aegis secret put`

- **New contract field.** `secretos: [name, ...]` on an `http` or
  `worker` service declares credentials the platform cannot invent (a
  cloud key, a chosen password). Each becomes the Secret
  `<service>-<name>`, listed by the generator; one nobody has provided
  shows as missing in `aegis org apply`.
- **New verb.** `aegis secret put <file> --from-file KEY=PATH [...]`
  encrypts the file's exact bytes into `data:`, through sops's stdin:
  never in argv, never printed (key names and byte lengths only), and
  only for a file a contract declares. It leaves an existing file alone;
  `--replace` changes the material.

## 2026-09-25 — `gpu: true` hands the instance's card to one service

- **New contract field.** `gpu: true` on ONE `http` or `worker` service
  of an organization, on an instance whose AI lane is `gpu`. The
  platform labels the organization's Namespace `aegis.dev/gpu-otorgada`,
  sets its quota to one `nvidia.com/gpu`, and its sizes Policy writes
  `runtimeClassName: nvidia` and the card request into that service's
  pods. The tenant's repo writes none of it. Deploy the service with
  `strategy: Recreate`: the quota refuses a second copy.
- `tenants-without-gpu` steps aside for that label only; in a granted
  namespace the nvidia runtime must ask for the card in every container.
  `NVIDIA_*` variables stay refused everywhere.
- Instances: bring `clusterpolicy-tenants-without-gpu.yaml` over again
  (`aegis seed apply k8s/base/kyverno-policies/clusterpolicy-tenants-without-gpu.yaml`).

## 2026-09-25 — an organization does not reach the GPU unless the platform hands it one

- **Security.** Measured on a live instance: in any organization's
  namespace, a pod could ask for `nvidia.com/gpu` (no quota named it), or
  ask for nothing and set `runtimeClassName: nvidia` plus
  `NVIDIA_VISIBLE_DEVICES=all`, and see the whole card (`/dev/nvidia0`).
  The new ClusterPolicy `tenants-without-gpu` refuses the three in every
  `org-*` namespace (Enforce, fails closed). `ai-system`, the platform's
  own GPU lane, is not affected.
- **Instances already running** get it by listing the policy in their
  `kyverno-policies` kustomization:
  `aegis seed apply k8s/base/kyverno-policies/clusterpolicy-tenants-without-gpu.yaml k8s/base/kyverno-policies/kustomization.yaml`
  (the kustomization of an instance past phase 80 also lists the
  signature policy: keep that entry). It can be applied at once with
  `kubectl apply -f` on that file; ArgoCD adopts it when the kustomization
  lists it.
- Phases 35 and 80 add and remove only the signature policy's entry
  (`signature_policy_entry`), and keep any other policy in the list.
## 2026-09-25 — traefik gives up on a dead backend

- **traefik bounds its wait for a backend**: `dialTimeout=5s` and
  `responseHeaderTimeout=60s` (static arguments in
  `k8s/base/ingress/traefik/values.yaml`). The running binary (v3.7.4) dialed
  for 30 s and waited for headers with no limit: during a 90 s network cut
  towards the canary (2026-09-24) every visitor hung. The header timeout is
  the wait for the FIRST header byte: SSE and WebSockets send headers at once
  and are unaffected; 60 s also stays under Cloudflare's own 100 s cut. Check 246.
- **If your instance is live**: `aegis seed apply
  k8s/base/ingress/traefik/values.yaml --yes` and push (traefik restarts with
  the new arguments).

## 2026-09-25 — a release does not drop the people on the site

- **The canary and every app template that serves a port wait 5 s in
  `preStop` before stopping** (native `sleep` action: the runtime images
  carry no shell), with `terminationGracePeriodSeconds: 30`. On SIGTERM a
  pod leaves the endpoints and stops at the same instant, and traefik
  keeps routing to it until the change reaches it: measured 2026-09-24,
  every rollout under 300 req/s dropped ~296 requests in 3 s (cloud
  instance) and 295 (Debian). The worker template has no port and is
  unchanged. Check 245.
- **Apps created before this** keep their own `k8s/` (the template is
  copied once): add the same `lifecycle.preStop.sleep` to their
  Deployment; `aegis seed apply k8s/…` does not reach a tenant's repo.
  The canary: its Deployment lives in the canary's app repo, not in the
  platform repo — copy the block there.

## 2026-09-25 — the rate limit counts per visitor, and traefik has room

- **Every rate limiter now counts per VISITOR behind the tunnel.** A
  traefik rateLimit with no `sourceCriterion` counts by the connection, and
  behind Cloudflare every connection is cloudflared's: «50 req/s per
  visitor» was 50 for the whole internet. Measured with a control on
  2026-09-24: a quiet visitor at ~5 req/s got 197 × 429 of 300 while another
  IP pushed 80 req/s, and none alone. The generator's `<org>-ritmo` and the
  seed's `canary-ritmo` and `ntfy-ritmo` now scan X-Forwarded-For from the
  right, skipping the pod range the entrypoints trust (`10.42.0.0/16`).
- **traefik runs two replicas with 512Mi** (it was one with 256Mi, and was
  OOMKilled at ~1600 req/s towards a CPU-throttled backend). Check 244.
- **If your instance is live**: `aegis seed apply
  k8s/base/ingress/traefik/values.yaml
  k8s/organizations/org-canary/routes.yaml
  k8s/base/observability/routes.yaml --yes`, push, and re-render every
  organization's routes with `aegis org apply orgs/<org>.yaml` (the
  generator writes the new criterion into each `<org>-ritmo`).

## 2026-09-24 — the canary sync ArgoCD does not retry

- **Phase 80 re-fires the canary sync that died on the signed digest.**
  ArgoCD re-attempts an automated sync only for a new revision. On the
  second cloud VM the canary revision carrying the signed digest was
  synced while Kyverno could not verify signatures, and was denied; once
  Kyverno was repaired the canary gate waited fifteen minutes for a sync
  that never came. After the policy is live and before that gate, the
  phase now syncs the canary again when its last operation Failed
  refusing that exact digest; any other failure is left to the wait and
  its diagnostic. Check 237.

## 2026-09-24 — a Kyverno restart owed for the CA is measured

- **Phase 80 restarts Kyverno whenever a controller is older than its
  CA, not only on the run that injected it.** The registry CA reaches
  Kyverno by subPath, which never refreshes; the restart used to hang on
  a flag of the injecting run. On the second cloud VM that run died in
  mirror-images before the restart, every later run found the CA already
  in git, and the admission controller kept a CA file without the aegis
  CA: it fell back to plain HTTP against the registry and denied the
  signed canary (`GET http://…:5000/v2/: 400`). The phase now compares
  each controller's oldest running pod with the last write of the CA
  ConfigMap it mounts, restarts on any debt, and gates
  `kyverno-ca-cargada` afterwards. Check 236.
- **If your Kyverno denies signed images with that 400**: resume phase
  80, or restart its controllers by hand
  (`kubectl -n kyverno rollout restart deploy`).

## 2026-09-24 — aegis-base-nginx declares /tmp writable

- **The nginx base starts under its own smoke test.** Its `nginx.conf`
  puts the pid and every temp path under `/tmp` (tenant pods run with a
  read-only root), and its `runtime-test.yaml` declared only
  `/var/cache/nginx` and `/run`. Since the smoke test arrived
  (2026-09-20) every clean install died in phase 80 on
  `open() "/tmp/nginx.pid" failed (30: Read-only file system)`, and `php`,
  built on top of it, fell with it. The runtime test now names `/tmp`,
  as php's already did. Check 235 reads every `pid` and `*_temp_path`
  of each base's nginx.conf against what its runtime test mounts.
- **If your instance's consumers of aegis-base-nginx do not mount /tmp
  as an emptyDir**, they die the same way on the next base rebuild:
  the runtime test is the base's contract with them.
- **If your instance was installed before 2026-09-20**, bring the file
  over: `aegis seed apply base-images/nginx/runtime-test.yaml --yes`.

## 2026-09-24 — redis 8.6.7 and postgres 17.11: the next patch, not a wait

- **The seed pins the patch that followed.** `redis:8.6.4-alpine` and
  `postgres:17.10-alpine` carry util-linux with CVE-2026-53612 (HIGH,
  fixed) and upstream never rebuilds an old patch tag: it publishes the
  next one. `redis:8.6.7-alpine` and `postgres:17.11-alpine` (both built
  2026-09-21, same major) carry the fixed util-linux and OpenSSL 3.5.8.
  No exception was written: the packages ARE in those images (`setpriv`,
  `libuuid`), and the clean patch exists.
- **If your instance runs these images**: `aegis seed apply
  mirror-images/images.txt --yes`, push the commit, and run the
  `mirror-images` job. The service catalogue's digests follow in a
  separate commit, read off the live registry once the mirror publishes.

## 2026-09-23 — the dirty-cloud pre-check sweeps Access too

- **Reinstalling against the same zone no longer dies on 409
  `application_already_exists`.** Phase 25 already swept a previous
  instance's tunnel and CNAMEs by name; the second cloud VM (the first
  one's host froze) then hit five 409s in the apply, because the dead
  instance's Access applications carry the same domains, and its
  reusable policies and service token sat next to them under the same
  names. The pre-check now lists the account's Access applications
  (domains under `ROOT_DOMAIN`), policies and service token (the module's
  names), keeps whatever THIS instance's encrypted state owns, and
  deletes the rest under the same RED confirmation — apps first, since
  a policy in use refuses to die. Gate `access-sin-restos`, declared
  subjectless on `EDGE=local` and when the token cannot list. Check 234.
- **A live instance needs nothing.** Its own resources are in its state
  and are never touched; a re-run of phase 25 lists nothing to sweep.

## 2026-09-23 — the GPU device plugin lands only where the node says there is a card

- **The NVIDIA device plugin no longer tries to start on a node without a
  GPU.** Its DaemonSet is part of the core and is synced on every
  instance, but its pods need the `nvidia` runtime class: on an `AI=no`
  install the pod sat in `ContainerCreating` for hours and the ArgoCD app
  `gpu` never left `Progressing`. The DaemonSet now selects nodes
  labelled `aegis.dev/gpu=true`; phase 20 puts that label on the node
  under `AI=gpu` and measures it (`gpu-node-labelled`), and removes it
  otherwise. Check 233.
- **If your instance runs `AI=gpu` today**: label the node BEFORE this
  change reaches it through `aegis seed apply`, or the plugin is left
  with no node to land on:
  `kubectl label node --all --overwrite aegis.dev/gpu=true`. An `AI=no`
  instance needs nothing: the stuck pod disappears on the next sync.

## 2026-09-23 — cleaning the cloud cleans the encrypted state too

- **Phase 25 no longer resurrects a tunnel it just deleted.** When it
  finds the leftovers of a failed apply in Cloudflare, it deletes them and
  purged the local tfstate; since the state lives encrypted, the wrapper
  decrypted the deleted tunnel right back and the apply died on a 404
  three runs in a row. The tunnel module is now dropped from the state
  through the wrapper (the Access resources, still in the cloud, stay),
  the plaintext copies `tofu state rm` writes are shredded, and the
  seed's `.gitignore` covers them (`*.tfstate.*.backup`). Check 232.
- **If your instance is stuck on that 404**: `tofu-apply.sh
  -chdir=envs/cloudflare-tunnel state rm <each module.tunnel.* resource>`
  with `SOPS_AGE_KEY_FILE` exported, shred the `terraform.tfstate.*.backup`
  copies, then `aegis init --from 25`.

## 2026-09-22 — Zero Trust dormant, found before the edge is built

- **Phase 25 asks whether Cloudflare Access is enabled** before it
  creates a tunnel, a DNS record or a policy. A brand new Cloudflare
  account has Zero Trust dormant and answers 403 «not_enabled» to every
  Access call; the first cloud instance found out in the middle of `tofu
  apply`. The refusal names the page that switches it on, and both
  READMEs and the journey now say it belongs in the preparation.

## 2026-09-22 — the valve's probe can say yes

- **Phase 20 no longer withdraws a reservation that was working.** The
  valve that rolls the node's memory reservation back asks the API with
  `kubectl`, and the user's kubeconfig is written further down in the
  same phase: up there kubectl talks to localhost:8080 and refuses
  however healthy the cluster is. On the first cloud instance the API
  had been serving for three minutes while the probe kept saying no. The
  probe now uses k3s's own kubeconfig, with the user's as a fallback, and
  check 230 drives it against a healthy cluster, a dead one, and a
  machine where `sudo -n` is refused.

## 2026-09-22 — the owner's deploy-key policy, asked in time

- **Phase 00 asks whether the GitHub owner allows deploy keys.** An
  organization forbids them by default, and aegis asked for its first
  one in phase 15 — with two repositories created, two Cloudflare tokens
  minted and half an hour gone. The first cloud instance of the lab died
  exactly there («Deploy keys are disabled for this repository»). Now the
  run stops before it touches anything, naming the page that changes the
  policy. A personal account has no such policy and is left alone; an API
  that cannot answer is NOT measured, not refused.
- **The clocks' gate converges before it measures.** `enable --now` on a
  machine past the timers' `OnBootSec` fires them that second, and a
  timer whose service is still running has no next elapse yet. The gate
  now waits for one (up to two minutes) instead of failing a healthy
  machine.

## 2026-09-22 — a server image is not a desktop

- **`aegis host` no longer reserves memory for a desktop that does not
  exist.** It took `graphical.target` alone as proof that a human shares
  the machine, and cloud images boot into it with nothing graphical
  installed (the first Vultr VM of the lab: Ubuntu 26.04, no gdm, sddm
  or lightdm). Now a machine is shared when a display manager is
  installed or a local session holds a seat; an unreadable display
  manager still counts as shared. An instance already installed on a
  VPS keeps the floor it derived: `aegis host floor --set` changes it.

## 2026-09-22 — a machine aegis cannot install on is refused first

- **The host is the first question**, in `aegis preflight` (before its
  first `sudo`), in `aegis init` (before the phase loop, so `--from` and
  `--only` cannot walk around it) and at the top of phase 00 (before the
  wizard). The rule is Ubuntu 24.04 or newer, the same one the phase 20
  playbook asserts, and it lives in `lib/host.sh`. Until today the only
  refusal was that playbook: on a CachyOS machine the preflight had
  already written a sudoers drop-in and switched IPv6 off, the wizard had
  asked every question, and phase 00 had only warned.
- **If you ran aegis on another distribution before this commit**, what
  it may have left: `/etc/sudoers.d/010-aegis-init-nopasswd`,
  `/etc/sysctl.d/99-disable-ipv6.conf` (plus IPv6 off until reboot or
  `sysctl -w`), `/usr/local/bin/k3s*` (remove with
  `k3s-uninstall.sh`), `~/aegis/`, the age key in
  `~/.config/sops/age/aegis.key`; outside the machine, two GitHub
  repositories with the topic `aegis-v2-disposable` and, with
  `cloudflare`, API tokens whose names start with `aegis`.

## 2026-09-21 — the front page, and main under CI

- **Both READMEs rewritten as one document in two languages**, section
  for section: what you get, before you start, install, your first
  application, how it works, the console, the commands, where it has
  been run, what is not there yet. The English page had aged in silence
  (136 checks, fifteen phases, a `restore` that left the bucket behind);
  check 180 now reads both gap lists and knows that `aegis seed apply`
  exists. Every picture ships in both languages (`docs/assets/*.en.svg`),
  and the console appears as it is: two screens drawn from the shipped
  case corpus, and its four states.
- **`main` is verified by GitHub on every push** and the badge on the
  front page says so. The first run went red on check 117: on a CI
  platform the login (`runner`) is the platform's, not a person's; the
  people there are the pusher and the repository's owner, and the owner
  is now measured on every machine, from the origin of the clone.

## 2026-09-20 — a version another person can install

For a fresh install (`docs/journeys/your-machine.md`):

- **Phase 00 asks the GPU** when `AI=gpu`: `nvidia-smi` has to answer
  with VRAM before a phase runs; the gate names the driver's install
  path and the fallen-off-the-bus signature.
- **Phase 05 installs the three user clocks** (backup, host metrics,
  update notice), derives `backup.env`, enables linger, links
  `/usr/local/share/aegis`, and gates on a **next run** — not on
  «enabled». `aegis-backup.timer` carries `OnCalendar=daily` beside its
  interval, so a restarted timer never sits without an appointment.
- **The AI gateway starts with an empty task registry** (in `ai-gateway`
  since 2026-09-02): a platform is born before its tenants. Not new in
  this version; named here because a clone that is behind still refuses.

For the bases you own (`base-images/`):

- **`MEMBERS` is never empty** and **`PROPAGATE` is false unless asked**:
  a pipeline cannot know who fired it, so the caller says both.
  `aegis ci build base-images --members <m>` builds, scans, signs and
  tells nobody; `--propagate` rewrites the consumers, once, when you
  mean it. `image-watch` and phase 80 pass both.
- **Every candidate runs as a pod before it is signed**, under exactly a
  tenant's restrictions (non-root, seccomp, no capabilities, read-only
  root), with what the member declares in `runtime-test.yaml`. A base
  that does not come up is pushed and NOT signed: inert for every tenant.
- `BasePropagationStorm`: a consumer rewritten more than three times in
  a week for one base is somebody iterating with `PROPAGATE=true`.
- Check 036 weighs `requests` as well as `limits`, every sidecar, and
  every spelling of a pod's resources.

For an instance that already exists:

- **`aegis seed diff` / `aegis seed apply`**: what the seed changed that
  your instance lacks, told apart from what is yours (contracts, plans,
  secrets, derived blocks) and from what only moved in pins; brought
  over with your pins and blocks kept, in a commit you read and push.
- **`aegis check` exits 2** when a measure could not be taken, and 2
  dominates 1; it also asks the cluster for every contract's AppProject.
- `aegis state restore --force` is a flag wherever it stands; `aegis
  rotate --help` prints its usage.

For the product: `.github/workflows/verify.yml` runs the whole static
suite on every push and the teeth of every check a pull request
touches; gitleaks scans every push.

Checks 223 to 226, each with its teeth. Registro: plan 18.
