# ci/compile.sh — compiles this front OUTSIDE the image build.
#
# The pipeline runs it (Jenkinsfile.app, stage `compile`) with `sh`, in the
# aegis-ci-node container, in the same workspace kaniko builds from; the
# Containerfile then only COPYs dist/ onto the signed runtime.
#
# WHY NOT INSIDE THE IMAGE BUILD. On a user's instance (2026-09-28) an Astro
# site built this way failed four builds of four: Astro printed «Complete!»
# and kaniko died with «permission denied» closing the stage — the Vite /
# esbuild family leaves a service process kaniko cannot snapshot. And the
# build stage had to stand on node:*-alpine, whose bundled npm carried
# eleven CVEs past their window when the template was tried on the Arch lab VM
# (2026-09-30). Compiled here, neither exists.
#
# WHAT YOU CHANGE: the two lines below, for your framework.
#
#   framework      BUILD_CMD          OUT_DIR
#   Astro          npm run build      dist
#   Vite (React)   npm run build      dist
#   Vite (Vue)     npm run build      dist
#   Angular        npm run build      dist/<project>/browser
#
# Whatever OUT_DIR is, the result lands in dist/: that is the one path the
# Containerfile knows.
set -eu
BUILD_CMD="${BUILD_CMD:-npm run build}"
OUT_DIR="${OUT_DIR:-dist}"

# `npm ci` and NOT `npm install`: it installs EXACTLY what the lock says.
npm ci --no-audit --no-fund
sh -c "$BUILD_CMD"
if [ ! -d "$OUT_DIR" ]; then
    echo "compile: «$BUILD_CMD» did not leave $OUT_DIR/ — set OUT_DIR in ci/compile.sh to where your framework writes" >&2
    exit 1
fi
if [ "$OUT_DIR" != dist ]; then
    rm -rf dist
    mv "$OUT_DIR" dist
fi
echo "compile: dist/ holds $(find dist -type f | wc -l) file(s)"
