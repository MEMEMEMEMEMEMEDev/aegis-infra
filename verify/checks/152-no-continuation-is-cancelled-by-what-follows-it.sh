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
# WHERE THE `#` OPENS A COMMENT, which is the correction of 2026-08-29
# and the reason this file no longer contains the paragraph it used to.
# That paragraph claimed the lexer could ignore quotes because «for the
# backslash to be the last non-blank character before the blanks, no
# quote can close after it». It is false, and it was false in the most
# expensive direction: the check accused code that loses nothing. The
# quote does not have to close before the backslash — it closes after
# the `#`, on the same line. Measured, three times, in bash:
#
#   · `msg "the patch wrote: curl -sS \  # marker"` prints the whole
#     string, backslash and hash included, and the next line runs
#     normally. The `#` is INSIDE the quotes: nothing was lost, and the
#     old lexer painted it red. This is the shape every note about this
#     very bug takes when it is written inside an `echo`, a `msg` or the
#     text of a `fail` — so the check bit the prose that documents it,
#     which is exactly the death the comment-line exemption below was
#     written to avoid.
#   · `v="$(f a b -X POST \  # marker` followed by its tail loses the
#     tail — `[a][b][ ]`, and `--max-time: command not found` — because
#     `$(` opens a COMMAND context inside the double quotes, and a
#     command context is where a `#` opens a comment again. That is the
#     founding regression itself: `code_bad="$(curl_access …`. A lexer
#     that stopped at the first quote would have missed it.
#   · `printf '[%s]' one "$(awk 'BEGIN{…} # x' </dev/null)" \  # bug`
#     loses its tail too. The first `#` is inside single quotes and
#     opens nothing; the second one, back at the top level, opens the
#     comment. The old header named this shape as the one thing it
#     knowingly missed. It is measured now.
#
# The trailing-blank half needed the same correction and for the same
# reason. A line that ends in `\` + blanks INSIDE a double-quoted string
# loses nothing either: measured, `msg "a string that continues \` +
# three blanks, closed on the line below, prints the backslash, the
# blanks and the newline, and the next line still runs. So `lex` reports
# whether a quote is still open when the line ends, and that half stays
# silent when one is. An open `$(` does NOT silence it — inside a
# substitution bash is reading a command, and there the blank really is
# escaped.
#
# So `lex` tracks single quotes, double quotes, and the
# command substitutions that RESTART the quoting state inside them. It
# is still a reading of ONE physical line, and the direction of its
# remaining error is deliberate: when the state is lost, the lexer
# believes it is inside a quote and stays silent. A check of this kind
# may miss; it may not accuse.
#
# THE SUBJECT is derived, never listed, and it is bigger than the
# scripts:
#
#   · every file that is a shell script — by the `.sh` extension, or by
#     a shell shebang on its first line, which is how bin/aegis and the
#     commands in libexec/ that have no extension get swept.
#
#   · every YAML LITERAL block scalar (`|`) that the product hands to a
#     shell: an ansible `shell:`/`raw:` module, and an `args:` block
#     under a `command:` that names `/bin/sh` or `/bin/bash` with `-c`.
#     This half was added on 2026-08-29 after a review measured that 25
#     lines of shell — with 4 live continuations among them — lived
#     inside `.yml` files and outside the sweep, in the k3s install
#     playbook, the registry trust playbook, the blackbox init container
#     and the trivy-db exporter. A written list of directories goes
#     stale the day somebody adds one; a written list of PLAYBOOKS is
#     worse.
#
#     Why the block scalar and not the whole YAML file: a literal block
#     scalar hands the physical lines to the shell BYTE FOR BYTE, so the
#     defect is identical there. Measured with pyyaml over the k3s
#     playbook — the loaded value comes back carrying `| \\\n`, the
#     backslash and the newline exactly as written, with nothing
#     re-lexed in between. A folded scalar (`>`) reflows its lines and
#     is NOT swept for that reason.
#
# WHAT IS OUT OF SCOPE, and why the boundary is drawn here.
#
#   · A line whose first non-blank character is `#`. bash discarded that
#     whole line before any word existed; there is no command on it to
#     mutilate. That exemption is also what lets the class be
#     DOCUMENTED — the header you are reading writes the grapheme out
#     several times, and a check that bit its own explanation would be
#     deleted within a week.
#
#   · verify/teeth/, for the fourth time and the same reason spelled out
#     in 111, 116, 117 and 151: a tooth CONTAINS the regression on
#     purpose, and this check's teeth have to write the exact grapheme
#     down to reintroduce it. Sweeping them would make the check bite
#     the only thing that proves it works. Its own reds therefore write
#     into files that ARE swept.
#
#   · THE SHELL BEHIND ANOTHER PARSER: the `sh '''…'''` blocks of the
#     Jenkinsfiles and the `RUN` chains of the Containerfiles. The count
#     is printed on every run so the hole cannot be forgotten, and it is
#     declared here instead of being swept for one reason: in both, the
#     physical line is read by ANOTHER lexer before any shell sees it —
#     Groovy's string literal, and the image builder's continuation
#     rule — and what each of them does with a backslash followed by
#     blanks was NOT VERIFIED. It could not be: this host has no groovy
#     interpreter and no image builder (checked: groovy, podman, docker
#     and buildah are all absent). Flagging them would be accusing
#     without measuring, which is the fault this verifier exists to
#     prevent, in the other direction. When there is a machine that can
#     run them, that measurement is what turns this bullet into a third
#     recogniser.
#
#   · A quote or a heredoc that SPANS lines. This is a lexer of one
#     physical line: it starts each line with a clean quoting state, so
#     an interior line of a multi-line string or of a heredoc that ends
#     in `\` + blanks + `#` is read as code and reported. That line is
#     DATA, but it is usually data destined to become somebody else's
#     script, so being told about it is not a false alarm worth
#     engineering away. The line that OPENS such a string is read
#     correctly — the quote is still open at the end of it, and the
#     lexer stays silent.
python3 - "$AEGIS_ROOT" <<'EOF'
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

