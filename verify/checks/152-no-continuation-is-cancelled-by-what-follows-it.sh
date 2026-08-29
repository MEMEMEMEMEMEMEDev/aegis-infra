# title: no line continuation is cancelled by what follows it on the same line
# origin: new in v3 — 2026-08-29, the marker that killed three negative teeth in libexec/aegis-rotate
check() {
# THE BUG THIS WAS BORN FROM, and it is written out in the code it
# killed (libexec/aegis-rotate, check_argocd_admin). A patch appended a
# scanner marker to a continued curl:
#
#     curl_access -s -o /dev/null -X POST \  # gitleaks:allow
#         --max-time 30 -d @"$body" "https://argocd.$ROOT_DOMAIN/..."
#
# bash does not read that backslash as a continuation. It escapes the
# BLANK that follows it — the argument list gains one word containing a
# single space — and then the `#`, now at the start of a word, opens a
# comment that eats the rest of the line. The command ENDS there, and
# the lines below it run as commands of their own. Measured, not
# recalled: `printf "[%s]" a b \  # note` prints `[a][b][ ]` and the
# next line comes back «command not found».
#
# What it cost: the three negative calls of `aegis rotate check`
# (ArgoCD, Grafana, ntfy) had been dead since the moment the marker was
# added. curl ran with no URL, the http code came back empty, and the
# verifier would have accused a perfectly healthy ArgoCD of accepting a
# false password. That is this project's defining illness — an
# instrument that no longer reaches its subject and keeps giving a
# verdict — and it arrived through a grapheme that `bash -n` calls
# valid, that no reviewer sees in a diff, and that no check was looking
# at.
#
# THE CLASS, not the symptom. A continuation dies the same silent death
# from two spellings, and they differ by one character nobody can see:
#
#   · `\` then blanks then a COMMENT   — the one above.
#   · `\` then blanks then END OF LINE — the same escaped blank, the
#     same command ended one line early. Measured the same way:
#     `printf "[%s]" a b \` followed by three spaces prints `[a][b][ ]`
#     and does not join the next line either.
#
# Both are measured here, in one verdict, because they are one defect:
# a backslash that the author wrote as a continuation and bash read as
# an escaped blank. Splitting them would let the tree be half-protected
# from a bug whose two halves are indistinguishable to the eye.
#
# THE ODD/EVEN RULE, which is why this is not a grep. Only an ODD run of
# backslashes ending the code is a lost continuation. With an even run
# the last backslash is escaped by the one before it, the token is a
# literal backslash argument, and the command genuinely ends there
# because the author wrote it that way — measured: `printf "[%s]" a b
# \\  # note` prints `[a][b][\]`, nothing was lost. Flagging it would be
# asking an author to change code that does exactly what it says.
#
# WHAT IS OUT OF SCOPE, and why the boundary is drawn here.
#
#   · A line whose first non-blank character is `#`. bash discarded that
#     whole line before any word existed; there is no command on it to
#     mutilate. That exemption is also what lets the class be
#     DOCUMENTED — the header you are reading writes the grapheme out
#     twice, and a check that bit its own explanation would be deleted
#     within a week.
#
#   · verify/teeth/, for the fourth time and the same reason spelled out
#     in 111, 116, 117 and 151: a tooth CONTAINS the regression on
#     purpose, and this check's teeth have to write the exact grapheme
#     down to reintroduce it. Sweeping them would make the check bite
#     the only thing that proves it works. Its own reds therefore write
#     into files that ARE swept.
#
#   · THE LIMIT: this is a LEXICAL reading of physical lines. It does
#     not parse the shell grammar, so it does not know whether a line
#     sits inside a heredoc or a multi-line quoted string. The reason
#     that costs almost nothing is structural, and it is worth saying
#     out loud: for the backslash to be the last non-blank character
#     before the blanks, no quote can close after it — so a backslash
#     inside a quoted string cannot land in this position unless the
#     string spans lines. What remains uncovered is exactly that: a
#     heredoc or a multi-line string whose interior line ends in
#     `\` + blanks + `#`. That line is DATA here, but it is usually
#     data destined to become somebody else's script, so being told
#     about it is not a false alarm worth engineering away.
#
#   · The `#` that opens a comment is taken to be the first one that
#     starts a WORD (at the start of the line, or after a blank).
#     Quotes are not tracked, so `awk '{print} # x' \  # real bug` would
#     be read as already-inside-a-comment and let through. That is the
#     one shape this instrument knowingly misses, and it is named here
#     rather than left for a reader to discover.
#
# THE SUBJECT is derived, never listed: every file under the product
# that is a shell script — by the `.sh` extension, or by a shell shebang
# on its first line, which is how bin/aegis and the sixteen commands in
# libexec/ that have no extension get swept. A written list of
# directories is a list that goes stale the day somebody adds one.
D152=""

if python3 - "$AEGIS_ROOT" <<'EOF'
import pathlib, re, sys

ROOT = pathlib.Path(sys.argv[1])

# `.git` and `__pycache__` are noise wherever they appear; verify/teeth
# is excluded by its PATH and not by its bare name, the same distinction
# check 151 draws: matching a bare name would exempt any future
# directory called `teeth` at any depth.
SKIP_ANYWHERE = {".git", "__pycache__"}
TEETH = ("verify", "teeth")

def is_swept(rel):
    return not (SKIP_ANYWHERE & set(rel.parts)) and rel.parts[:2] != TEETH

SHEBANG = re.compile(r'^#!.*\b(?:ba|da|k|z)?sh\b')

def is_shell(f):
    if f.suffix == ".sh":
        return True
    try:
        with f.open("rb") as fh:
            head = fh.readline(256)
    except OSError:
        return False
    return bool(SHEBANG.match(head.decode("utf-8", "replace")))

def comment_start(line):
    """index of the first `#` that opens a comment, or -1. A `#` opens a
    comment only at the start of a WORD: line start, or after a blank.
    Quotes are not tracked — the header says so and says what it costs."""
    for i, ch in enumerate(line):
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            return i
    return -1

TRAILING_BS = re.compile(r'(\\*)$')

def lost_continuation(code):
    """True when `code` ends in an ODD run of backslashes: the last one
    escapes the blank that followed it instead of the newline."""
    return len(TRAILING_BS.search(code).group(1)) % 2 == 1

found, n_files = [], 0
for f in sorted(ROOT.rglob("*")):
    if not f.is_file() or f.is_symlink():
        continue
    where = f.relative_to(ROOT)
    if not is_swept(where) or not is_shell(f):
        continue
    try:
        text = f.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    n_files += 1
    for i, line in enumerate(text.splitlines(), 1):
        c = comment_start(line)
        if c != -1:
            if line[:c].strip() == "":
                continue        # a whole line of comment: no command on it
            if lost_continuation(line[:c].rstrip(" \t")):
                found.append((f"{where}:{i}", "a comment"))
            continue
        stripped = line.rstrip(" \t")
        if stripped != line and lost_continuation(stripped):
            found.append((f"{where}:{i}", "trailing blanks"))

print(f"    {n_files} shell scripts swept for a continuation cancelled by a comment or by trailing blanks")
# An empty sweep is NOT a pass. This can only be zero if the recogniser
# stopped recognising shell scripts, and a green over an empty subject is
# the exact silence this check exists to break. It is counted HERE, by the
# same code that does the sweeping — a second count taken outside would
# answer about a corpus nobody measured.
if n_files == 0:
    print("    the sweep recognised no shell script at all: the instrument never reached its subject")
for where, what in found:
    print(f"    {where} ends in a backslash that {what} follows: bash escapes the BLANK, not the "
          "newline, so the command ends on this line and everything below it runs on its own. "
          "`bash -n` calls it valid. Put the backslash last on the line — and if the tail was a "
          "scanner marker, remove the reason the marker was needed instead "
          "(libexec/aegis-rotate's _wrong_password is that pattern)")
sys.exit(1 if (found or n_files == 0) else 0)
EOF
then :; else D152="$D152 (see the detail above);"; fi

if [[ -n "$D152" ]]; then fail "a line continuation is cancelled on its own line:$D152"
else pass "no shell script of the product ends a line in a continuation that bash reads as an escaped blank: no comment and no trailing blank follows a continuation"; fi
}
