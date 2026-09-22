# teeth of check 229 — the owner's deploy-key policy, asked in time.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}

# phase 00 as it was: nobody asks, and phase 15 pays for it
red_1() { _sub "$AEGIS_ROOT/init/phases/00-preflight.sh" 'gate "github-owner-permite-deploy-keys" check_gh_org_allows_deploy_keys "$GH_OWNER"' ':'; }

# an organization that forbids them LET THROUGH: the refusal logged and
# then swallowed, which is how the first cloud instance reached phase 15
red_2() { _sub "$AEGIS_ROOT/lib/checks.sh" "            return 1 ;;
        *)" "            return 0 ;;
        *)"; }

# the refusal without the page that fixes it: a wall with no door
red_3() { _sub "$AEGIS_ROOT/lib/checks.sh" 'log_error "  Enable them: https://github.com/organizations/$owner/settings/repository-policies -> Deploy keys"' 'log_error "  Enable deploy keys for that organization"'; }

# «could not be read» turned into a refusal: not knowing is not knowing
red_4() { _sub "$AEGIS_ROOT/lib/checks.sh" '            log_warn "whether $owner allows deploy keys could not be read (does the gh session have read:org?): NOT measured"
            return 0 ;;' '            log_error "whether $owner allows deploy keys could not be read"
            return 1 ;;'; }

# control: a personal account is still left alone, said in other words
control_1() { _sub "$AEGIS_ROOT/lib/checks.sh" '    [[ "$kind" == "Organization" ]] || return 0' '    [[ "$kind" == "Organization" ]] || return 0   # a user has no such policy'; }
