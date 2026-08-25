// Jenkinsfile.app — TEMPLATE v2 for apps that consume the aegis
// platform (copy it into the app's repo and adjust CHANGEME). It
// is the hello-aegis v1 canary pipeline distilled: build → scan →
// push → sign → report, with the Image Updater anti-loop and every
// A* lesson baked in. Change ONLY what is marked CHANGEME; the
// rest is a contract with the platform (pins, secrets, limits — if
// any of that does not suit you, the change goes in ops-stack, not
// here).
//
// Prerequisites in the jenkins-system tenant namespace (the init
// creates them / see the registry-credentials.md protocol):
//   - Secret regcred-internal (the registry's dockerconfigjson)
//   - Secret aegis-ca-trust (the internal CA's ca.crt)
//   - Secret cosign-signing-key (cosign.key + cosign.password)
pipeline {
  agent {
    kubernetes {
      // Strict RQ in jenkins-system: EVERY container declares its
      // limits (jnlp included — NEVER `yaml ''`, it overrides the
      // default).
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
  # node: ONLY for the `desplegar` stage, which writes the digest into
  # the overlay. It does not compile the app —kaniko does that from the
  # Containerfile—, so the limits are small on purpose. If your app needs
  # `npm ci` in the pipeline, raise them here.
  #
  # Image from the internal registry, same as crane and cosign: it comes
  # out of the same ci-images job, so it adds no new startup dependency.
  - name: node
    image: registry.registry-system.svc.cluster.local:5000/aegis-ci-node:22.23.1-alpine
    command: ['sleep', 'infinity']
    # Small on purpose, and the numbers are not a matter of taste: the
    # jenkins-system ResourceQuota has to hold jenkins-0 + TWO builds
    # overlapping (retries and multibranch make overlapping the normal
    # case, not the rare one). Every limit added here counts TWICE.
    # At 500m this pod went over the ceiling and verify-static caught
    # it on the spot — check 36, the run #11 cascade.
    resources:
      requests: { cpu: 100m, memory: 128Mi }
      limits:   { cpu: 250m, memory: 256Mi }
  # kaniko: UNPRIVILEGED build (W-05). No /dev/fuse, no vfs, no
  # privileged — it extracts layers straight onto the FS (it works where
  # rootless buildah does not, Ubuntu 24.04). root inside the container
  # but NOT privileged = no escape to the node. Auth: regcred at
  # /kaniko/.docker/config.json; our own CA via --registry-certificate.
  # -debug ships a shell.
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
  # crane: pushes the tar that was ALREADY scanned (scan-before-push).
  # Custom image aegis-ci-crane (distroless crane on alpine with a shell;
  # tag = the FROM of ci-images/crane/Containerfile). Auth via
  # DOCKER_CONFIG; CA via SSL_CERT_FILE (go-containerregistry honours it).
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
  # trivy: THIN client — the server (trivy-system) holds the DB.
  - name: trivy
    image: ghcr.io/aquasecurity/trivy:0.72.0
    command: ['sleep', 'infinity']
    resources:
      requests: { cpu: 250m, memory: 256Mi }
      limits:   { cpu: 1000m, memory: 512Mi }
  # cosign: custom image aegis-ci-cosign (the official binary on
  # alpine with a shell — the official one is distroless and
  # container(){sh} needs a shell). Password via secretKeyRef,
  # NEVER argv. optional:true on key/password: during the bootstrap
  # (phases 50-70) the cosign-signing-key secret does NOT exist yet
  # and the pod still has to start; the sign stage skips with WARN
  # if the key is missing. It is NOT a permanent hole:
  # kyverno-policies (phase 80) rejects unsigned images the moment
  # Enforce goes in.
  # DECLARED COUPLING: the tag MUST match the FROM of
  # ops-stack/ci-images/cosign/Containerfile (source of the pin).
  # It is inter-repo and not derivable at runtime; if they diverge,
  # the symptom is ImagePullBackOff (visible, not silent).
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
    IMAGE    = 'CHANGEME-app'   // the image's name in the registry
  }
  stages {
    stage('compute-tag') {
      // branch slug + BUILD_NUMBER zero-padded to 6: lexicographic
      // order == numeric order.
      //
      // The zero-pad was born so the Image Updater would sort the tags
      // properly, and the Image Updater was retired in #36/#37 —this
      // pipeline writes the digest now—. It stays as it is because it
      // still helps to read `docker images` and the logs without doing
      // sums: build 9 before build 10.
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
      // ANTI-LOOP. The `desplegar` stage further down commits the
      // digest to k8s/overlays/, and that commit fires this very job:
      // if it built, a new image would come out → another write-back →
      // an infinite loop.
      //
      // (The write-back used to be the Image Updater's. It was retired
      // in #36/#37 and the pipeline does it now, but the loop that has
      // to be cut is exactly the same one.)
      //
      // ONE structural signal (the commit's paths), NEVER [skip ci] in
      // the message: two signals that can disagree produce false skips,
      // and that really happened in the canary's build #7.
      //
      // Safe default = BUILD: if diff-tree comes back empty (a merge,
      // the first build, a manual trigger), it builds.
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
          // W-05: kaniko builds into a TAR (--no-push) so the scan runs
          // BEFORE the push. --destination gives the tar its ref; our own
          // CA via --registry-certificate.
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
      // Trivy server-mode: export to DOCKER-ARCHIVE (an oci-archive
      // tar does NOT work with --input — verified against the binary).
      // It blocks the build on actionable CRITICAL/HIGH (the toolchain
      // pin ages; the scan is the lookout).
      //
      // BOOTSTRAP TOLERANCE: if trivy-server does not answer (init
      // phases 50-70, before phase 80), the scan is SKIPPED with a
      // WARN instead of breaking the build. The distinction matters:
      // infra-absent ≠ vulnerability-found (the second one ALWAYS
      // breaks). Phase 80 closes the gap (live server + Enforce).
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
              echo 'WARN: trivy-server unavailable (bootstrap pre-phase-80) — scan SKIPPED'
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
          // W-05: crane pushes the ALREADY scanned TAR (scan-before-push
          // preserved); the digest comes from crane digest, for the sign.
          sh '''
            crane push ${WORKSPACE}/image.tar ${REGISTRY}/${IMAGE}:${TAG}
            crane digest ${REGISTRY}/${IMAGE}:${TAG} > ${WORKSPACE}/image-digest
            echo "pushed digest: $(cat ${WORKSPACE}/image-digest)"
          '''
        }
      }
    }
    stage('sign') {
      // Signed by DIGEST (immutable), to the SAME registry.
      // --tlog-upload=false: nothing from the internal registry goes
      // to the public Rekor. cosign v2.6.3 (NOT v3: it breaks against
      // distribution 3.1.1). BOOTSTRAP TOLERANCE: with no
      // cosign-signing-key (phases 50-70) the stage skips with a
      // WARN; see the container's note.
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        container('cosign') {
          script {
            def hasKey = sh(returnStatus: true,
              script: 'test -f /cosign/keys/cosign.key') == 0
            if (!hasKey) {
              echo 'WARN: cosign-signing-key missing (bootstrap pre-phase-80) — sign SKIPPED'
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
      // WRITE THE DIGEST INTO GIT — the stage this template was
      // MISSING, and whose absence was invisible (#56).
      //
      // Without it the pipeline builds, scans, publishes and signs the
      // image... and deploys nothing. It ends green, because it does
      // everything it says it does: what is missing is not broken, it is
      // ABSENT, and no check looks at what does not exist. The canary
      // copied it as it was and stayed that way until 2026-08-06.
      //
      // WHY THE DIGEST AND NOT THE TAG: Kyverno rewrites the image,
      // adding the verified digest to it when it admits the pod. With a
      // TAG in git, what is deployed and what is desired differ ALWAYS,
      // and to keep ArgoCD from sitting OutOfSync forever the `image`
      // field had to be ignored — which TURNED OFF the auto-sync: if the
      // only difference is the image and the image is ignored, ArgoCD
      // sees nothing to do and nothing gets deployed. Measured on
      // 2026-08-03 (#36): 4 syncs in 8 days, none for a new image.
      //
      // With the digest in git Kyverno's mutation is a no-op —verified
      // at admission, input identical to output—, there is no drift,
      // and the auto-sync comes back.
      //
      // THIS pipeline writes it because it is the one that built the
      // image and already knows the digest. The commit touches only
      // k8s/, so detect-change's anti-loop skips the build it fires.
      //
      // REQUIREMENTS in the app's repo (both of them live in this
      // templates folder, next to this file):
      //   ci/write-digest.mjs
      //   k8s/overlays/dev/kustomization.yaml  with its `images:` section
      // plus a `github-token` credential in Jenkins with write
      // permission on this repo.
      //
      // ONLY ON THE DEFAULT BRANCH, and this is not a matter of style.
      // A multibranch job builds ALL the branches, so without this guard
      // a working branch would write ITS image's digest and push it to
      // the deployed branch: somebody's half-finished work would go out
      // to production without anyone asking for it. The working branch
      // still builds, scans and signs —so it keeps proving the code is
      // sound—, it simply does not deploy.
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
            // SINGLE quotes: the shell expands $GH_TOKEN, not Groovy.
            // With double ones the token would end up embedded in the
            // job's config, which is a place where it stays written
            // down and gets read.
            sh '''
              set -e
              cd ${WORKSPACE}
              DIGEST="$(cat image-digest)"

              node ci/write-digest.mjs "${REGISTRY}/${IMAGE}=${DIGEST}"

              if git diff --quiet k8s/overlays/dev/kustomization.yaml; then
                echo "the digest was already written — nothing to commit"
                exit 0
              fi

              # The config goes to the workspace and not to $HOME: the
              # container's HOME may not be writable, and this way the
              # change dies with the pod instead of leaking into another
              # build.
              export GIT_CONFIG_GLOBAL="${WORKSPACE}/.gitconfig-ci"

              # safe.directory BEFORE ANYTHING ELSE (#55). The jnlp
              # container creates the workspace under one UID and this
              # stage runs under another, so git sees it as "dubious
              # ownership" and REFUSES TO OPERATE — it does not fail at
              # the end, it fails on the first command.
              #
              # And it goes here and not in the image: the line above
              # REPLACES the global config with a new file in the
              # workspace, so any safe.directory the container brought
              # along is out of reach.
              #
              # MEASURED on 2026-08-04 in blog-aegis, build 4:
              #   fatal: detected dubious ownership in repository at
              #   '/home/jenkins/agent/workspace/blog-mb_main'
              # exit 128 AFTER building, scanning, pushing and signing.
              # All the work done and the digest unwritten, with the app
              # serving the previous version in Synced + Healthy.
              git config --global --add safe.directory "${WORKSPACE}"

              git config --global user.email "ci@aegis"
              git config --global user.name "aegis CI"
              git config --global url."https://github.com/".insteadOf "git@github.com:"
              # The token NEVER touches argv or disk: what is stored is
              # the variable's NAME, and git expands it when it invokes
              # the helper.
              git config --global credential.helper \
                '!f() { echo username=x-access-token; echo password=$GH_TOKEN; }; f'

              git checkout -B ${BRANCH_NAME}
              git add k8s/overlays/dev/kustomization.yaml
              git commit -m "deploy: ${TAG} by digest (build ${BUILD_NUMBER})"

              # Retry: another build may have pushed in the meantime.
              for i in 1 2 3; do
                if git pull --rebase origin ${BRANCH_NAME} && git push origin ${BRANCH_NAME}; then
                  exit 0
                fi
                sleep 5
              done
              echo "could not push the digest after 3 attempts" >&2
              exit 1
            '''
          }
        }
      }
    }
    stage('report') {
      // Observability HOOK (observability/design.md §2): ONE
      // JSON-line with the whole supply-chain event. Natural key:
      // digest. Never Secret values (the guarantee is born here,
      // and whoever consumes it inherits it).
      //
      // WHY IT POSTS, AND WHY PRINTING IT IS NOT ENOUGH
      // ───────────────────────────────────────────────
      // The original design said Vector would pick this line up
      // from the build pod's stdout, with ZERO changes here. That
      // premise is FALSE on a Jenkins Kubernetes agent: the output
      // of an `sh` step does not go to the container's stdout — the
      // durable-task plugin writes it to a file and streams it over
      // the remoting channel to the build's console. Vector reads
      // /var/log/pods, so the line never passed in front of it.
      // Measured on 2026-08-22: the jenkins-build stream had ZERO
      // rows and the two supply-chain panels had been empty since
      // the day they were born, with real builds running.
      //
      // So the event travels the same road gates.jsonl already
      // travels in phase 85: a direct POST. The printf stays as it
      // is — it is still what a human reads in the build's console.
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
          # The Content-Type is NOT decorative: without it curl
          # declares x-www-form-urlencoded and VictoriaLogs discards
          # the whole body, returning HTTP 200 and zero rows — no
          # drop, no log, no complaint. It cost an afternoon to find
          # out (phase 85). And the `||`: logging cannot topple a
          # build, but it cannot keep quiet either — a mute failure
          # here is exactly the disease this fix came to cure.
          printf '%s\n' "$EVENTO" \
            | curl -fsS --max-time 15 \
                -H 'Content-Type: application/stream+json' --data-binary @- \
                'http://vlogs-events.observability.svc.cluster.local:9428/insert/jsonline?_time_field=ts&_msg_field=image&_stream_fields=source' \
            || echo 'NOTICE: the event could not be recorded in vlogs-events (the build does NOT fail for this)'

          # ── and the SAME three things as a metric ───────────────
          #
          # The event above is kept for a year and nobody looks at it:
          # there is no panel and no alert that reads it. So
          # `scan_skipped:true` travelled, got filed away, and the
          # build ended GREEN with an image that was never scanned
          # running in production. Found on 2026-08-22 while going
          # over why the observability sweep had not caught it: it did
          # not catch it because the instrument did not exist.
          #
          # The bootstrap tolerance (above, the scan and sign stages)
          # is correct and it stays: during phases 50-70 there is no
          # trivy-server and no cosign key, and breaking the build
          # there would mean blocking the startup. What cannot stay is
          # that tolerance being INVISIBLE once the platform is on its
          # feet. A log nobody reads is not a signal.
          #
          # The two sides are not symmetric, and that is why the alert
          # keeps them apart: with no signature Kyverno REJECTS the
          # admission and the deploy fails loudly; with no scan
          # nothing happens — the image goes in, runs, and the only
          # difference from a healthy one is that nobody looked at
          # this one.
          #
          # Only when there really was a build: with SKIP_BUILD the
          # pipeline produced no artifact, and pushing 0 would say
          # «the last build scanned clean», which is exactly the
          # opposite of what happened. The previous value is still the
          # truth about the image that is running.
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
              || echo 'NOTICE: the build metrics did not reach vmsingle (the build does NOT fail for this)'
          fi
        '''
      }
    }
  }
}
