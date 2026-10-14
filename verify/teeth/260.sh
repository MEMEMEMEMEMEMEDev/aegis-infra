# teeth of check 260 — a static front compiles in the pipeline, the image build only copies it.
C260="$AEGIS_ROOT/seed/templates/static/repos/app/Containerfile"
D260="$AEGIS_ROOT/seed/templates/static/repos/app/.dockerignore"
S260="$AEGIS_ROOT/seed/templates/static/repos/app/ci/compile.sh"
J260="$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the template as a user used it: the build stage back inside the image
red_1() { _sub "$C260" 'FROM __FROM_NODE__
' 'FROM __FROM_NODE_BUILD__ AS build
WORKDIR /app
COPY . .
RUN npm ci --no-audit --no-fund && npm run build

FROM __FROM_NODE__
'; }

# the pipeline loses its compile stage
red_2() { _sub "$J260" "    stage('compile') {" "    stage('compile-disabled-by-tooth') {"; }

# the compiled result never reaches the build context
red_3() { _sub "$D260" '!dist
' ''; }

# ci/compile.sh stops moving an OUT_DIR elsewhere into dist/
red_4() { _sub "$S260" '    mv "$OUT_DIR" dist' '    :'; }

# the compile stage runs for every repo, a Go service included
red_5() { _sub "$J260" "          expression { fileExists('ci/compile.sh') }" "          expression { true }"; }

# the lock stops being what is built (the script's own comment still says `npm ci`)
red_6() { _sub "$S260" 'npm ci --no-audit --no-fund
' 'npm install --no-audit --no-fund
'; }

# ── controls ──
control_1() { _sub "$S260" 'echo "compile: dist/ holds' 'echo "compile: dist/ now holds'; }
