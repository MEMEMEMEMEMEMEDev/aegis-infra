# The platform repo's .sops.yaml — TEMPLATE. The init's phase 10
# replaces __AGE_PUBLIC__ with the freshly generated public key.
# Rule A4: this file SHADOWS the workspace's — EVERY rule that is
# needed lives here, nothing is inherited.
# Rotating the age key: update the recipient + `sops updatekeys` over
# ALL the encrypted files (see the rotate-age-key protocol).
creation_rules:
  # Encrypted K8s Secrets (KSOPS): only data/stringData
  - path_regex: k8s/.*\.enc\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: __AGE_PUBLIC__
  # tofu's tokens: everything encrypted except the audit metadata
  - path_regex: tofu/secrets/.*\.enc\.yaml$
    unencrypted_suffix: _unencrypted
    age: __AGE_PUBLIC__
  # tofu's STATE. It was NOT here until 2026-08-31, and the hole was
  # quiet in the worst way: the wrapper encrypts the state after every
  # apply, sops answered «no creation rules», and the apply had already
  # created the resources. So the state — which carries the tunnel
  # token and the Access service token's secret, because a state holds
  # what the API answered — stayed in PLAINTEXT on disk while the
  # encrypted copy beside it aged. On the previous lineage's machine
  # that encrypted copy was TEN DAYS STALE and nobody knew.
  #
  # No `encrypted_regex` here, unlike the k8s rule: in a Secret only
  # data/stringData is sensitive and the rest is what makes a diff
  # readable. A tofu state has no such split — the token is in an
  # attribute, the id is in another, and which attributes are sensitive
  # changes with the provider. Everything, then.
  - path_regex: tofu/envs/.*/terraform\.tfstate\.enc\.json$
    age: __AGE_PUBLIC__
