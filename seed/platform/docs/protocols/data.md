# Protocol: the tenants' data — capture, restore, weight

`aegis state backup` takes the platform's STATE (the store's secrets,
the init's trail, the edge's tfstate). This one takes what the
tenants GENERATED: their databases and their objects. **Neither half
is any good alone**: with the state you raise an empty platform, with
the data you have a dump nobody knows where to put.

    aegis data backup                    # one bundle per organization
    aegis data list <bundle.age>         # what is inside, without restoring
    aegis data restore <bundle.age> --org <org>
    aegis data size                      # what it weighs, as metrics

The decisions and their measurements live in the command's own header
— it is the document that cannot go stale, because it sits next to the
code it describes. What follows is what the OPERATOR needs, and above
all how each half is proven on a live instance.

## 1. Golden rule

**A restore that finishes is not a restore; a restore that is measured
is.** Twice now the command reported success over a state nobody would
have called restored: once over a database that had been deleted
(2026-08-09), once over an organization that could not log into its own
database (2026-08-27). Every half therefore measures its result against
the manifest — tables and rows for the database, size and count for the
objects — and refuses to call it good if they do not match.

## 2. What restoring does, in order

1. It opens the bundle with the age key and checks EVERY piece against
   its sha256 — the SQL files and each object of the bucket. Nothing is
   written before that, and it is the WHOLE bundle and not each piece as
   its turn comes up: a mismatch on the last object has to stop the
   restore before the first one is uploaded, never after.
2. It compares the manifest's credential fingerprint against the live
   Secret's. A difference is a brake with `--force`, and the brake is
   not about repair — the role is realigned three steps below — it is
   about the DECISION: restoring a machine and moving an organization
   into a new one are not the same operation.
3. It scales the organization's consumers to zero and cuts the leftover
   sessions, because a `pg_dump --clean` drops objects the application
   may be using. That window covers BOTH halves and it is opened once:
   it closes when the objects and the databases are back. They come up
   again NO MATTER WHAT: leaving the organization at zero replicas would
   turn a failed restore into an outage.
4. **It puts the objects back** into the bucket, with the credential of
   the destination instance. They go before the databases, and inside
   the window, for a reason worth writing down: the rows point at the
   objects. A row without its object is a 404 in front of a user; an
   object without its row is an orphan nobody notices. If this ever
   stops halfway, it stops on the side that hurts less.
5. It loads the roles (globals) and then each database.
6. **It realigns the role** with the live Secret and PROVES it, opening
   the database with that credential. It is the last thing before the
   consumers return: the pods come back looking for the database, and
   finding it with the password from the capture would give them a crash
   loop whose message —authentication failed— points at the application
   and not at the restore.
7. It measures: the databases' tables and rows against the manifest, the
   objects' size and count against the bucket's own listing.

### The objects, and what it does with what is already there

An object that is already in the bucket is **overwritten unless it is
identical**. Restoring means bringing the organization back to the
captured state, and the database half already overwrites; skipping the
objects would leave the two halves at different dates, which is exactly
the inconsistency this command exists to avoid. Identical is compared by
CONTENT and not by name, so re-running a restore is cheap and what the
report says it wrote is what actually changed.

An object the bucket has and the bundle does not is **named, never
deleted**: it is later than the capture, and deleting it would turn a
restore into a loss no bundle can undo.

## 3. How each half is PROVEN on a live instance

The three below need a cluster; none of them can be seen from the static
verifier, which is why they are written down here.

**The role is in step.** After a restore, without touching anything:

    kubectl -n org-<org> rollout status deploy/<app>

The application comes up on its own. If it does not, the restore already
said so — it dies when the live credential does not open the database,
instead of reporting success and leaving the diagnosis to whoever finds
the crash loop.

**The objects came back.** `aegis data list` prints how many objects and
how many bytes the bundle carries; the restore prints the same two
figures read back from the bucket, per object and in total. They have to
be the same numbers, and if an object is not there afterwards the
command says which one and stops.

**The weight.** `aegis data size` prints the series on stdout and a
readable line per source on stderr. The figures are the ones postgres
and the bucket report about themselves, not the size the PVC requested.

## 4. The measurement

The instance's storage class is of local path: it does not measure or
limit the disk a PVC really uses, so the cluster cannot answer how much
an organization weighs — what `kubectl` gives back is what was ASKED
FOR. A number nobody can obtain is a number nobody watches, and the
first sign of a full disk is postgres refusing to write.

| series | labels | what it says |
|---|---|---|
| `aegis_org_database_bytes` | org, service, database | what each database occupies, according to postgres |
| `aegis_org_bucket_bytes` | org, bucket | what the objects add up to, according to the bucket's listing |
| `aegis_org_bucket_objects` | org, bucket | how many objects there are |
| `aegis_org_data_measured_timestamp_seconds` | org | when it was last measured |

The timestamp is not decoration: a gauge that stops being written keeps
its last value for ever, and without something dated to compare against,
stale is indistinguishable from healthy. It is the same pair the image
watch uses.

The command pushes nothing. Where the series go —a host timer, the round
of checks— is decided outside, because a tool that measures and also
decides where to report is a tool you cannot use for anything else.

## 5. Notes

- Every capture runs from the operator's side and not from inside the
  cluster. It is not a preference: the namespaces with data are
  `restricted` and their egress is closed except for DNS, so a Job in
  there could dump the database and could not get the dump out. The
  header of the command has the four measurements.
- The credential never travels in argv (`/proc/PID/cmdline` is
  readable): the statement that sets the role's password goes as psql's
  script over stdin, and the verification reads the password with a
  `read` inside the container. Check 154 measures this over the whole
  file.
- The login is proven over the loopback interface and not over the unix
  socket. Over the socket it would prove nothing: the image's `pg_hba`
  trusts local connections, so a wrong password would get in all the
  same and the test would be green by construction.
- If the age key is lost, every bundle is a brick. There is no partial
  recovery. The key goes to offline safekeeping, and to a DIFFERENT
  place from the backups disk.
