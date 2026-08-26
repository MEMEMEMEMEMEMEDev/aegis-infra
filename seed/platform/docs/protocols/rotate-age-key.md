# Rotating the age key — the root of trust

**Written on 2026-08-12.** Four places in the stack cited it —two of
them by a specific section (`§A`, `§A.8/A.9`)— and the file did not
exist. The rotation procedure for the one irreducible of the system was
a dangling reference.

| what cited it | from |
|---|---|
| `docs/protocols/rotation-checklist.md` | item 1 and the table of refusals |
| `init/phases/10-age-ceremony.sh:3` | «generalizes rotate-age-key.md §A» |
| `init/lib/secrets.sh:21` | «pattern rotate-age-key.md §A» |
| `init/lib/secrets.sh:406` | «rotate-age-key.md §A.8/A.9» |

---

## Why this rotation is unlike all the others

aegis' whole model of secrets rests on a single sentence:

> The age key decrypts everything, so it is the only thing the operator
> safeguards. The rest is recoverable.

That makes this the only rotation that **cannot be recovered from the
system itself**. If `sops updatekeys` is left half done, there is
material that no longer decrypts with the old key (because it was taken
away from it) nor with the new one (because it never got added to it).
No backup helps: the backup is encrypted with the key that broke too.

Hence the shape of the protocol: **the new key is added before the old
one is taken away**, and between those two moments there is a
verification that can fail. Throughout the whole of phase A both sets of
keys work, so there is no instant at which a failure leaves material
unreadable.

---

## Measured scope (2026-08-12)

```
platform/**/*.enc.yaml, *.enc.json ..... 39 files
init/.state-secrets/*.enc ............... 18 files
                                          ──
                                          57 re-encryptions
```

Plus three places that point at the key and have to move with it:

| where | what it is |
|---|---|
| `platform/.sops.yaml` | **three** `creation_rules`, each with its own `age:` |
| `init/.age-public` | this is where `$AGE_PUBLIC` comes from for the whole init |
| `argocd/argocd-sops-age` (Secret, key `keys.txt`) | what KSOPS uses in the cluster to decrypt |

`init/.state-secrets/.sops.yaml` **is not edited by hand**:
`persist_secret` rewrites it on every call out of `$AGE_PUBLIC`. It
moves only when `init/.age-public` moves.

---

## Before starting

```bash
export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/aegis.key
export AEGIS_BACKUPS=/mnt/<your backup disk>/aegis-backups   # mounted (#85)
aegis state backup          # ROUNDTRIP verified, not «we have backups»
```

The bundle ends up encrypted with the **old** key. That is deliberate:
as long as the old one is still valid —the whole of phase A— that backup
is usable. Once phase C is over you have to **back up again**, because
the old bundle stops opening.

And one condition that is not negotiable: the safeguarded copy of the
old key has to be at hand and **proven**, not assumed. If you cannot
decrypt something with it right now, do not start.

---

## Phase A — the new key comes in, the old one stays

**A.1** Generate the new key in tmpfs and derive its public half.

```bash
umask 077
NEW=/dev/shm/age-new.key
age-keygen -o "$NEW"
PUB_NEW="$(age-keygen -y "$NEW")"
PUB_OLD="$(cat init/.age-public)"
echo "old: $PUB_OLD"
echo "new: $PUB_NEW"
```

The public halves **can** be looked at and printed. The private one
cannot: it lives in `/dev/shm` until you put it in safekeeping.

**A.2** Put the new key in safekeeping **from another terminal**, never
in this pane. That is rule W-01/EV-01, and it comes from a real
incident: an age key ended up in a tmux log and that instance was
declared compromised (`HISTORIA.md:199`).

```
# in ANOTHER terminal:
cat /dev/shm/age-new.key        # store it wherever you store your secrets
```

**A.3** Add the new public half as a **second** recipient, without
taking the old one away. The three rules of `platform/.sops.yaml`:

```bash
sed -i "s|age: $PUB_OLD|age: $PUB_OLD,$PUB_NEW|g" platform/.sops.yaml

# count STRUCTURALLY, not with grep: every rule has to have ended up
# with the new key
python3 - <<PY
import yaml
rules = yaml.safe_load(open("platform/.sops.yaml"))["creation_rules"]
with_new = [r for r in rules if "$PUB_NEW" in r.get("age","")]
print(f"rules: {len(rules)}   with the new key: {len(with_new)}")
assert len(with_new) == len(rules), "there are rules WITHOUT the new key"
PY
```

That **all** of them have it is not cosmetic: if one rule is left
without the new key, the files matched by that one `path_regex` stay
behind, and the failure only shows up when somebody touches them.

And the count goes through YAML on purpose. `grep -c "$PUB_NEW"` over
this file returns **4** and not 3, because the header of `.sops.yaml`
mentions the key in a comment. It is exactly the pothole the stack
already has catalogued as H4 / check 41 —«a guard over YAML is done
structurally, never with `grep` over a name, because it matches
comments»— and this guide fell into it on its first writing.

