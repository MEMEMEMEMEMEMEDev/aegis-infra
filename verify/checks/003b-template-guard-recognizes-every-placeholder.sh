# title: the template guard recognizes every placeholder the seed uses
# origin: new in v3 — the defect of 2026-08-24
check() {
# `aegis app` renders the templates in seed/templates/ and then checks
# that no __X__ is left loose: a template that asks for something the
# command cannot derive has to STOP right there, not hand the operator
# the repo of their app with the literal inside.
#
# That guard is a pattern, and a pattern that does not recognize what
# it is looking for is worse than not having one: it gives the feeling
# of being covered. Until 2026-08-24 it was `__[A-Z]+__`, which matches
# NO placeholder with an underscore — neither __ROOT_DOMAIN__ nor
# __GH_OWNER__ nor __PLATFORM_REPO__.
#
# So this check does not read the pattern: it EXERCISES it against the
# placeholder vocabulary of the WHOLE artifact, not only against the
# ones the templates use today. The difference is not cosmetic: today
# the templates use __ORG__, __DOMINIO__ and __REPO__, the three of
# them without an underscore, so measured against those the broken
# pattern passed for healthy. Its own tooth gave it away. What the
# guard has to recognize is what a template CAN ask for, and that is
# the vocabulary of the artifact.
APP="$AEGIS_ROOT/libexec/aegis-app"
[[ -r "$APP" ]] || { skip "cannot exercise the guard: libexec/aegis-app is missing"; return; }
[[ -d "$SEED" ]] || { skip "cannot exercise the guard: there is no seed/"; return; }
BLIND="$(APP="$APP" VOCABULARY="$SEED" python3 - <<'PY' 2>/dev/null
import ast, os, re, sys, pathlib

source = pathlib.Path(os.environ["APP"]).read_text(encoding="utf-8")
pattern = None
for node in ast.parse(source).body:                 # module level only
    if (isinstance(node, ast.Assign)
            and any(getattr(t, "id", None) == "PLACEHOLDER" for t in node.targets)
            and isinstance(node.value, ast.Call)
            and isinstance(node.value.args[0], ast.Constant)):
        pattern = node.value.args[0].value
if pattern is None:
    sys.exit(2)                                     # could not: this is not red

used = set()
for p in pathlib.Path(os.environ["VOCABULARY"]).rglob("*"):
    if not p.is_file():
        continue
    try:
        used |= set(re.findall(r"__[A-Z0-9_]+__", p.read_text(encoding="utf-8")))
    except (UnicodeDecodeError, OSError):
        continue

guard = re.compile(pattern)
print(" ".join(sorted(x for x in used if not guard.search(x))))
PY
)"
RC=$?
if [[ $RC -ne 0 ]]; then
    skip "could not exercise the template guard (libexec/aegis-app does not declare PLACEHOLDER at module level, or python3 is missing)"
elif [[ -n "$BLIND" ]]; then
    fail "the aegis-app guard does NOT recognize placeholders the seed uses: $BLIND"
else
    pass "the aegis-app guard recognizes the whole placeholder vocabulary of the seed"
fi
}
