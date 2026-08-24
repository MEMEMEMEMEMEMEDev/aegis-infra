#!/usr/bin/env bash
# verify/lib.sh — what every check has at hand.
#
# In v2 the verifier was ONE file of 3938 lines, and the four idioms
# below were copied 91, 38, 16 and 11 times. Every copy was a chance to
# write it differently: three times a tooth ended up biting the check
# itself instead of the artifact (checks 22, 25, 66 and 71 tell it in
# their own comments — "a mention is not a use"). That is the class that
# happened more than twice, so it deserves a mechanism.
#
# WHAT A CHECK MAY DO:
#   check() { ... ; pass "…" }   or   fail "…"     EXACTLY ONCE.
# A check that emits no verdict is not "green": it is the missing line,
# and the runner reports it FAIL. A check that emits two is a bug in the
# verifier and exits 3. Neither can be covered up by the check's author:
# the runner counts them.
#
# There is NO `set -e` here and NO `pipefail`. The reason is measured (H2
# of run #15, reproduced 190/200): the dominant pattern is
# `nc file | grep -q pattern`, and grep -q exits on the FIRST match → the
# producer gets SIGPIPE (141) if it was still writing → with pipefail the
# pipeline "fails" depending on the scheduler and a red appears that does
# not depend on the tree. Checks count EXPLICIT failures, not pipeline rcs.

# ── the verdict ──────────────────────────────────────────────────────
# Written to a file and NOT to a variable: each check runs in its own
# subshell (so one check's variable cannot leak into the next — v2 had 4
# such couplings), and a variable does not survive the subshell. The
# runner reads the file and counts.
pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; printf 'PASS\t%s\n' "$*" >> "$AEGIS_VERDICT_FILE"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; printf 'FAIL\t%s\n' "$*" >> "$AEGIS_VERDICT_FILE"; }

# NOT EVALUABLE: the instrument never reached the subject. It is NOT
# green and NOT red — it is the third outcome (03 §3, rc 2). A profile
# check that does not apply SAYS SO with this instead of passing on
# nothing, which is exactly the silence that v2's check 90 was born to
# kill.
skip() { printf '\033[1;33mSKIP\033[0m %s\n' "$*"; printf 'SKIP\t%s\n' "$*" >> "$AEGIS_VERDICT_FILE"; }

# ── the four idioms ──────────────────────────────────────────────────
# nc: the file without its comments. A check looking for `|| true` in the
# code cannot be fooled by a comment that EXPLAINS why there is no
# `|| true` — half of v2's false reds came from there.
nc() { grep -vE '^[[:space:]]*#' "$@"; }

# nc_hits: the same, but over `grep -n` output (file:NN:text).
nc_hits() { grep -vE ':[0-9]+:[[:space:]]*#'; }

# joincont: joins backslash line continuations. Without it, a command
# split across five lines looks like five commands and the structural
# guards read it wrong.
joincont() { sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$@"; }

# body_of FN FILE: the body of a bash function, from `fn() {` to its `}`
# in column 0. It is what allows asking "does THIS FUNCTION do X?"
# instead of "does the file mention X?" — the distinction checks 22, 25,
# 66 and 71 paid dearly for.
body_of() { awk -v fn="$1" 'index($0, fn "()")==1,/^\}/' "$2"; }

# body_nc: the body, without comments (the most frequent combination).
body_nc() { body_of "$1" "$2" | grep -vE '^[[:space:]]*#'; }

# ── where each thing is ──────────────────────────────────────────────
# A check does NOT recompute paths: it receives them. (The same principle
# as lib/paths.sh for the product.)
: "${AEGIS_ROOT:?verify/lib.sh requires AEGIS_ROOT}"
P="$AEGIS_ROOT/seed/platform"   # the SEED — the artifact under test
PHASES="$AEGIS_ROOT/init/phases"
LIBS="$AEGIS_ROOT/lib"
LIBEXEC="$AEGIS_ROOT/libexec"
SEED="$AEGIS_ROOT/seed"
export P PHASES LIBS LIBEXEC SEED

# ── profile ──────────────────────────────────────────────────────────
# AEGIS_VERIFY_PROFILE is set by the runner (cloudflare|local). A check
# measuring something profile-specific asks with this and uses skip() for
# the other, with the reason written down.
profile() { printf '%s\n' "${AEGIS_VERIFY_PROFILE:-cloudflare}"; }
is_local() { [[ "$(profile)" == "local" ]]; }

# And where the INSTANCE is, for the checks that need to contrast the
# artifact against the real machine (86 above all). It comes from the
# same resolver the product uses: a check that recomputes paths is a
# check that one day measures something else.
# shellcheck source=../lib/paths.sh
source "$AEGIS_ROOT/lib/paths.sh"
