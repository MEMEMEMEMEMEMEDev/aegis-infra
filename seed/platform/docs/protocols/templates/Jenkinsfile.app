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
      requests: { cpu: 250m, memory: 512Mi }
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
      requests: { cpu: 50m, memory: 128Mi }
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
      requests: { cpu: 250m, memory: 512Mi }
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
      requests: { cpu: 100m, memory: 256Mi }
      limits:   { cpu: 1000m, memory: 512Mi }
  # trivy: THIN client — the server (trivy-system) holds the DB.
  - name: trivy
    image: ghcr.io/aquasecurity/trivy:0.72.0
    command: ['sleep', 'infinity']
    resources:
      requests: { cpu: 100m, memory: 256Mi }
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
      requests: { cpu: 50m, memory: 128Mi }
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
    // ONE origin for the file kaniko builds and the from-guard reads:
    // two literals would be two places to edit, and the guard would end
    // up measuring a file the build does not use.
    CONTAINERFILE = 'Containerfile'
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
    stage('from-guard') {
      // THE FROM IS PART OF THE SUPPLY CHAIN, and until today nobody
      // looked at it. Everything downstream of this line is measured —
      // kaniko builds without privileges, trivy blocks on actionable
      // CRITICAL/HIGH, cosign signs by digest, Kyverno refuses to admit
      // what is not signed — and all of it stands on a base image that
      // was written by hand, in another repo, pulled from the open
      // internet, under a tag somebody else can repoint. The scan looks
      // at the RESULT, which is why an unpinned base does not fail: it
      // succeeds, with different bytes than yesterday.
      //
      // Two failures, and they are not the same one:
      //   · a FROM that is not the internal registry: nothing about
      //     that image went through our scan or our key, so the pod is
      //     rejected at admission — after the build spent its minutes,
      //     in a namespace nobody was looking at, with a message about
      //     signatures that says nothing about a Containerfile;
      //   · a FROM by TAG, even ours: the tag is a mutable pointer and
      //     what Kyverno verifies is a digest. `registry/x:1.2` and
      //     `registry/x:1.2@sha256:…` build differently on two
      //     different days and neither build says so.
      // Both die HERE instead, before a single layer is extracted, with
      // the one command that fixes them.
      //
      // The guard reads the FROMs of this repo's own Containerfile and
      // asks the two questions of the two containers that can answer
      // them and are ALREADY in this pod: crane (does the internal
      // registry hold this digest) and cosign (does its signature
      // verify against our key). No new container, so the quota
      // arithmetic of check 036 does not move.
      //
      // WHAT IS NOT ASKED. A ref that names an earlier stage of this
      // same file is not a base image, it is this build's own output;
      // and a double-underscore placeholder belongs to a template that
      // has not been instantiated yet (the shape the seed uses, check
      // 003's vocabulary). Both are skipped, and said out loud.
      //
      // BOOTSTRAP TOLERANCE, the same one the scan and sign stages
      // carry and for the same reason: during init phases 50-70 the
      // cosign key does not exist yet, so the signature half CANNOT be
      // measured. It is not skipped quietly — "could not measure" is
      // printed, travels in the event, and the existence half still
      // runs. The day the key is there, both halves block.
      //
      // NO NEW METRIC, on purpose. This file already pushes
      // aegis_build_* series that an alert reads; a new series that no
      // rule and no panel reads is case (d) of the 2026-08-22
      // observability sweep — paid for and looked at by nobody, which
      // check 092 refuses. The signal a failed guard emits is the one
      // that cannot be missed: the build is dead. The event carries the
      // detail for the record.
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        container('crane') {
          sh '''
            set -e
            test -f "${CONTAINERFILE}" || {
              echo "from-guard: this repo has no ${CONTAINERFILE} — the build stage would not find one either"
              exit 1
            }
            rm -f from-refs from-bad from-msg from-unsigned from-count from-sign-state

            # The FROMs, with the aliases of this same file taken out.
            # `--platform=` and friends are flags, not references; the
            # first field that is not one is the image.
            awk '
              { sub(/#.*/, "") }
              toupper($1) == "FROM" {
                  ref = ""
                  for (i = 2; i <= NF; i++) { if (substr($i, 1, 2) != "--") { ref = $i; break } }
                  if (NF >= 3 && toupper($(NF-1)) == "AS") stage[tolower($NF)] = 1
                  if (ref != "" && !(tolower(ref) in stage)) print ref
              }
            ' "${CONTAINERFILE}" > from-refs

            N=0
            while read -r ref; do
              [ -n "$ref" ] || continue
              N=$((N+1))
              case "$ref" in
                __*__)
                  echo "from-guard: ${ref} is an uninstantiated template placeholder — not resolvable here"
                  continue
                  ;;
              esac
              WHY=""
              case "$ref" in
                "${REGISTRY}"/*@sha256:*)
                  D=${ref##*@sha256:}
                  [ ${#D} -eq 64 ] || WHY="the digest after @sha256: is not 64 hex characters"
                  ;;
                "${REGISTRY}"/*)
                  WHY="it names the internal registry but by TAG: a tag is a mutable pointer and what Kyverno verifies is a digest"
                  ;;
                *)
                  WHY="it does not come from the internal registry: nothing about that image went through our scan or our key, so a pod that uses it is rejected at admission"
                  ;;
              esac
              if [ -z "$WHY" ]; then
                crane manifest "$ref" > /dev/null 2>&1 || WHY="the internal registry does not serve that digest (it was never mirrored, or it was garbage-collected)"
              fi
              if [ -n "$WHY" ]; then
                printf '%s\n' "$ref" >> from-bad
                printf '%s\n' "FROM ${ref} is not mirrored/signed. Run: aegis image request ${ref}  and paste the FROM it prints" >> from-msg
                printf '%s\n' "    why: ${WHY}" >> from-msg
              fi
            done < from-refs
            printf '%s\n' "$N" > from-count
            echo "from-guard: ${N} base reference(s) read from ${CONTAINERFILE}"
          '''
        }
        container('cosign') {
          sh '''
            set -e
            if [ ! -f /cosign/keys/cosign.key ]; then
              echo "WARN: cosign-signing-key missing (bootstrap pre-phase-80) — the SIGNATURE half of from-guard COULD NOT BE MEASURED (the existence half did run)"
              printf '%s\n' "not-evaluable" > from-sign-state
              exit 0
            fi
            printf '%s\n' "measured" > from-sign-state
            # The public half is derived from the private key we already
            # mount: cosign.pub lives in the platform repo, and this pod
            # is standing in the app's. One less thing to mount, one
            # less place for the two to drift apart.
            cosign public-key --key /cosign/keys/cosign.key > from-cosign.pub
            while read -r ref; do
              [ -n "$ref" ] || continue
              case "$ref" in __*__) continue ;; esac
              if [ -f from-bad ] && grep -qxF "$ref" from-bad; then continue; fi
              # --insecure-ignore-tlog: the signature is fully verified
              # against our key; only the public transparency log is
              # skipped, and it was never used (--tlog-upload=false on a
              # private registry).
              cosign verify --key from-cosign.pub \
                  --registry-cacert /cosign/ca/ca.crt \
                  --insecure-ignore-tlog=true "$ref" > /dev/null 2>&1 \
                || printf '%s\n' "$ref" >> from-unsigned
            done < from-refs
            rm -f from-cosign.pub
          '''
        }
        sh '''
          N=$(cat from-count 2>/dev/null || echo 0)
          STATE=$(cat from-sign-state 2>/dev/null || echo not-evaluable)
          BAD=0
          UNSIGNED=0
          if [ -f from-bad ];      then BAD=$(wc -l < from-bad); fi
          if [ -f from-unsigned ]; then UNSIGNED=$(wc -l < from-unsigned); fi
          EVENTO=$(printf \
            '{"source":"jenkins-build","event":"from-guard","image":"%s","tag":"%s","bases":%s,"unmirrored":%s,"unsigned":%s,"signature_check":"%s","build":"%s","branch":"%s","ts":"%s"}' \
            "${IMAGE}" "${TAG}" "${N}" "${BAD}" "${UNSIGNED}" "${STATE}" \
            "${BUILD_NUMBER}" "${BRANCH_NAME}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
          printf 'AEGIS_EVENT %s\n' "$EVENTO"
          # Same road and the same Content-Type as the report stage: an
          # `sh` step writes to the remoting channel, not to the
          # container stdout, so Vector never sees it. Without the
          # header VictoriaLogs answers 200 and stores zero rows.
          printf '%s\n' "$EVENTO" \
            | curl -fsS --max-time 15 \
                -H 'Content-Type: application/stream+json' --data-binary @- \
                'http://vlogs-events.observability.svc.cluster.local:9428/insert/jsonline?_time_field=ts&_msg_field=image&_stream_fields=source' \
            || echo 'NOTICE: the from-guard event could not be recorded in vlogs-events (the guard does NOT change its verdict over this)'

          # BOOTSTRAP: the same marker the signature half already uses.
          # Measured on 2026-08-31, on the first run that reached this
          # stage: phase 60 builds the canary to prove webhook -> build
          # -> deploy END TO END, and it runs BEFORE phase 80, which is
          # what mirrors anything at all. So at that moment the canary's
          # base CANNOT be in the internal registry — there is no
          # registry content yet — and this guard was stopping a build
          # for not having what nothing had yet produced.
          #
          # The signature half already knew this and degraded to «could
          # not be measured». The existence half did not, and the
          # asymmetry is what broke the install: half the guard was
          # bootstrap-aware and half of it was not.
          #
          # It is NOT silenced. The build goes on and says, in the same
          # words the phase's log will carry, that its base was not
          # verified and why. And the moment phase 80 exists — the
          # cosign key is its marker — this guard is hard again,
          # forever, for every build that follows.
          if [ "$STATE" = "not-evaluable" ] && [ "$BAD" -gt 0 ]; then
            echo "============= from-guard: NOT MEASURED (bootstrap) ============="
            if [ -f from-msg ]; then cat from-msg; fi
            echo "This build runs BEFORE the supply chain exists (no cosign key yet:"
            echo "phase 80 has not run). Its base is NOT mirrored and NOT signed, and"
            echo "that is the expected shape of the canary that proves the webhook"
            echo "path at phase 60. From the first build after phase 80, this guard"
            echo "stops instead of warning."
            echo "==============================================================="
            BAD=0
          fi

          if [ "$BAD" -gt 0 ] || [ "$UNSIGNED" -gt 0 ]; then
            echo "=================== from-guard: STOP ==================="
            if [ -f from-msg ]; then cat from-msg; fi
            if [ -f from-unsigned ]; then
              while read -r r; do
                printf '%s\n' "FROM ${r} is not mirrored/signed. Run: aegis image request ${r}  and paste the FROM it prints"
                printf '%s\n' "    why: the registry serves that digest and its signature does NOT verify against the aegis key — Kyverno rejects it at admission"
              done < from-unsigned
            fi
            echo "========================================================"
            echo "Nothing was built: a base nobody scanned and nobody signed is not a base."
            exit 1
          fi
          if [ "$STATE" = "not-evaluable" ]; then
            echo "from-guard: ${N} base reference(s) present in the internal registry by digest; their signatures COULD NOT BE MEASURED (no key yet)"
          else
            echo "from-guard: ${N} base reference(s), every one from the internal registry, by digest, present and signed"
          fi
        '''
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
              --dockerfile=${CONTAINERFILE} \
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