def is_shell(f, head):
    if f.suffix == ".sh":
        return True
    return bool(SHEBANG.match(head))

def lex(line):
    """(index of the first `#` that opens a comment on this physical
    line, or -1;  whether a QUOTE is still open when the line ends).

    A `#` opens a comment only at the start of a WORD (line start, or
    after a blank) and only OUTSIDE quotes. `$(` restarts the quoting
    state, because inside a command substitution bash is parsing a
    command again — that is where the founding regression lives, and a
    lexer that treated the enclosing `"` as final would have missed it.

    The second value is what the trailing-blank half needs. Inside a
    double-quoted string a backslash followed by blanks is a literal
    backslash and a literal space: the string simply continues on the
    next line and NOTHING is lost, so reporting it would be the same
    false accusation the comment half was corrected for. An open `$(`
    does not suppress anything — inside a substitution bash is reading a
    command, and there the blank is escaped for real."""
    quote, stack, i, n = "", [], 0, len(line)
    while i < n:
        ch = line[i]
        if quote == "'":
            # single quotes escape nothing at all, backslash included
            if ch == "'":
                quote = ""
            i += 1
            continue
        if ch == "\\":
            i += 2       # whatever follows is escaped, `#` and quote alike
            continue
        if quote == '"':
            if ch == '"':
                quote = ""
            elif line.startswith("$(", i):
                stack.append(quote); quote = ""; i += 2
                continue
            i += 1
            continue
        if line.startswith("$(", i):
            stack.append(quote); i += 2
            continue
        if ch == ")" and stack:
            quote = stack.pop(); i += 1
            continue
        if ch in "'\"":
            quote = ch; i += 1
            continue
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            return i, False
        i += 1
    return -1, quote != ""

TRAILING_BS = re.compile(r'(\\*)$')

def lost_continuation(code):
    """True when `code` ends in an ODD run of backslashes: the last one
    escapes the blank that followed it instead of the newline."""
    return len(TRAILING_BS.search(code).group(1)) % 2 == 1

