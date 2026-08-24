// Jenkinsfile.app — TEMPLATE v2 para apps consumidoras de la
// plataforma aegis (copiar al repo de la app y ajustar CHANGEME).
// Es el pipeline del canary hello-aegis v1 destilado: build →
// scan → push → sign → report, con el anti-loop de Image Updater
// y todas las lecciones A* horneadas. Cambiar SOLO lo marcado
// CHANGEME; el resto es contrato con la plataforma (pins, secrets,
// limits — si algo de eso no te sirve, el cambio va en ops-stack,
// no acá).
//
// Prerrequisitos en el namespace del tenant jenkins-system (los
// crea el init / el protocolo registry-credentials.md):
//   - Secret regcred-internal (dockerconfigjson del registry)
//   - Secret aegis-ca-trust (ca.crt del CA interno)
//   - Secret cosign-signing-key (cosign.key + cosign.password)
pipeline {
  agent {
    kubernetes {
      // RQ estricta de jenkins-system: TODO container declara
      // limits (incluido jnlp — NUNCA `yaml ''`, pisa el default).
      yaml '''
apiVersion: v1
kind: Pod
spec:
  imagePullSecrets:
  - name: regcred-internal
  containers:
  - name: jnlp
    image: jenkins/inbound-agent:3355.v388858a_47b_33-23
    resources:
      requests: { cpu: 500m, memory: 512Mi }
      limits:   { cpu: 1000m, memory: 1Gi }
  # node: SOLO para la etapa `desplegar`, que escribe el digest en el
  # overlay. No compila la app —de eso se encarga kaniko desde el
  # Containerfile—, así que los límites son chicos a propósito. Si tu app
  # necesita `npm ci` en el pipeline, subilos acá.
  #
  # Imagen del registry interno, igual que crane y cosign: sale del mismo
  # job ci-images, así que no agrega una dependencia de arranque nueva.
  - name: node
    image: registry.registry-system.svc.cluster.local:5000/aegis-ci-node:22.23.1-alpine
    command: ['sleep', 'infinity']
    # Chicos a propósito, y el número no es al voto: la ResourceQuota de
    # jenkins-system tiene que bancar jenkins-0 + DOS builds solapados
    # (reintentos y multibranch hacen que solaparse sea el caso normal,
    # no el raro). Cada limit que se agregue acá se cuenta DOS VECES.
    # Con 500m este pod pasaba el techo y verify-static lo cazó en el
    # acto — check 36, la cascada de la corrida #11.
    resources:
      requests: { cpu: 100m, memory: 128Mi }
      limits:   { cpu: 250m, memory: 256Mi }
  # kaniko: build SIN privilegios (W-05). No /dev/fuse, no vfs, no
  # privileged — extrae capas al FS directo (anda donde buildah rootless
  # no, Ubuntu 24.04). root en el container pero NO privileged = no
  # escapa al nodo. Auth: regcred en /kaniko/.docker/config.json; CA
  # propio por --registry-certificate. -debug trae shell.
  - name: kaniko
    image: gcr.io/kaniko-project/executor:v1.23.2-debug
    command: ['sleep', 'infinity']
    volumeMounts:
    - name: regcred
      mountPath: /kaniko/.docker/config.json
      subPath: .dockerconfigjson
      readOnly: true
    - name: ca-trust
      mountPath: /kaniko/ca.crt
      subPath: ca.crt
      readOnly: true
    resources:
      requests: { cpu: 500m, memory: 512Mi }
      limits:   { cpu: 1500m, memory: 2Gi }
  # crane: pushea el tar YA escaneado (scan-antes-de-push). Imagen custom
  # aegis-ci-crane (crane distroless sobre alpine con shell; tag = FROM de
  # ci-images/crane/Containerfile). Auth por DOCKER_CONFIG; CA por
  # SSL_CERT_FILE (go-containerregistry lo honra).
  - name: crane
    image: registry.registry-system.svc.cluster.local:5000/aegis-ci-crane:v0.20.3
    command: ['sleep', 'infinity']
    env:
    - name: DOCKER_CONFIG
      value: /crane/docker
    - name: SSL_CERT_FILE
      value: /crane/ca/ca.crt
    volumeMounts:
    - name: regcred
      mountPath: /crane/docker/config.json
      subPath: .dockerconfigjson
      readOnly: true
    - name: ca-trust
      mountPath: /crane/ca/ca.crt
      subPath: ca.crt
      readOnly: true
    resources:
      requests: { cpu: 250m, memory: 256Mi }
      limits:   { cpu: 1000m, memory: 512Mi }
  # trivy: cliente THIN — el server (trivy-system) tiene la DB.
  - name: trivy
    image: ghcr.io/aquasecurity/trivy:0.72.0
    command: ['sleep', 'infinity']
    resources:
      requests: { cpu: 250m, memory: 256Mi }
      limits:   { cpu: 1000m, memory: 512Mi }
  # cosign: imagen custom aegis-ci-cosign (binario oficial sobre
  # alpine con shell — la oficial es distroless y container(){sh}
  # necesita shell). Password via secretKeyRef, NUNCA argv.
  # optional:true en key/password: durante el bootstrap (fases
  # 50-70) el secret cosign-signing-key AÚN no existe y el pod debe
  # poder arrancar; el stage sign salta con WARN si falta la key.
  # NO es un hueco permanente: kyverno-policies (fase 80) rechaza
  # imágenes sin firma en cuanto entra el Enforce.
  # ACOPLE DECLARADO: el tag DEBE coincidir con el FROM de
  # ops-stack/ci-images/cosign/Containerfile (fuente del pin). Es
  # inter-repo y no derivable en runtime; si divergen, el síntoma
  # es ImagePullBackOff (visible, no silencioso).
  - name: cosign
    image: registry.registry-system.svc.cluster.local:5000/aegis-ci-cosign:v2.6.3
    command: ['sleep', 'infinity']
    env:
    - name: COSIGN_PASSWORD
      valueFrom:
        secretKeyRef:
          name: cosign-signing-key
          key: cosign.password
          optional: true
    - name: DOCKER_CONFIG
      value: /cosign/docker
    volumeMounts:
    - name: cosign-key
      mountPath: /cosign/keys/cosign.key
      subPath: cosign.key
      readOnly: true
    - name: regcred
      mountPath: /cosign/docker/config.json
      subPath: .dockerconfigjson
      readOnly: true
    - name: ca-trust
      mountPath: /cosign/ca/ca.crt
      subPath: ca.crt
      readOnly: true
    resources:
      requests: { cpu: 100m, memory: 128Mi }
      limits:   { cpu: 500m, memory: 256Mi }
  volumes:
  - name: regcred
    secret:
      secretName: regcred-internal
      items: [{ key: .dockerconfigjson, path: .dockerconfigjson }]
  - name: ca-trust
    secret:
      secretName: aegis-ca-trust
      items: [{ key: ca.crt, path: ca.crt }]
  - name: cosign-key
    secret:
      secretName: cosign-signing-key
      optional: true
      items: [{ key: cosign.key, path: cosign.key }]
'''
      defaultContainer 'jnlp'
    }
  }
  environment {
    REGISTRY = 'registry.registry-system.svc.cluster.local:5000'
    IMAGE    = 'CHANGEME-app'   // nombre de la imagen en el registry
  }
  stages {
    stage('compute-tag') {
      // slug del branch + BUILD_NUMBER con zero-pad a 6: el orden
      // lexicográfico == orden numérico.
      //
      // El zero-pad nació para que el Image Updater ordenara bien los
      // tags, y el Image Updater se retiró en #36/#37 —ahora el digest
      // lo escribe este pipeline—. Se queda igual porque sigue sirviendo
      // para leer `docker images` y los logs sin hacer cuentas: build 9
      // antes que build 10.
      steps {
        script {
          def slug = env.BRANCH_NAME.replaceAll(/[^a-zA-Z0-9]/, '-').toLowerCase()
          env.TAG = "${slug}-${env.BUILD_NUMBER.padLeft(6, '0')}"
          echo "TAG=${env.TAG}"
        }
      }
    }
    stage('checkout') {
      steps { checkout scm }
    }
    stage('detect-change') {
      // ANTI-LOOP. La etapa `desplegar` de más abajo commitea el
      // digest a k8s/overlays/, y ese commit dispara este mismo job:
      // si buildeara, saldría una imagen nueva → otro write-back →
      // bucle infinito.
      //
      // (Antes el write-back lo hacía el Image Updater. Se retiró en
      // #36/#37 y ahora lo hace el pipeline, pero el bucle que hay que
      // cortar es exactamente el mismo.)
      //
      // UNA señal estructural (los paths del commit), NUNCA [skip ci]
      // del mensaje: dos señales que pueden discordar dan falsos skips,
      // y pasó de verdad en el build #7 del canary.
      //
      // Default seguro = BUILDEAR: si diff-tree viene vacío (merge,
      // primer build, disparo manual), se buildea.
      steps {
        script {
          def changed = sh(
            script: 'git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || true',
            returnStdout: true
          ).trim()
          def files = changed ? (changed.split('\n') as List) : []
          def onlyManifests = files && files.every { it.startsWith('k8s/') }
          env.SKIP_BUILD = onlyManifests ? 'true' : 'false'
          echo "detect-change: onlyManifests=${onlyManifests} -> SKIP_BUILD=${env.SKIP_BUILD}"
        }
      }
    }
    stage('build') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        container('kaniko') {
          // W-05: kaniko buildea a un TAR (--no-push) para escanear ANTES
          // de pushear. --destination da el ref del tar; CA propio por
          // --registry-certificate.
          sh '''
            /kaniko/executor \
              --context=dir://${WORKSPACE} \
              --dockerfile=Containerfile \
              --destination=${REGISTRY}/${IMAGE}:${TAG} \
              --no-push \
              --tarPath=${WORKSPACE}/image.tar \
              --registry-certificate ${REGISTRY}=/kaniko/ca.crt
          '''
        }
      }
    }
    stage('scan') {
      // Trivy server-mode: exportar a DOCKER-ARCHIVE (oci-archive
      // tar NO sirve para --input — verificado contra el binario).
      // Bloquea el build con CRITICAL/HIGH accionables (el pin del
      // toolchain envejece; el scan es el vigía).
      //
      // TOLERANCIA DE BOOTSTRAP: si el trivy-server no responde
      // (fases 50-70 del init, antes de la 80), el scan se SALTA con
      // WARN en vez de romper el build. La distinción importa:
      // infra-ausente ≠ vulnerabilidad-encontrada (la segunda SIEMPRE
      // rompe). El hueco lo cierra la fase 80 (server vivo + Enforce).
      when { expression { env.SKIP_BUILD != 'true' } }
      environment {
        TRIVY_SERVER = 'http://trivy.trivy-system.svc.cluster.local:4954'
      }
      steps {
        container('trivy') {
          script {
            def up = sh(returnStatus: true, script:
              'wget -q -T 5 -O /dev/null ${TRIVY_SERVER}/healthz') == 0
            if (!up) {
              echo 'WARN: trivy-server no disponible (bootstrap pre-fase-80) — scan SALTADO'
              env.SCAN_SKIPPED = 'true'
            } else {
              sh '''
                trivy image \
                  --server ${TRIVY_SERVER} \
                  --input ${WORKSPACE}/image.tar \
                  --exit-code 1 \
                  --severity CRITICAL,HIGH \
                  --ignore-unfixed \
                  --scanners vuln \
                  --no-progress
              '''
            }
          }
        }
      }
    }
    stage('push') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        container('crane') {
          // W-05: crane pushea el TAR YA escaneado (scan-antes-de-push
          // preservado); el digest sale de crane digest, para la firma.
          sh '''
            crane push ${WORKSPACE}/image.tar ${REGISTRY}/${IMAGE}:${TAG}
            crane digest ${REGISTRY}/${IMAGE}:${TAG} > ${WORKSPACE}/image-digest
            echo "pushed digest: $(cat ${WORKSPACE}/image-digest)"
          '''
        }
      }
    }
    stage('sign') {
      // Firma por DIGEST (inmutable), al MISMO registry.
      // --tlog-upload=false: nada del registry interno al Rekor
      // público. cosign v2.6.3 (NO v3: rompe vs distribution 3.1.1).
      // TOLERANCIA DE BOOTSTRAP: sin cosign-signing-key (fases
      // 50-70) el stage salta con WARN; ver nota del container.
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        container('cosign') {
          script {
            def hasKey = sh(returnStatus: true,
              script: 'test -f /cosign/keys/cosign.key') == 0
            if (!hasKey) {
              echo 'WARN: cosign-signing-key ausente (bootstrap pre-fase-80) — sign SALTADO'
              env.SIGN_SKIPPED = 'true'
            } else {
              sh '''
                DIGEST=$(cat ${WORKSPACE}/image-digest)
                cosign sign --yes \
                  --key /cosign/keys/cosign.key \
                  --tlog-upload=false \
                  --registry-cacert /cosign/ca/ca.crt \
                  ${REGISTRY}/${IMAGE}@${DIGEST}
              '''
            }
          }
        }
      }
    }
    stage('desplegar') {
      // ESCRIBIR EL DIGEST EN GIT — la etapa que a esta plantilla le
      // FALTABA, y su ausencia era invisible (#56).
      //
      // Sin ella el pipeline construye, escanea, publica y firma la
      // imagen... y no despliega nada. Termina en verde, porque hace
      // todo lo que dice hacer: lo que falta no está roto, está AUSENTE,
      // y ningún chequeo mira lo que no existe. El canario la copió tal
      // cual y estuvo así hasta el 2026-08-06.
      //
      // POR QUÉ EL DIGEST Y NO EL TAG: Kyverno reescribe la imagen
      // agregándole el digest verificado al admitir el pod. Con un TAG
      // en git, lo desplegado y lo deseado difieren SIEMPRE, y para que
      // ArgoCD no quede OutOfSync eterno había que ignorar el campo
      // `image` — lo que APAGABA el auto-sync: si la única diferencia es
      // la imagen y la imagen está ignorada, ArgoCD no ve nada que hacer
      // y nada se despliega. Medido el 2026-08-03 (#36): 4 syncs en 8
      // días, ninguno por una imagen nueva.
      //
      // Con el digest en git la mutación de Kyverno es un no-op
      // —verificado por admisión, entrada idéntica a salida—, no hay
      // deriva, y el auto-sync vuelve.
      //
      // Lo escribe ESTE pipeline porque es quien construyó la imagen y
      // ya sabe el digest. El commit toca solo k8s/, así que el
      // anti-loop del detect-change saltea el build que dispare.
      //
      // REQUISITOS en el repo de la app (los dos van en esta carpeta de
      // plantillas, al lado de este archivo):
      //   ci/write-digest.mjs
      //   k8s/overlays/dev/kustomization.yaml  con la sección `images:`
      // y una credencial `github-token` en Jenkins con permiso de
      // escritura sobre este repo.
      //
      // SOLO EN LA RAMA POR DEFECTO, y esto no es una preferencia de
      // estilo. Un job multibranch construye TODAS las ramas, así que
      // sin este guarda una rama de trabajo escribiría el digest de SU
      // imagen y lo empujaría a la rama desplegada: el trabajo a medio
      // hacer de alguien saldría a producción sin que nadie lo pidiera.
      // La rama de trabajo igual construye, escanea y firma —o sea que
      // sigue comprobando que el código está bien—, simplemente no
      // despliega.
      when {
        allOf {
          branch 'main'
          expression { env.SKIP_BUILD != 'true' }
        }
      }
      steps {
        container('node') {
          withCredentials([usernamePassword(
            credentialsId: 'github-token',
            usernameVariable: 'GH_USER',
            passwordVariable: 'GH_TOKEN')]) {
            // Comillas SIMPLES: $GH_TOKEN lo expande el shell, no Groovy.
            // Con dobles el token quedaría incrustado en la config del
            // job, que es un lugar donde queda escrito y se lee.
            sh '''
              set -e
              cd ${WORKSPACE}
              DIGEST="$(cat image-digest)"

              node ci/write-digest.mjs "${REGISTRY}/${IMAGE}=${DIGEST}"

              if git diff --quiet k8s/overlays/dev/kustomization.yaml; then
                echo "el digest ya estaba escrito — nada que commitear"
                exit 0
              fi

              # La config va al workspace y no a $HOME: el HOME del
              # container puede no ser escribible, y así el cambio muere
              # con el pod en vez de filtrarse a otro build.
              export GIT_CONFIG_GLOBAL="${WORKSPACE}/.gitconfig-ci"

              # safe.directory ANTES QUE NADA (#55). El workspace lo crea
              # el container jnlp con un UID y esta etapa corre en otro,
              # así que git lo ve como "dubious ownership" y SE NIEGA A
              # OPERAR — no falla al final, falla en el primer comando.
              #
              # Y va acá y no en la imagen: la línea de arriba REEMPLAZA
              # el config global por un archivo nuevo del workspace, así
              # que cualquier safe.directory que trajera el container
              # queda fuera de alcance.
              #
              # MEDIDO el 2026-08-04 en blog-aegis, build 4:
              #   fatal: detected dubious ownership in repository at
              #   '/home/jenkins/agent/workspace/blog-mb_main'
              # exit 128 DESPUÉS de construir, escanear, pushear y firmar.
              # Todo el trabajo hecho y el digest sin escribir, con la app
              # sirviendo la versión anterior en Synced + Healthy.
              git config --global --add safe.directory "${WORKSPACE}"

              git config --global user.email "ci@aegis"
              git config --global user.name "aegis CI"
              git config --global url."https://github.com/".insteadOf "git@github.com:"
              # El token NUNCA toca argv ni disco: se guarda el NOMBRE de
              # la variable y git la expande al invocar el helper.
              git config --global credential.helper \
                '!f() { echo username=x-access-token; echo password=$GH_TOKEN; }; f'

              git checkout -B ${BRANCH_NAME}
              git add k8s/overlays/dev/kustomization.yaml
              git commit -m "deploy: ${TAG} por digest (build ${BUILD_NUMBER})"

              # Reintento: otro build pudo empujar en el medio.
              for i in 1 2 3; do
                if git pull --rebase origin ${BRANCH_NAME} && git push origin ${BRANCH_NAME}; then
                  exit 0
                fi
                sleep 5
              done
              echo "no se pudo empujar el digest tras 3 intentos" >&2
              exit 1
            '''
          }
        }
      }
    }
    stage('report') {
      // HOOK de observabilidad (observability/design.md §2): UN
      // JSON-line con el evento supply-chain completo. Clave
      // natural: digest. Nunca valores de Secrets (la garantía nace
      // acá, y quien lo consuma la hereda).
      //
      // POR QUÉ POSTEA Y NO ALCANZA CON IMPRIMIRLO
      // ──────────────────────────────────────────
      // El diseño original decía que Vector levantaría esta línea
      // del stdout del pod de build, con CERO cambios acá. Esa
      // premisa es FALSA en un agente Kubernetes de Jenkins: la
      // salida de un paso `sh` no va al stdout del contenedor — el
      // plugin durable-task la escribe a un archivo y la transmite
      // por el canal de remoting hasta la consola del build. Vector
      // lee /var/log/pods, así que la línea nunca pasaba por su
      // vista. Medido el 2026-08-22: el stream jenkins-build tenía
      // CERO filas y los dos paneles de supply-chain llevaban vacíos
      // desde que nacieron, con builds reales corriendo.
      //
      // Así que el evento viaja por donde ya viaja gates.jsonl en la
      // fase 85: un POST directo. El printf se queda igual — sigue
      // siendo lo que un humano lee en la consola del build.
      steps {
        sh '''
          DIGEST=$(cat ${WORKSPACE}/image-digest 2>/dev/null || echo "")
          EVENTO=$(printf \
            '{"source":"jenkins-build","event":"supply-chain","image":"%s","tag":"%s","digest":"%s","skip_build":%s,"scan_skipped":%s,"sign_skipped":%s,"build":"%s","branch":"%s","ts":"%s"}' \
            "${IMAGE}" "${TAG}" "${DIGEST}" "${SKIP_BUILD}" \
            "${SCAN_SKIPPED:-false}" "${SIGN_SKIPPED:-false}" \
            "${BUILD_NUMBER}" "${BRANCH_NAME}" \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
          printf 'AEGIS_EVENT %s\n' "$EVENTO"
          # El Content-Type NO es decorativo: sin él curl declara
          # x-www-form-urlencoded y VictoriaLogs descarta el cuerpo
          # entero devolviendo HTTP 200 y cero filas — sin drop, sin
          # log, sin queja. Costó una tarde descubrirlo (fase 85).
          # Y el `||`: registrar no puede voltear un build, pero
          # tampoco puede callarse — un fallo mudo acá es justo la
          # enfermedad que este arreglo vino a curar.
          printf '%s\n' "$EVENTO" \
            | curl -fsS --max-time 15 \
                -H 'Content-Type: application/stream+json' --data-binary @- \
                'http://vlogs-events.observability.svc.cluster.local:9428/insert/jsonline?_time_field=ts&_msg_field=image&_stream_fields=source' \
            || echo 'AVISO: el evento no se pudo registrar en vlogs-events (el build NO falla por esto)'

          # ── y las MISMAS tres cosas como métrica ────────────────
          #
          # El evento de arriba se guarda un año y nadie lo mira: no
          # hay panel ni alerta que lo lea. Así que `scan_skipped:true`
          # viajaba, se archivaba, y el build terminaba en VERDE con
          # una imagen que nunca se escaneó corriendo en producción.
          # Encontrado el 2026-08-22 revisando por qué el barrido de
          # observabilidad no lo había cazado: no lo cazó porque no
          # existía el instrumento.
          #
          # La tolerancia de bootstrap (arriba, stages scan y sign) es
          # correcta y se queda: durante las fases 50-70 no hay
          # trivy-server ni clave de cosign, y romper el build ahí
          # sería impedir el arranque. Lo que no puede quedarse es que
          # esa tolerancia sea INVISIBLE una vez que la plataforma está
          # de pie. Un log que nadie lee no es una señal.
          #
          # Las dos caras no son simétricas, y por eso la alerta las
          # separa: sin firma, Kyverno RECHAZA la admisión y el
          # despliegue falla a gritos; sin escaneo no pasa nada — la
          # imagen entra, corre, y la única diferencia con una sana es
          # que a esta nadie la miró.
          #
          # Solo cuando hubo build de verdad: con SKIP_BUILD el
          # pipeline no produjo artefacto, y pushear 0 diría «el último
          # build escaneó bien», que es justo lo contrario de lo que
          # pasó. El valor anterior sigue siendo la verdad sobre la
          # imagen que está corriendo.
          if [ "${SKIP_BUILD}" != "true" ]; then
            {
              printf 'aegis_build_scan_skipped{image="%s"} %s\n' "${IMAGE}" \
                "$([ "${SCAN_SKIPPED:-false}" = true ] && echo 1 || echo 0)"
              printf 'aegis_build_sign_skipped{image="%s"} %s\n' "${IMAGE}" \
                "$([ "${SIGN_SKIPPED:-false}" = true ] && echo 1 || echo 0)"
              printf 'aegis_build_timestamp_seconds{image="%s"} %s\n' "${IMAGE}" \
                "$(date -u +%s)"
            } | curl -fsS --max-time 15 --data-binary @- \
                  'http://vmsingle.observability.svc.cluster.local:8428/api/v1/import/prometheus' \
              || echo 'AVISO: las métricas del build no llegaron a vmsingle (el build NO falla por esto)'
          fi
        '''
      }
    }
  }
}