**A.4** Re-encrypt the 39 in the repo.

```bash
cd platform
find . \( -name '*.enc.yaml' -o -name '*.enc.json' \) -print0 \
  | xargs -0 -n1 sops updatekeys --yes
```

`updatekeys` **does not decrypt the content**: it rewrites only the
header's list of recipients. That is why it can run over all 39 without
exposing anything.

**A.5** Re-encrypt the 18 in the store. The store uses a config of its
own, so it gets the double recipient first:

```bash
printf 'creation_rules:\n  - age: %s,%s\n' "$PUB_OLD" "$PUB_NEW" \
  > init/.state-secrets/.sops.yaml
for f in init/.state-secrets/*.enc; do
  sops updatekeys --yes "$f"
done
```

**A.6 — THE VERIFICATION THAT CAN FAIL.** Both sets have to open all
57. With `--yes` in the previous step it is easy for something to have
failed without anybody looking.

```bash
for K in "$HOME/.config/sops/age/aegis.key" /dev/shm/age-new.key; do
  echo "── with $(basename $K) ──"; bad=0
  for f in $(find platform -name '*.enc.yaml' -o -name '*.enc.json') \
           init/.state-secrets/*.enc; do
    SOPS_AGE_KEY_FILE="$K" sops -d "$f" >/dev/null 2>&1 || { echo "  DOES NOT OPEN: $f"; bad=$((bad+1)); }
  done
  echo "  unreadable: $bad"
done
```

**Both passes have to give 0.** If either one does not, **stop here**:
nothing has been taken away yet, so the state is still recoverable. Fix
it and repeat A.4/A.5.

**A.7** Commit. At this point the repo is in a safe state and it is
worth putting that on the record even if there is more to do afterwards.

```bash
cd platform && git add -A && git commit -m "chore(age): double recipient — phase A of the rotation" && git push
```

---

## Phase B — the cluster and the operator move to the new key

**B.1** The Secret that KSOPS uses:

```bash
kubectl -n argocd create secret generic argocd-sops-age \
  --from-file=keys.txt=/dev/shm/age-new.key \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd rollout restart deploy/argocd-repo-server
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=180s
```

**B.2** The operator's key. The old one is **not deleted yet**: it is
kept alongside, because phase C still needs to prove that it has stopped
working.

```bash
cp -a ~/.config/sops/age/aegis.key ~/.config/sops/age/aegis.key.old
install -m 600 /dev/shm/age-new.key ~/.config/sops/age/aegis.key
echo -n "$PUB_NEW" > init/.age-public
```

**B.3** Verify that the cluster is still alive — with a signal that can
fail. A repo-server that cannot decrypt leaves the Apps unreconciled,
and that is not always visible quickly:

```bash
aegis sync --drifted
kubectl get applications -n argocd -o custom-columns=\
'N:.metadata.name,S:.status.sync.status,H:.status.health.status' | grep -v Synced
```

No App should be left `Unknown` or `Degraded`. A `ComparisonError` in
the repo-server is the signature of «it cannot decrypt».

---

## Phase C — the old key stops working

This is the phase that turns «I added a key» into «I rotated the key».
Without it the system is left with two valid roots of trust, which is
worse than before: the old one —the one you meant to retire— still opens
everything.

**C.1** Take the old public half out of the four places:

```bash
sed -i "s|age: $PUB_OLD,$PUB_NEW|age: $PUB_NEW|g" platform/.sops.yaml

python3 - <<PY
import yaml
rules = yaml.safe_load(open("platform/.sops.yaml"))["creation_rules"]
left = [r for r in rules if "$PUB_OLD" in r.get("age","")]
print(f"rules that STILL carry the old one: {len(left)}")
assert not left, "at least one rule is left with the old key"
PY

printf 'creation_rules:\n  - age: %s\n' "$PUB_NEW" > init/.state-secrets/.sops.yaml
```

The header comment of `.sops.yaml` still names the old key: it is
documentation of phase 10, not a recipient. That is why the check goes
through YAML and not through `grep` (see A.3).

**C.2** Re-encrypt the 57 again (the same commands as A.4 and A.5).

**C.3 — THE NEGATIVE TOOTH.** With the new key everything opens; with
the old one **nothing** must open. The second half is the one that
matters: without it, «I rotated» and «I added a key and forgot to take
the other one away» give exactly the same green signal.

```bash
echo "── with the NEW one (expected: 0 unreadable) ──"; bad=0
for f in $(find platform -name '*.enc.yaml' -o -name '*.enc.json') init/.state-secrets/*.enc; do
  sops -d "$f" >/dev/null 2>&1 || { echo "  DOES NOT OPEN: $f"; bad=$((bad+1)); }
done; echo "  unreadable: $bad"

echo "── with the OLD one (expected: ALL unreadable) ──"; open=0
for f in $(find platform -name '*.enc.yaml' -o -name '*.enc.json') init/.state-secrets/*.enc; do
  SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key.old sops -d "$f" >/dev/null 2>&1 \
    && { echo "  STILL OPENS: $f"; open=$((open+1)); }
done; echo "  still opening: $open"
```

