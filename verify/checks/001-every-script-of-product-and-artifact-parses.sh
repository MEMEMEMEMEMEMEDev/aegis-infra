# title: every script of the product and of the artifact parses
# origin: verify-static.sh (v2) ══ 1
check() {
# In v2 this swept `-name '*.sh'`, and in v2 that was enough: the
# commands lived in seed/platform/bin/ and nobody looked at them
# either, but at least the phases and the libs ended in .sh.
#
# In v3 the commands are VERBS and carry no extension (libexec/aegis-
# init, libexec/aegis-org…). With the filter by extension, this check
# left out all 20 commands — its own tooth found it: an unclosed
# `case x in` was slipped into libexec/aegis-rotate and it stayed
# green. It is the class «filter by name that stops biting when the
# file changes shape» (H7 of the record), the same one that forced
# check 15a to exclude a DIRECTORY and not a file name.
#
# The language is DERIVED from the shebang, which is the only place
# where it is really written down. And each one is checked with its own
# parser: `bash -n` does not see a broken python command, and in v2
# nobody saw it.
D1="" ; n_bash=0 ; n_py=0
# The scratch file is PER RUN, not a fixed path. It used to be
# $SYN_ERR, an absolute path OUTSIDE the tree — and `--teeth`
# runs up to N mutations in parallel, each in its own copy in /dev/shm
# but all of them sharing that one /tmp name. The verdict could not
# flip (it is driven by bash -n's rc, read immediately) but the error
# TEXT reported could come from another job's file, and one job's
# `rm -f` raced every other job's write. A diagnostic that can report
# another run's error is a diagnostic that sends you to the wrong file.
SYN_ERR="$(mktemp)"
while IFS= read -r f; do
    # TWO signals, in order, and neither of them optional.
    #
    # (1) The SHEBANG, which is where the language is really written
    #     down — and shebang means the line STARTS with `#!`. The
    #     previous version did a `case` over the whole first line, and
    #     on 2026-08-24 a new check titled «the python package really
    #     loads» went down the python branch because its TITLE
    #     contained the word: `ast.parse` was handed a bash file and
    #     001 went red over a healthy file.
    #
    # (2) The EXTENSION, for what legitimately carries no shebang: the
    #     modules in lib/aegis/ are libraries, not commands, and must
    #     not have one. Demanding a shebang left them out of the sweep
    #     — and measuring it showed something worse: under the old rule
    #     they were checked BY ACCIDENT, depending on whether their
    #     docstring mentioned the word «python». Six modules, 5,800
    #     lines, covered by chance.
    #
    # And whatever falls into neither of the two is REPORTED. An
    # executable file that no parser can claim is not an innocent file:
    # it is one that nobody is looking at.
    line1="$(head -c 200 "$f" | head -1)"
    lang=""
    case "$line1" in
        '#!'*bash*|'#!'*/sh|'#!'*" sh") lang=bash ;;
        '#!'*python*)                   lang=python ;;
        *) case "$f" in
               *.sh) lang=bash ;;
               *.py) lang=python ;;
           esac ;;
    esac
    case "$lang" in
        bash)
            if bash -n "$f" 2>$SYN_ERR; then n_bash=$((n_bash+1))
            else D1="$D1 bash: $f: $(head -1 $SYN_ERR);"; fi ;;
        python)
            if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>$SYN_ERR
            then n_py=$((n_py+1))
            else D1="$D1 python: $f: $(tail -1 $SYN_ERR);"; fi ;;
        *)  D1="$D1 no derivable language (neither shebang nor extension): $f;" ;;
    esac
done < <(find "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" "$AEGIS_ROOT/verify" "$P" \
              -type f \( -name '*.sh' -o -name '*.py' -o -perm -u+x \) \
              -not -path '*/__pycache__/*')
# The checks and the teeth carry no shebang —the runner sources them—
# but they do carry `.sh`, so the sweep above already takes them by
# extension. Until 2026-08-24 they had their own loop down here, and
# since the extension became a signal in its own right that loop
# counted them TWICE: 228 duplicated files out of a total of 523.
# Checking twice breaks nothing; a number that lies does.
rm -f "$SYN_ERR"
printf '    %s bash · %s python\n' "$n_bash" "$n_py"
if [[ -n "$D1" ]]; then fail "syntax:$D1"
else pass "every script parses: $n_bash of bash, $n_py of python (language derived from the shebang; the extension backs up what legitimately carries none)"; fi
}
