# title: a FROM pinned by another installation is repointed by a verb, and by the registry that will serve it
# origin: new in v3 — 2026-09-02, after four repos were rewritten by hand during an install from zero
check() {
# MEASURED on 2026-09-01, installing from zero.
#
# An application repo pins its bases the way the protocol demands
# (images.md §3.3) — internal registry, tag and digest:
#
#     FROM <internal>/aegis-base-nginx:3.22-000001@sha256:394ed28…
#
# and that digest was measured in the registry of the installation the
# repo last built on. The new installation serves the SAME tag with
# ANOTHER digest, because it built the base itself; and for a base the
# platform owns, frequently under another tag too — 3.22-000001 there,
# 3.22-000004 here. Jenkinsfile.app's `from-guard` refuses the build,
# and it is right to: nothing of that image passed through this
# installation's scan or its key. Four repos, four hand edits.
#
# The hand edit was the whole bug. Everything the operation needs
# already existed and nobody had joined it up: phase 80 does exactly
# this for the canary, `aegis ci digests` prints what the registry
# holds «for a human to read BEFORE bumping a consumer's FROM by hand»,
# and `aegis image from` answers with the reference — the only command
# that knows the internal digest and the only one that REFUSES an image
# that is present and unsigned.
#
# So this check asks four things of `aegis app rebase`, and each one is
# a different way for the verb to exist and not work:
#
#   1. it exists where the product can see it — the `# aegis-subcommands:`
#      header, a subparser, a dispatch;
#   2. it REWRITES. The rewriter is exercised over a Containerfile of
#      every shape: a verb that returns without touching a FROM leaves
#      the operator exactly where they were, with four repos to edit;
#   3. the reference comes from `aegis image from` and from nowhere
#      else — no table of digests in the product, which would be a
#      second place for the truth to live and the stale one is always
#      the cheaper to read;
#   4. it has a dry mode, and it does not push. Pinning an image and
#      putting it in production are two decisions (images.md §2).
D175=""
APP="$LIBEXEC/aegis-app"
[[ -f "$APP" ]] || { fail "libexec/aegis-app does not exist: this check has no subject"; return; }

# The scan is python and it lives in its own file, for the two reasons
# this house has already paid for: a scanner that dies in silence turns
# a check green (166), and a grep that reads the paragraph explaining
# the fix accuses the fix (161, 163, 165, 166, 167, 168 — and the first
# version of most of them). It reads the code with the AST, which never
# sees a comment, and it EXERCISES the rewriter instead of believing it.
OUT="$(python3 "$AEGIS_ROOT/verify/checks/175.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC == 3 )); then
    skip "libexec/aegis-app cannot be imported here (pyyaml?), so the rewriter could not be exercised: this is «I could not look», not «it is fine»"
    return
fi
if (( RC != 0 )); then
    fail "the scan of check 175 itself failed (rc $RC) and this check measured nothing about the verb"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D175="$D175 $hit;"
done <<< "$OUT"

N="$(python3 "$AEGIS_ROOT/verify/checks/175.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2}')"
printf '    %s cases exercised against the rewriter and its tag derivation\n' "${N:-0}"
if [[ -n "$D175" ]]; then fail "a repo pinned by another installation is not repointed by the product:$D175"
else pass "aegis app rebase exists, rewrites every FROM that names the internal registry and only those, derives the tag from the artifact that owns it, takes the digest from aegis image from, has a dry mode and never pushes"; fi
}