def scan(numbered):
    """the whole rule, over (lineno, text) pairs — the same one for a
    script's lines and for the lines of an embedded block."""
    out = []
    for i, line in numbered:
        c, in_quote = lex(line)
        if c != -1:
            if line[:c].strip() == "":
                continue        # a whole line of comment: no command on it
            if lost_continuation(line[:c].rstrip(" \t")):
                out.append((i, "a comment follows"))
            continue
        if in_quote:
            continue            # the line ends inside a string: see lex()
        stripped = line.rstrip(" \t")
        if stripped != line and lost_continuation(stripped):
            out.append((i, "trailing blanks follow"))
    return out

# ── the shell that lives inside YAML ──────────────────────────────────
# Only LITERAL block scalars (`|`), never folded ones (`>`): a folded
# scalar reflows its lines, so its physical line ends are not the shell's.
BLOCK_KEY  = re.compile(r'^(\s*)(?:-\s+)?([\w.\-/]+)\s*:\s*\|[-+]?\d*\s*(?:#.*)?$')
BLOCK_ITEM = re.compile(r'^(\s*)-\s*\|[-+]?\d*\s*(?:#.*)?$')
# `command: ["/bin/sh", "-c"]` and its bash spelling: the container SAYS
# that what follows is a shell program, so the args block is shell.
SHELL_EXEC = re.compile(r'^(\s*)(?:-\s+)?(?:command|args)\s*:\s*\[?\s*["\']?/bin/(?:ba)?sh\b')
# the last dotted segment, so `ansible.builtin.shell` and a bare `shell`
# are one rule. `script:` is NOT here: ansible's script module takes a
# path, and jenkins' `script:` in a values.yaml is Groovy.
SHELL_MODULE = ("shell", "raw")

def embedded_shell(text):
    """(lineno, text) for every physical line of every block scalar that
    the product hands to a shell."""
    lines = text.splitlines()
    marked, exec_col, i, n = [], None, 0, len(lines)
    while i < n:
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        col = len(line) - len(line.lstrip())
        # we left the container that declared the shell: a shallower
        # line, or a sibling list item (the next container)
        if exec_col is not None and (col < exec_col
                                     or (col <= exec_col and line.lstrip().startswith("- "))):
            exec_col = None
        if SHELL_EXEC.match(line):
            exec_col = col
            i += 1
            continue
        opener = BLOCK_KEY.match(line) or BLOCK_ITEM.match(line)
        if opener:
            col = len(opener.group(1))
            key = opener.group(2) if opener.re is BLOCK_KEY else ""
            is_sh = (key.rsplit(".", 1)[-1] in SHELL_MODULE
                     or (exec_col is not None and col > exec_col))
            j, body = i + 1, []
            while j < n:
                b = lines[j]
                if b.strip() and (len(b) - len(b.lstrip())) <= col:
                    break
                body.append((j + 1, b))
                j += 1
            if is_sh:
                marked.extend(body)
            i = j
            continue
        i += 1
    return marked

# ── the sweep ─────────────────────────────────────────────────────────
# The count of lines that end in a continuation inside the two homes
# this check declares out of scope. It is measured and printed, never
# judged: a hole with a number on it every run is a hole nobody forgets.
OTHER_PARSER = re.compile(r'^(Jenkinsfile|Containerfile|Dockerfile)')
CONTINUED = re.compile(r'\\[ \t]*$')

found, unread = [], []
n_scripts = n_yaml = n_blocks = n_declared = 0

