# teeth of check 272 — a node service is installed and tested in the pipeline.
C272="$AEGIS_ROOT/seed/templates/service-node/repos/app/Containerfile"
D272="$AEGIS_ROOT/seed/templates/service-node/repos/app/.dockerignore"
S272="$AEGIS_ROOT/seed/templates/service-node/repos/app/ci/compile.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the template as it was: the build stage back inside the image
red_1() { _sub "$C272" 'FROM __FROM_NODE__
' 'FROM __FROM_NODE_BUILD__ AS build
WORKDIR /app
COPY . .
RUN npm ci --no-audit --no-fund && npm test

FROM __FROM_NODE__
'; }

# the tests stop being the door
red_2() { _sub "$S272" 'npm test
' ''; }

# an empty dependency tree leaves no node_modules for the COPY
red_3() { _sub "$S272" 'mkdir -p node_modules
' ''; }

# the installed modules never reach the build context
red_4() { _sub "$D272" '!node_modules
' ''; }

# a red test is swallowed
red_5() { _sub "$S272" 'npm test
' 'npm test || true
'; }

# node_modules is left empty: the first build depends on how the builder carries an empty directory
red_6() { _sub "$S272" ': > node_modules/.aegis-compiled
' ''; }

# without errexit a red `npm test` falls through to prune and the echo
red_7() { _sub "$S272" 'set -eu
' 'set -u
'; }

# ── controls ──
control_1() { _sub "$S272" 'echo "compile: tests green;' 'echo "compile: the tests are green;'; }
