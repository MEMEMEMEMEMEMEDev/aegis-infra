# Protocol: a project's API key against the AI gateway

Blast radius: whoever holds the key can spend the GPU within the
project's budgets, invoking ONLY the tasks that name it in the
registry. It cannot ask for free-form prompts, it cannot read another
project's conversations, it cannot touch the cluster. It is a
CONSUMPTION credential, not a control one — deliberately boring.

Design reference: `docs/architecture/ai-gateway.md` §7.1.

## The key is split in two, on purpose

| Half | Where it lives | Why there |
|---|---|---|
| **hash** SHA-256 | `ai-system/ai-keys` (`keys.json`) | the gateway only needs to verify |
| **cleartext** | `org-<project>/ai-gateway-key` | rotating it is an act of the PROJECT, not of the platform |

The gateway never sees the cleartext stored anywhere: it receives it in
the header and compares it against the hash. Losing the project's
Secret means issuing a new key, not recovering the old one.

## 1. Issue it (tmpfs, the cleartext never touches unencrypted disk)

    D=$(mktemp -d /dev/shm/aegis-ai.XXXXXX) && chmod 700 "$D"

    # The `aegisk_<project>_` prefix is DELIBERATE: it makes a leaked
    # key greppable by a secret scanner. Hiding the format protects
    # nothing —whoever has it already has it— and it does stop the
    # leak from being detected.
    KEY="aegisk_<project>_$(head -c 24 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')"
    printf '%s' "$KEY" > "$D/clave"
    HASH=$(printf '%s' "$KEY" | sha256sum | cut -d' ' -f1)

## 2. Write the two halves

`kid` identifies WHICH key was used: it shows up on every log line and
it is what makes rotating possible without guessing who is still using
the old one.

    printf '{"claves":[{"tenant":"org-<project>","kid":"<proj>-1","sha256":"%s"}]}\n' \
      "$HASH" > "$D/keys.json"

    # --from-file and not --from-literal: byte-preserving. A stringData
    # assembled by hand adds a byte from the YAML folding.
    kubectl create secret generic ai-keys -n ai-system \
      --from-file=keys.json="$D/keys.json" --dry-run=client -o yaml > "$D/s1.yaml"
    kubectl create secret generic ai-gateway-key -n org-<project> \
      --from-file=clave="$D/clave" --dry-run=client -o yaml > "$D/s2.yaml"

    # mv to the repo's path FIRST, sops AFTERWARDS: the creation_rule
    # matches by path_regex and /dev/shm does not match.
    mv "$D/s1.yaml" k8s/base/ai-system/secret-ai-keys.enc.yaml
    mv "$D/s2.yaml" k8s/organizations/org-<project>/secret-ai-gateway-key.enc.yaml
    sops -e --in-place k8s/base/ai-system/secret-ai-keys.enc.yaml
    sops -e --in-place k8s/organizations/org-<project>/secret-ai-gateway-key.enc.yaml

    find "$D" -type f -exec shred -u {} \; && rmdir "$D"

Add both files to the corresponding `secret-generator.yaml` (an
explicit list, A7: no globs).

## 3. Validate the roundtrip BY LOOKING AT THE EXIT CODE

    export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/aegis.key"
    sops -d <file> > /dev/null && echo OK || echo FAILED

Do **not** validate with `sops -d ... | head -c 1`. When sops fails it
writes `Failed to get the data key...` to stderr, `head -c 1` prints
the `F` and the `&&` goes green: the check confirms exactly the
opposite of what happened. It bit on 2026-08-02 and it is the same
class we already know —*the check tied to the letter instead of to the
invariant*—, here disguised as "but I did test it".

Mind the path: this instance's identity is `aegis.key`, not the
`keys.txt` sops looks for by default. Without `SOPS_AGE_KEY_FILE`, sops
fails with "no such file or directory" even though the file exists.

## 4. Authorize the task AND the network

A key on its own is not enough. Both are needed:

1. The project has to be in the `tenants` of every task in the registry
   (`k8s/base/ai-system/registro.yaml`).
2. The namespace has to have a NetworkPolicy rule towards the internal
   door: one in `ai-system` (`allow-tenants-a-gateway`) and an egress
   one in the tenant itself. Every permission is born with its
   consumer.

If (1) is missing the gateway answers 403 and it shows. If (2) is
missing the connection dies by timeout and the symptom is uglier — that
is why they travel together.

## 5. Rotate (with no downtime window)

The verifier accepts **several keys at once**: that is the whole
rotation machinery.

1. Issue the new one with a different `kid` (`<proj>-2`) and add it to
   the `claves` array **without removing the old one**.
2. Update the project's Secret with the new cleartext; the pod picks
   the variable up when it restarts.
3. Confirm in the gateway's logs that the old `kid` no longer appears
   (`"kid":"<proj>-1"`).
4. Only then remove the old entry from the array.

The gateway reloads the keys file hot every 30 s: it does not have to
be restarted at any step. And if the new file is badly written, it
keeps the previous one and shouts about it in the log — a rotation with
a typo does not leave the service authenticating nobody.

## 6. Emergency revocation

Remove the entry from the array and sync. Effect in ≤30 s, no
restarts. If ALL consumption has to be cut right now, the real cut is
`aegis ai stop`: with no engine there is nothing to spend.
