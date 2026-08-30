# Protocol: the backups leave the house

`docs/protocols/data.md` says how a bundle is made and how it is put
back. This one answers the question that one does not: **where does the
bundle live when the machine that made it is gone.**

Until 2026-08-29 the answer was «on a second disk of the same house».
The command said so out loud at the end of every run — *«without a sink
the bundle stays on the SAME machine you want to survive»* — and saying
it is not fixing it. Measured that morning on the live instance: the
newest bundle was three days old and had been made by hand.

    aegis data remote bucket                 # the destination's name, derived
    aegis data remote adopt --credentials-file <file>
    aegis data remote list                   # what is out there, and how old
    aegis data remote status                 # its freshness, as metrics
    aegis data remote push <bundle.age>      # send out a bundle made elsewhere
    aegis data remote cadence --set 6h       # the clock

## 1. What is backed up, and what is NOT

**In the bundle**, one per organization, encrypted with the instance's
age key:

| | |
|---|---|
| the databases | `pg_dumpall --globals-only` for the roles plus one `pg_dump --clean` per database. The roles live outside any database and a plain dump loses them. |
| the objects | every object of the organization's bucket, with its key and its sha256. |
| the fingerprint | the sha256 of the live credential — never the credential. |

**NOT in the bundle, and this is measured and not an oversight:**

- **the internal registry.** `registry-system` holds a 10 Gi volume of
  image layers, and none of it is in any bundle. It does not need to
  be: every image in there is rebuilt from a `Containerfile` that lives
  in a git repo, on a base that is mirrored from a tag and a digest
  written down in `seed/platform/mirror-images/images.txt`. Backing up
  the registry would be backing up a cache — ten gigabytes of something
  reproducible, against a ten gigabyte shelf that has to hold what is
  NOT reproducible.
- **the model volumes of the AI subsystem.** Same reason and more so:
  they are weights downloaded from a public origin, they are the
  largest thing on the machine, and a copy of them would fill the free
  tier on its own while protecting nothing that cannot be fetched again.
- **the age key.** On purpose, with a guard that aborts the capture if
  it appears inside. See section 6 — it is the half of this that is not
  a file on a shelf.
- **the platform's STATE.** `aegis state backup` writes it into the
  same tree and does not yet know how to send it anywhere. Until it
  does, that half leaves by hand:

      aegis data remote push ~/aegis-backups/platform/aegis-state-<ts>.age

  Do not skip it. With the data and without the state you have a dump
  nobody knows where to put.

## 2. Where it goes, and how the destination is made

Cloudflare R2, in the account that already holds the zone and the
tunnel. It was chosen for one property that matters only once: **it
does not charge for downloading**, and a recovery is one long download.
On a provider that charges for egress, the day you need the data is the
day it costs money, and a recovery that costs money is a recovery that
gets postponed.

The bucket is created by hand, once, and not by a phase. The reason is
an order: the bucket has to exist before the credential that writes
into it is worth anything, and phase 15 — where that credential is
minted — runs long before this instance has any data.

```bash
cd "$AEGIS_HOME/platform/tofu"
# The wrapper injects the TUNNEL token, which cannot create a bucket
# (that is `Workers R2 Storage Edit`, another permission group). This
# env is the one place in the tree that overrides it, through the same
# door CI uses.
export TF_VAR_cloudflare_api_token="<a token with Workers R2 Storage Edit>"
export TF_VAR_backups_bucket="$(aegis data remote bucket)"
./tofu-apply.sh -chdir=envs/data-r2 init
./tofu-apply.sh -chdir=envs/data-r2 plan
./tofu-apply.sh -chdir=envs/data-r2 apply
git -C "$AEGIS_HOME/platform" add tofu/envs/data-r2/terraform.tfstate.enc.json
git -C "$AEGIS_HOME/platform" commit -m "estado del bucket de respaldos"
```

That last commit is not optional: without it the next recovery does not
know this bucket exists.

**The name is derived, never typed.** `aegis data remote bucket` builds
it from the instance's root domain, and it is the same derivation the
upload uses. Three places write that name — the tofu, the access policy
of the token, and the PUT — and two of them agreeing while the third
does not is a backup that reports success against a bucket nobody made.

