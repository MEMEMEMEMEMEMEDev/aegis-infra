# Convención de secretos v2

Consolida las reglas que en v1 vivían dispersas (salda C4/C7/C8).

## Clasificación

- **TIPO 1** (conocido): certs públicos, dominios, host keys,
  pins, IDs de cuenta → declarativo en git, desde fuente oficial.
- **TIPO 2** (secreto): tokens, private keys, passwords → SOPS+age,
  flujo con el operador. Sub-clases: T2-A (autogenerable:
  `openssl rand`, `ssh-keygen`, `age-keygen`, `cosign
  generate-key-pair`) y T2-E (lo emite un tercero).
- **JAMÁS TOFU**: prohibido StrictHostKeyChecking=no,
  insecure-skip-tls-verify, accept-first-connection, keyscan en
  init containers.

## Reglas duras (cada una nació de un incidente)

1. Secrets K8s por `data:` byte-preserving (`kubectl create secret
   --from-file --dry-run=client -o yaml`). NUNCA `stringData`
   armado a mano: el folding YAML agrega 1 byte y rompe HMACs.
2. **SOPS: `mv` al path del repo PRIMERO, `sops -e --in-place`
   DESPUÉS.** La creation_rule matchea por path_regex; /dev/shm no
   matchea. Validar SIEMPRE con roundtrip `sops -d | head -c1`.
3. Material en claro SOLO en tmpfs (/dev/shm), chmod 700, shred al
   salir. Nunca /tmp, nunca el repo, nunca el home.
4. Secretos JAMÁS en argv (`/proc/PID/cmdline` es legible):
   `--from-file`, `htpasswd -nBi` (stdin), `jq --rawfile`.
5. Nunca imprimir valores — ni base64. Shape-checks: SOLO longitud
   (`wc -c` sobre archivo). `kubectl get secret <n>` sin `-o`.
6. Credenciales compartidas (htpasswd↔regcreds, HMAC↔webhook):
   UN origen, derivación en el MISMO proceso, UN commit.
7. `type` de un Secret es INMUTABLE: para cambiarlo, `kubectl
   delete` + selfHeal recrea desde git. Jamás Replace=true
   permanente en la App.
8. KSOPS generators: LISTA EXPLÍCITA de files. App Synced+Healthy
   NO garantiza los Secrets — validar `kubectl get secret`
   post-sync SIEMPRE.
9. La age key: path custom (`~/.config/sops/age/aegis.key`), jamás
   `keys.txt`; `SOPS_AGE_KEY_FILE` exportada EXPLÍCITA en todo
   shell non-interactive (direnv no llega ahí).
10. Excepción de exposición deliberada: la CEREMONIA (age, cosign)
    muestra el valor UNA vez para resguardo del operador, con gate
    ROJO antes y validación por roundtrip después. Es la única.
11. Irreemplazables (age, cosign, write key): resguardo VALIDADO
    (canary cifrado/firmado con la copia resguardada), no
    confirmación verbal.
12. Del lado del host: python3+pyyaml, no yq. Pasos de
    revert/cleanup NUNCA con `&&`.
