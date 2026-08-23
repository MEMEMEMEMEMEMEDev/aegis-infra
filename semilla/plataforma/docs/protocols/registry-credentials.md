# Protocolo: credenciales del registry (htpasswd + regcreds)

Salda C9/C10 parcial y codifica A27: htpasswd y sus 4 derivados son
UNA credencial con 5 caras — se generan JUNTOS o se desincronizan
(caso real v1: 6 días de mismatch → 401 en el primer push).

## Regla de oro

**Un origen, un proceso, un commit.** El init lo hace estructural
(`derive_htpasswd_and_regcreds` en lib/secrets.sh); a mano, TODO en
la misma shell antes de cualquier unset/exit.

## Flujo manual (si no se usa el init)

    mkdir -p /dev/shm/regcred && cd /dev/shm/regcred
    openssl rand -base64 32 | tr -d '\n' > pass    # → Bitwarden
    # htpasswd bcrypt vía STDIN (jamás el password en argv —
    # /proc/PID/cmdline es legible):
    htpasswd -nBi aegis-dev < pass > htpasswd
    # dockerconfigjson con jq --rawfile (ídem: nunca argv):
    jq -n --rawfile p pass --arg u aegis-dev \
      --arg h registry.registry-system.svc.cluster.local:5000 \
      '{auths:{($h):{username:$u,password:$p,
        auth:(($u+":"+$p)|@base64)}}}' > dockerconfig.json

Después, POR CADA destino (registry-system/htpasswd + los 4
regcred: jenkins-system, argocd, kyverno, org-personal): kubectl
--from-file → mv al path del repo → sops -e --in-place → roundtrip.
UN commit con los 5 archivos.

## Notas

- `data:` siempre (byte-preserving); el protocolo v1 de laptop
  usaba stringData para el htpasswd — funcionaba porque bcrypt es
  ASCII sin folding, pero v2 unifica: data/--from-file SIEMPRE (una
  regla sin excepciones vale más que la explicación de la
  excepción).
- Deuda heredada consciente: htpasswd es all-or-nothing (sin
  pull/push separation). Trigger de separación: primer tenant
  no-trusted / Hetzner (token-based auth, lift grande).
- El test definitorio de las creds es cliente→servidor real (un
  push y un pull), no `--get-login` ni el plan verde.
