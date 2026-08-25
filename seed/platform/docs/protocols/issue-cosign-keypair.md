# Protocol: cosign keypair (the cluster's signing authority)

Settles C3. Blast radius: whoever holds `cosign.key` + password
signs images that are "valid" for Kyverno => decides WHAT RUNS in
the cluster. Treat it like the age key: a ceremony with real
validation.

## 1. Generate it (tmpfs, correct ownership)

    mkdir -p /dev/shm/cosign-gen && cd /dev/shm/cosign-gen
    # random password (NOT chosen — the random+Bitwarden pattern):
    openssl rand -base64 32 | tr -d '\n' > pass
    # known snag: inside a container the keypair ends up owned by
    # uid 65532 — ALWAYS --user:
    docker run --rm -it --user "$(id -u):$(id -g)" \
      -v /dev/shm/cosign-gen:/work -w /work \
      -e COSIGN_PASSWORD="$(cat pass)" \
      ghcr.io/sigstore/cosign/cosign:v2.6.3 generate-key-pair
    # (with cosign native on the host: plain cosign generate-key-pair)

## 2. Safekeeping ceremony (like the age one)

- Password → Bitwarden NOW ("aegis cosign password").
- VALIDATE the safekeeping with a REAL roundtrip (not "yes, I saved
  it"): retype the password FROM Bitwarden and sign+verify a blob:

      COSIGN_PASSWORD=<retyped> cosign sign-blob --key cosign.key \
        --tlog-upload=false --output-signature s.sig blob
      cosign verify-blob --key cosign.pub --signature s.sig blob

## 3. Destinations

- `cosign.key` + password → Secret `cosign-signing-key`
  (jenkins-system) through the KSOPS flow (data/--from-file,
  mv-before-sops, roundtrip).
- `cosign.pub` is T1 → into the repo in the clear
  (`k8s/base/platform/cosign/cosign.pub`) AND inline in Kyverno's
  ClusterPolicy.
- shred the whole tmpfs directory.

## 4. Use in a pipeline (reference for consumers)

`cosign sign --yes --key <mounted>/cosign.key --tlog-upload=false
--registry-cacert <ca> <registry>/<img>@<DIGEST>` — ALWAYS by
digest (buildah's --digestfile), NEVER by tag (TOCTOU). cosign v2
for as long as the registry is distribution 3.x (v3 demands the
referrers API).

## 5. Rotation (2 STEPS — more involved than the rest)

1. New keypair + ceremony + re-encrypt the Secret.
2. Update cosign.pub in git AND Kyverno's policy, and **RE-SIGN
   every deployed image** the policy covers — otherwise the next
   restart of an old pod is rejected. Safe order: policy to Audit →
   re-sign → back to Enforce.
