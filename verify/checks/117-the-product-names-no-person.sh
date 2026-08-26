# title: the product names no person
# origin: new in v3 — 2026-08-26, the day the artifact was measured as what ships
check() {
# Sibling of check 116. That one keeps out the address of a MACHINE;
# this one keeps out the identity of a PERSON — the two ways an artifact
# quietly stops being something anyone can install and becomes something
# written for whoever wrote it.
#
# What it found the day it was written, and none of it was suspected:
#
#   · `seed/platform/vps/clouding-lab.cloud-init.yaml.tpl` created the
#     VM's admin user with the NAME OF THE OPERATOR who first wrote the
#     template. Anybody installing aegis got a machine carrying a
#     stranger's username — and it was not a comment, it was the account
#     that boots;
#   · a harness defaulted to an absolute path under one person's home
#     directory — a path that exists on exactly one computer on earth;
#   · three files quoted the operator's GitHub account by name;
#   · a protocol told the reader to export a backup path under that same
#     person's home.
#
# HOW IT ASKS. Two questions, and the second is the interesting one.
#
# (1) Universal: no absolute path under a home directory. The two
#     spellings — the Linux one and the macOS one — name one machine's
#     one account. `$HOME` and `~` are the portable way of saying the
#     same thing, and they are what belongs here. (This paragraph does
#     not write either spelling out, because this check reads itself.)
#
# (2) Contextual: the product must not contain the name of whoever is
#     RUNNING it — their login, and the GitHub account their `gh` session
#     is authenticated as. This one is deliberately relative: on this
#     machine it catches this operator, and on somebody else's it catches
#     theirs, which is exactly the guarantee wanted. It is the same trick
#     check 086 uses to contrast the seed against the live instance.
#     Where the name cannot be read, the sub-check says so instead of
#     passing: not being able to look is not the same as being clean.
#
# The RECORD (plan/, ENCARGO.md, EJECUTADO.md, Problema-*) is out of
# scope here, unlike in 116, and the difference is deliberate: an address
# is an address wherever it is written, but the record's whole job is to
# say who decided what and on which machine. It is also the part of the
# tree that does not ship.
D117="" ; N117=0

PRODUCT_DIRS=(bin lib libexec init verify share docs)
[[ -d "$SEED" ]] && PRODUCT_DIRS+=(seed)

# ── (1) no absolute home path ───────────────────────────────────────
# verify/teeth is EXCLUDED, and the first version of this check was
# wrong about that: a tooth has to WRITE the forbidden path in order to
# prove the check bites, so sweeping the teeth makes the check bite the
# thing that tests it. Exactly the reasoning checks 111 and 116 already
# carry — found here by writing the tooth and watching the check accuse
# it.
#
# SERVICE ACCOUNTS ARE NOT PEOPLE. A container image gives its unprivileged
# user a home too, and that path is the SAME on every installation — it
# names a role inside an image, not a machine of anybody's. Each one is
# declared here with who owns it, because an exception without a reason is
# a hiding place (same bargain as check 116's allowlist):
#
#   jenkins  the agent's user in the Jenkins image — the workspace lives
#            under its home, and a real build failure is quoted verbatim
#            in the app's Jenkinsfile template
#   scanner  trivy's user (chart 0.24.0): its cache is where the
#            vulnerability DB lands, which is what the age CronJob reads
SERVICE_HOMES='jenkins|scanner'
HOMES="$(cd "$AEGIS_ROOT" && command grep -rIn --exclude-dir=.git --exclude-dir=teeth \
    -E '(/home/|/Users/)[a-z_][a-z0-9_-]*/' "${PRODUCT_DIRS[@]}" 2>/dev/null \
    | grep -vE '(/home/|/Users/)(<|\$|\{)' \
    | grep -vE "(/home/|/Users/)($SERVICE_HOMES)/" || true)"
if [[ -n "$HOMES" ]]; then
    D117="$D117 an absolute path under somebody's home directory: $(echo "$HOMES" | head -3 | cut -d: -f1,2 | tr '\n' ' ')(use \$HOME or ~, which say the same thing on every machine);"
fi

# ── (2) the name of whoever runs it ─────────────────────────────────
# A login shorter than four characters, or one that is an ordinary
# English word, would fire on prose and teach the operator to ignore
# this check. Those cases are declared as NOT MEASURED rather than
# silently skipped.
_name_absent() {   # <name> <what it is>
    local name="$1" what="$2" hits
    if [[ -z "$name" ]]; then
        printf '    %s could not be read: NOT measured (this is not a clean bill)\n' "$what"
        return 0
    fi
    if (( ${#name} < 4 )); then
        printf '    %s is "%s", too short to search for without false positives: NOT measured\n' "$what" "$name"
        return 0
    fi
    N117=$((N117+1))
    hits="$(cd "$AEGIS_ROOT" && command grep -rIln --exclude-dir=.git -F -- "$name" \
        "${PRODUCT_DIRS[@]}" 2>/dev/null || true)"
    [[ -z "$hits" ]] && return 0
    D117="$D117 the product names $what ('$name') in: $(echo "$hits" | head -3 | tr '\n' ' ')— the artifact is for anybody, and it must not carry the identity of whoever happens to be building it;"
}

_name_absent "${SUDO_USER:-${USER:-$(id -un 2>/dev/null)}}" "the login of whoever is running this"
_name_absent "$(gh api user --jq .login 2>/dev/null || true)" "the GitHub account this machine is authenticated as"

printf '    %s dirs of product swept · %s identity(ies) measured\n' "${#PRODUCT_DIRS[@]}" "$N117"
if [[ -n "$D117" ]]; then fail "the product names a person:$D117"
else pass "the product names no person: no home directory of anybody's, and not the identity of whoever is building it"; fi
}
