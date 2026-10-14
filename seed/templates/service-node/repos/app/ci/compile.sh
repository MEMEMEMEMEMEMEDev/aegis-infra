# ci/compile.sh — installs, tests and prunes this service OUTSIDE the image
# build.
#
# The pipeline runs it (Jenkinsfile.app, stage `compile`) with `sh`, in the
# aegis-ci-node container, in the same workspace kaniko builds from; the
# Containerfile then only COPYs the result onto the signed runtime.
#
# WHY NOT INSIDE THE IMAGE BUILD (since 2026-10-02). The build stage stood
# on node:22.23.1-alpine, an image nobody else needs: it had to be mirrored
# before the template could even be instantiated, and on the Arch lab VM
# (2026-09-30) the door retained that very image — its bundled npm carried
# eleven CVEs past their window. The static template moved first
# (ci/compile.sh, the same stage); this one follows. Here, the npm that
# installs is the platform's own (aegis-ci-node, built and scanned by the
# platform), and nothing with a package manager reaches the image.
#
# WHAT IT DOES, in order — each step is load bearing:
#   1. `npm ci`: EXACTLY what the lock says. `npm install` may resolve a
#      different tree than the one that was tested.
#   2. `npm test`: the image's door. A red test stops the pipeline here and
#      the image never comes to exist.
#   3. `npm prune --omit=dev`: only production travels into the image.
#   4. `mkdir -p node_modules` and a marker file in it: with an EMPTY
#      dependency tree — how this template ships — `npm ci` creates no
#      node_modules at all (measured 2026-08-29: «up to date», no
#      directory), and the Containerfile's COPY of a path that does not
#      exist would abort the build with an error that never mentions npm.
#      The marker is there so that the directory is never EMPTY either:
#      whether a builder carries an empty directory out of a build context
#      filtered by an allowlist is the builder's business, and a first
#      build should not depend on it. node ignores the file.
#
# NATIVE ADDONS (bcrypt, sharp…) are compiled for the libc of the agent,
# which is Alpine's musl. They run on aegis-base-node (Alpine too), not on
# nodejs-distroless (glibc): the README says how to move the runtime.
set -eu
npm ci --no-audit --no-fund
npm test
npm prune --omit=dev
mkdir -p node_modules
: > node_modules/.aegis-compiled
echo "compile: tests green; node_modules holds $(find node_modules -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l) production package(s)"
