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
