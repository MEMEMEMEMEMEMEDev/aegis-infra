# .sops.yaml del repo de plataforma v2 — TEMPLATE. La fase 10 del
# init reemplaza __AGE_PUBLIC__ con la pública recién generada.
# Regla A4: este archivo SOMBREA al del workspace — TODA regla
# necesaria vive acá, no se hereda nada.
# Rotación de la age key: actualizar recipient + `sops updatekeys`
# sobre TODOS los cifrados (ver protocolo rotate-age-key).
creation_rules:
  # Secrets K8s cifrados (KSOPS): solo data/stringData
  - path_regex: k8s/.*\.enc\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: __AGE_PUBLIC__
  # tokens de tofu: todo cifrado salvo metadata de auditoría
  - path_regex: tofu/secrets/.*\.enc\.yaml$
    unencrypted_suffix: _unencrypted
    age: __AGE_PUBLIC__
