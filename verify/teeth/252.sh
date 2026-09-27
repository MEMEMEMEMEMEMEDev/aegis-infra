# teeth of check 252 — a member on the siblings its run just built.
JF252="$AEGIS_ROOT/seed/platform/base-images/Jenkinsfile"
S252="$AEGIS_ROOT/seed/platform/base-images/siblings.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the build stage as it was on 2026-09-23: php built on the seed's pin (finding 14)
red_1() { _sub "$JF252" "              sh 'sh base-images/siblings.sh pin \"\$M\"'
" ""; }

# the loop walks MEMBERS as asked again
red_2() { _sub "$JF252" "          MEMBERS_TO_BUILD = ordered
" "          MEMBERS_TO_BUILD = members
"; }

# the order ignores who stands on whom
red_3() { _sub "$S252" '                case " $left " in *" $s "*) ok=0 ;; esac' '                :'; }

# a failed sibling no longer stops the member
red_4() { _sub "$S252" '            *" $s "*) echo "ERROR: aegis-base-$m stands on aegis-base-$s, which FAILED in this run — nothing to build it on" >&2
                      exit 1 ;;' '            *" $s "*) ;;'; }

# the pin runs after kaniko has already built on the old one
red_5() { python3 - "$JF252" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
line = "              sh 'sh base-images/siblings.sh pin \"$M\"'\n"
assert s.count(line) == 1
s = s.replace(line, "", 1)
k = s.index("              container('crane') {\n                // THE CONTRACT")
p.write_text(s[:k] + line + s[k:])
PY
}

# the rewrite matches only a FROM without a tag: the pin stays where it was
red_6() { _sub "$S252" '(aegis-base-$s)(:[^@[:space:]]+)?@sha256' '(aegis-base-$s)@sha256'; }

# ── controls ──
# phase 80's list already in dependency order: nothing to reorder, still green
control_1() { _sub "$S252" '# POSIX sh: it runs in the agent' '# POSIX sh (checked by 252): it runs in the agent'; }
# the members stage says it differently in its log line
control_2() { _sub "$JF252" 'each after the ones it stands on:' 'siblings first:'; }