for f in sorted(ROOT.rglob("*")):
    if not f.is_file() or f.is_symlink():
        continue
    where = f.relative_to(ROOT)
    if not is_swept(where):
        continue
    try:
        raw = f.read_bytes()
    except OSError as e:
        # NOT a `continue`. A file this check cannot open is a file it
        # did not measure, and the old code dropped it silently — with
        # UnicodeDecodeError in the same clause, so a shell script with
        # one latin-1 byte in a comment vanished from the corpus without
        # ever being counted. The decoding half is gone (surrogateescape
        # below never raises, and this rule is pure ASCII); what is left
        # is a real I/O failure, and it is reported.
        unread.append((str(where), e.__class__.__name__))
        continue
    # surrogateescape and not utf-8-strict: every byte survives the round
    # trip, no line is lost to an encoding, and the lexer only ever looks
    # at ASCII graphemes.
    text = raw.decode("utf-8", "surrogateescape")
    head = text.split("\n", 1)[0]
    if is_shell(f, head):
        n_scripts += 1
        hits = scan(list(enumerate(text.splitlines(), 1)))
    elif f.suffix in (".yml", ".yaml"):
        n_yaml += 1
        block = embedded_shell(text)
        if block:
            n_blocks += 1
        hits = scan(block)
    else:
        if OTHER_PARSER.match(f.name):
            n_declared += sum(1 for l in text.splitlines() if CONTINUED.search(l))
        continue
    for i, what in hits:
        found.append((f"{where}:{i}", what))

print(f"    {n_scripts} shell scripts and {n_blocks} embedded shell blocks "
      f"(out of {n_yaml} YAML files) swept for a continuation cancelled by a comment "
      f"or by trailing blanks")
print(f"    {n_declared} continued lines left to another parser (Jenkins `sh`, image "
      f"builder `RUN`): declared out of scope in the header, not measured on this host")

# An empty sweep is NOT a pass. Either count can only be zero if a
# recogniser stopped recognising, and a green over an empty subject is
# the exact silence this check exists to break. Both are counted HERE, by
# the same code that does the sweeping — a second count taken outside
# would answer about a corpus nobody measured. This product cannot exist
# without shell scripts and cannot exist without YAML, so a zero on
# either side is a broken instrument and never a clean tree.
blind = []
if n_scripts == 0:
    blind.append("the sweep recognised no shell script at all")
if n_yaml == 0:
    blind.append("the sweep recognised no YAML file at all")
for msg in blind:
    print(f"    {msg}: the instrument never reached its subject")
for where, kind in unread:
    print(f"    {where} could not be opened ({kind}): it is inside the swept tree and it "
          "was NOT measured, which is a hole in the instrument and not a clean file")

for where, what in found:
    print(f"    {where} ends in a backslash that {what}: bash escapes the BLANK, not the "
          "newline, so the command ends on this line and everything below it runs on its own. "
          "`bash -n` calls it valid. Put the backslash last on the line — and if the tail was a "
          "scanner marker, remove the reason the marker was needed instead "
          "(libexec/aegis-rotate's _wrong_password is that pattern)")

# 5 and 6, and not 1 and 2, on purpose. python exits 1 on an uncaught
# exception and 2 on a bad command line, and the old check mapped ANY
# non-zero to «a line continuation is cancelled» — so a missing
# interpreter (127) was reported as a defect in the tree, and the reader
# was sent to look for a backslash that did not exist. Measured with a
# stub: `python3` returning 127 printed `command not found` and then the
# tree's verdict. Nothing but this script ever exits 5 or 6, so the
# caller can tell «measured and red» from «never ran».
sys.exit(5 if found else (6 if (blind or unread) else 0))
EOF
rc152=$?

if [[ "$rc152" == 5 ]]; then
    fail "a line continuation is cancelled on its own line: (see the detail above);"
elif [[ "$rc152" == 6 ]]; then
    fail "this check did not reach part of its own subject: (see the detail above). A sweep that measured nothing is not a clean tree;"
elif [[ "$rc152" != 0 ]]; then
    fail "this check measured NOTHING: python3 exited $rc152 before the sweep gave a verdict (127 = no interpreter on this host). Fail-closed on purpose, and named for what it is: the instrument did not run, so the tree was not accused;"
else
    pass "no shell of the product ends a line in a continuation that bash reads as an escaped blank: not in a script, not in the shell embedded in YAML — no comment and no trailing blank follows a continuation"
fi
}