**The retention is R2's, not the instance's.** Ninety days, deleted by
the far side. Deleting is the one operation an attacker who owns the
backed-up machine would most like to have, so the token that machine
holds cannot do it: it writes objects and nothing else. The rule also
aborts interrupted uploads after a day — their parts count towards the
stored bytes and no listing shows them, which is how a free tier gets
exhausted by something invisible.

**The bucket is private by absence.** R2 serves nothing publicly until
a custom domain or the managed `r2.dev` subdomain is attached to it.
Neither is declared, and neither should ever be: a public bucket of
backups is every bundle this platform ever wrote, handed over for
offline cracking. There is no `public = false` to read in the tofu —
the guarantee is what is not there, which is why check 153 watches for
the two resource types that would break it.

## 3. The credential

Phase 15 mints it with the ephemeral master credential, in the same
breath as the three Cloudflare tokens, and it is scoped to **one
bucket**: `Workers R2 Storage Bucket Item Write` is a bucket-level
permission group, so the token reads, writes and lists objects in the
bucket its policy names and touches nothing else in the account.

The S3 pair is derived the way Cloudflare documents it, and this was
verified against `developers.cloudflare.com/r2/api/tokens` rather than
remembered:

- Access Key ID = the API token's `id`.
- Secret Access Key = the SHA-256 of the API token's `value`.

Getting that wrong is the worst way to be wrong here — the mint
succeeds, the phase goes green, and the failure appears on the day
somebody needs the copy — so `aegis data remote adopt` **lists the
destination with the derived pair before storing it**, and refuses to
store one the destination rejects.

If you are adopting a destination by hand (a pair created in the
dashboard, or an instance born before this existed), write the two
values into a file in tmpfs and hand it over. Never on the command
line: `/proc/PID/cmdline` is world-readable.

```bash
install -m600 /dev/null /dev/shm/r2
printf '%s\n%s\n' "<access key id>" "<secret access key>" > /dev/shm/r2
aegis data remote adopt --credentials-file /dev/shm/r2
shred -u /dev/shm/r2
```

## 4. The clock

The timer runs every 24 hours. It is a **user** unit, and that is the
whole identity story: the capture needs the operator's age key, their
kubeconfig, and a `kubectl exec` into every tenant. Running it as root
would hand root the key that opens every bundle this platform ever
wrote, to save writing `--user`.

```bash
mkdir -p ~/.config/systemd/user ~/.config/aegis
cp /usr/local/share/aegis/systemd/aegis-backup.{service,timer} ~/.config/systemd/user/
printf 'AEGIS_ROOT=%s\nAEGIS_HOME=%s\nSOPS_AGE_KEY_FILE=%s\n' \
    "$AEGIS_ROOT" "$AEGIS_HOME" "$HOME/.config/sops/age/aegis.key" \
    > ~/.config/aegis/backup.env
systemctl --user daemon-reload
systemctl --user enable --now aegis-backup.timer
loginctl enable-linger "$USER"
```

**That last line is not decoration.** A user timer only runs while the
user has a session. Without lingering, the backups stop the day the
operator logs out and nothing says so — the unit stays `enabled`, the
timer looks healthy, and the destination quietly stops receiving
copies.

### Changing the cadence

Between 1 hour and 24 hours, freely:

    aegis data remote cadence --set 6h

**Under 1 hour the command asks for a code that arrives on the
operator's phone**, over the platform's own ntfy, and it has to be typed
back beside the word `entendido`. The code is generated with the random
source meant for secrets, and it is never printed, never logged and
never written to any file on this machine — the whole property is that
the answer cannot be produced by whoever holds the terminal.

Three refusals, and none of them degrades into the next:

1. **No operator.** With `AEGIS_NONINTERACTIVE`, or with stdin not a
   terminal, there is nobody to read a phone. Answering «assume yes»
   here would turn the whole door into a comment.
2. **No second channel.** If ntfy is not configured, the code has
   nowhere to go, and a confirmation typed at the same keyboard would
   be theatre. It refuses; it does not fall back to «trust me».
3. **A wrong code, or a missing word.** The word is not decoration: it
   is what stops a code pasted by reflex from being a confirmation of
   something nobody read.

Who confirmed and when is appended to
`$AEGIS_HOME/.init-state/backup-cadence.jsonl`. The code is not.