What is correct is **0 unreadable with the new one** and **0 still
opening with the old one**. Any file in the second list is a file the
rotation did not reach.

**C.4** Back up again. The bundle from «before starting» no longer opens
with the key you now have.

```bash
aegis state backup
```

**C.5 — WITHDRAW THE OLD KEY. And withdrawing is NOT destroying.**

The first version of this document said `shred -u` here, and nothing
more. That is wrong, and it is the kind of mistake you only discover
once it is too late: the backups are encrypted with
`age -r $AGE_PUBLIC`, so **destroying the old key makes every bundle
taken before the rotation unrecoverable**. As of 2026-08-12 that is 14
bundles (7 in `legado/`, 5 in `plataforma/`, 2 in `org-ejemplo/`), plus
the `.enc` files archived in `init/.state-secrets/.previo/`.

There are two paths and the first one is the good one.

**C.5a — re-encrypt what you can reach (preferred).** It is 152K: it
takes seconds. And it is the only thing that allows destroying the old
one *cleanly*, without leaving a key lying around that can open the
system's material.

```bash
OLD=~/.config/sops/age/aegis.key.old
for b in "$AEGIS_BACKUPS"/*/*.age; do
  age -d -i "$OLD" "$b" | age -r "$PUB_NEW" -o "$b.new" || { echo "FAILED: $b"; continue; }
  # roundtrip BEFORE the mv: nothing is declared re-encrypted without opening it again
  if age -d -i ~/.config/sops/age/aegis.key "$b.new" >/dev/null 2>&1; then
    mv "$b.new" "$b"; echo "  ok  $b"
  else
    rm -f "$b.new"; echo "  ROUNDTRIP FAILED, the original is kept: $b"
  fi
done
```

The `.enc` files in `.previo/` go through `sops updatekeys` like the
rest — they sit under the store's `.sops.yaml`, so C.2 has already
reached them if the glob included them. **Verify that**:
`ls init/.state-secrets/.previo/`.

Only once everything has been re-encrypted and verified:

```bash
shred -u "$OLD"
shred -u /dev/shm/age-new.key      # already in ~/.config and safeguarded
```

**C.5b — withdraw without destroying (when there are copies you cannot
reach).** If there are bundles offsite, in cold storage, or on a disk
that is not plugged in —any copy C.5a cannot touch— then the old key is
**not destroyed**. It is withdrawn, which is a different thing, and it
has requirements:

- **It comes out of every operational place all the same**: the three
  `creation_rules` of `.sops.yaml`, the `argocd-sops-age` Secret,
  `~/.config/sops/age/`. Archived does **not** mean in use: nothing new
  is encrypted with it and no process has it at hand.
- **It goes into the operator's offline safeguard**, with a label saying
  what it opens, from and until what date, and when it may die. A key
  with no label is, six months later, indistinguishable from a live key
  — and nobody dares delete it, so it stays forever.
- **NEVER inside the backup tree it decrypts.** That is circular:
  whoever gets hold of that disk would have the padlock and the key
  together, and the encryption stops protecting absolutely anything. It
  goes where the safeguard of the *current* key lives, which is a
  different place by definition.

The underlying rule, and it applies to any key in the system, not only
to this one: **invalidating for all new use is mandatory; destroying is
a separate decision, and it can only be taken once nothing encrypted
with it matters any more.**

**C.6** Commit and push.

---

## If something goes wrong

| where | what happens | what to do |
|---|---|---|
| phase A | nothing is irreversible: the old key is still a recipient of everything | fix it and repeat A.4/A.5 |
| phase B | the cluster cannot decrypt, but the repo is fine | put the `argocd-sops-age` Secret back to the old key and restart repo-server |
| phase C, before C.5 | the old key still exists | put both recipients back and re-run updatekeys |
| phase C, after C.5a | **the old key no longer exists** | only the safeguard of the new one helps; that is why A.2 comes before everything |
| phase C, after C.5b | the old one exists but is archived offline | recovering it from the safeguard opens the old bundles; nothing else |

The order of this document is not aesthetic. Every step is where it is
so that the previous one stays reversible.

---

## What this protocol does NOT cover

- **The `.enc` files that are not in the two measured trees.** If a
  fourth site with encrypted material turns up, this protocol leaves it
  behind in silence. The count of 39 + 18 is from 2026-08-12:
  **verify it before starting**, do not copy it.
- **Backup copies that are not mounted or reachable** at the moment of
  C.5a. The loop only reaches what it can see. If you have offsite
  bundles, you go in through C.5b, and that is a decision that gets
  written down — not an oversight discovered the day a restore is
  needed.
- **Exercising it.** As of 2026-08-12 this document is written and its
  commands verified one by one against the live instance, but the full
  rotation **has still not been run end to end**. Until it is run, this
  is a plan, not a proven procedure. Write down the date here the first
  time it is executed.
