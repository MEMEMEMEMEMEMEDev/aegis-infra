# Protocolo: keypair cosign (la autoridad de firma del cluster)

Salda C3. Blast radius: quien tenga `cosign.key` + password firma
imágenes "válidas" para Kyverno => decide QUÉ CORRE en el cluster.
Tratarla como la age key: ceremonia con validación real.

## 1. Generar (tmpfs, ownership correcto)

    mkdir -p /dev/shm/cosign-gen && cd /dev/shm/cosign-gen
    # password random (NO elegida — patrón random+Bitwarden):
    openssl rand -base64 32 | tr -d '\n' > pass
    # bache conocido: en container el keypair queda owned por uid
    # 65532 — SIEMPRE --user:
    docker run --rm -it --user "$(id -u):$(id -g)" \
      -v /dev/shm/cosign-gen:/work -w /work \
      -e COSIGN_PASSWORD="$(cat pass)" \
      ghcr.io/sigstore/cosign/cosign:v2.6.3 generate-key-pair
    # (con cosign nativo en el host: cosign generate-key-pair a secas)

## 2. Ceremonia de resguardo (como la age)

- Password → Bitwarden AHORA ("aegis cosign password").
- VALIDAR el resguardo con roundtrip REAL (no "sí, la guardé"):
  re-tipear la password DESDE Bitwarden y firmar+verificar un blob:

      COSIGN_PASSWORD=<retipeada> cosign sign-blob --key cosign.key \
        --tlog-upload=false --output-signature s.sig blob
      cosign verify-blob --key cosign.pub --signature s.sig blob

## 3. Destinos

- `cosign.key` + password → Secret `cosign-signing-key`
  (jenkins-system) vía flujo KSOPS (data/--from-file, mv-antes-de-
  sops, roundtrip).
- `cosign.pub` es T1 → al repo en claro
  (`k8s/base/platform/cosign/cosign.pub`) Y inline en la
  ClusterPolicy de Kyverno.
- shred del directorio tmpfs completo.

## 4. Uso en pipeline (referencia para consumidores)

`cosign sign --yes --key <mounted>/cosign.key --tlog-upload=false
--registry-cacert <ca> <registry>/<img>@<DIGEST>` — SIEMPRE por
digest (--digestfile de buildah), NUNCA por tag (TOCTOU). cosign v2
mientras el registry sea distribution 3.x (v3 exige referrers API).

## 5. Rotación (2 PASOS — más compleja que las demás)

1. Nuevo keypair + ceremonia + re-cifrar el Secret.
2. Actualizar cosign.pub en git Y la policy de Kyverno, y
   **RE-FIRMAR todas las imágenes desplegadas** que la policy
   cubra — si no, el próximo restart de un pod viejo es rechazado.
   Orden seguro: policy en Audit → re-firmar → volver a Enforce.