And the honest limit: **this is a brake on the tooling, not a lock on
the machine.** A hand with a text editor can write the systemd drop-in
directly. What the door buys is that the path the tools take cannot be
walked alone, and that the decision leaves a name and a date behind it.

### Why one hour and not less

Not the disk. Every run opens a port-forward per bucket, runs a
`pg_dumpall` and a `pg_dump` per database **against the live server of
every tenant**, downloads every object, and pushes the whole bundle to a
third party. Under an hour that stops being a backup and becomes a
load: on the tenants' postgres, on a household uplink, and on a free
tier that is counted in operations as well as in bytes. The command
prints that estimate, from the bundles that are actually at the
destination, before it asks for the code.

## 5. Restoring on a machine that is not this one

The order is the one that matters. Everything else is in `data.md`.

1. **Install the age key first.** Nothing below works without it, and
   nothing below tells you so in those words — you get «the bundle does
   not decrypt», which reads like a corrupt download.
2. Run the init on the new machine so that there is a platform, an
   instance and a store. It will generate ITS OWN credentials; that is
   correct and it is the reason step 5 exists.
3. Adopt the destination on the new machine (section 3) and look:

       aegis data remote list

   The bundles are under `org-<name>/` and `platform/`, each one beside
   a `.manifiesto.json`. **A bundle with no manifest is named and not
   counted**: it cannot be checked before restoring, and a copy that
   cannot be checked is not a copy.
4. Bring each organization back. What comes down is compared against
   its manifest **before anything is written**, which is the same order
   the restore of a bucket follows inside a bundle:

       aegis data restore --from-remote org-<name>/aegis-datos-org-<name>-<ts>.age --org <name>

5. Expect the credential brake. The fingerprint in the bundle is the
   one from the machine that is gone, and this machine minted its own —
   that difference deserves a person, because restoring a machine and
   moving an organization into a new one are not the same operation.
   `--force` goes past it; the role is realigned with the live Secret
   either way.

## 6. The two uncomfortable truths

**The offline copy of the age key is the other half of the backup.**
R2 without that key returns files nobody can open. There is no
recovery, not partial and not by brute force. So:

- the key does not travel in any bundle, by design and with a guard
  that aborts the capture if it appears inside;
- the key must live somewhere that is **not** this machine and **not**
  this Cloudflare account. If both halves live together, one accident
  takes both;
- a copy of the key that nobody has ever tested restoring with is a
  copy nobody knows works.

**R2 lives in the same account as the DNS and the tunnel.** If that
account is lost — closed, hijacked, suspended — the public names, the
way in, and the off-site copies all go at once. That is tolerable and
it is deliberate: the bundle is ciphertext, so what an attacker on that
account gains is the ability to delete copies and to see how many there
are, not to read one. It is tolerable, and it is not invisible: a
second destination, in another account or another provider, is the only
thing that fixes it, and this instance does not have one.

## 7. Rotating the R2 pair

By hand, today, and this section exists because `aegis rotate` does not
know how yet: its inventory lists `r2_access_key_id` and
`r2_secret_access_key` under **material with NO RECIPE**, which is
correct and must not be silenced. What is missing is a recipe in that
command's table, class `normal`, third party Cloudflare, blast radius
«the off-site copy stops leaving the machine».

Until then: mint a new scoped token in the dashboard for the same
bucket, derive its pair (section 3), adopt it — `adopt` proves it
against the destination before replacing what is stored — run one
`aegis data backup` to confirm the bundle still leaves, and only then
revoke the old token.

## 8. What is still missing

- **An alert.** There is no rule yet for «the newest bundle at the
  destination is older than twice the cadence», and there cannot be one
  until something inside the cluster produces the series: the platform's
  alert audit requires every own metric a rule reads to have a producer
  with a declared cadence, and this producer is a host timer, which that
  audit does not know how to see. `aegis data remote status` already
  emits the series (`aegis_backup_remote_timestamp_seconds` and its
  companions); what is missing is the road from the host into the
  metrics store, and the audit learning that a `share/systemd` timer is
  a producer with the cadence its `.timer` declares.
  Until then the freshness is checked by running that command.
- **The state bundle leaving on its own** (section 1).
- **A second destination**, in another account (section 6).
