"""Check 203 — the form is filled from what was measured, and the one guess says it is one.

Importing a repository fills a form for somebody. Every value it puts
there is a value that person is likely to accept without reading, which
is the whole point of filling it — and it is why a form that invents is
worse than a form that is blank. A blank asks.

MEASURED WHILE WRITING IT. The first version of `import_fields` built
the repository's URL as `git@github.com:owner/<name>.git`, with the word
`owner` in it, because the owner was not to hand. That contract
validates. It points at a repository that is not yours, the deploy key
goes to the wrong place, and the first push builds nothing — from a
field somebody was shown already filled and had no reason to doubt.

So: every field is either DERIVED from the reading or left empty, with
exactly one exception. The type is a suggestion taken from the language,
because making somebody choose between six words when five are obviously
wrong is not honesty, it is ceremony — and the form says out loud that
it guessed.
"""
import json
import os
import subprocess
import sys

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))

try:
    from aegis import console
except ImportError:
    print("SCOPE: there is no renderer: this check has no subject")
    sys.exit(0)
if not hasattr(console, "import_fields"):
    print("SCOPE: the console does not import a repository yet: this check has no subject")
    sys.exit(0)

findings = []

# ── the owner comes from the reading, never from a word ──────────────
got = console.import_fields("tienda-web", "TypeScript",
                            "https://github.com/QuienSea/tienda-web")
repo = got.get("servicio0.repo") or ""
if "QuienSea" not in repo:
    findings.append(f"the repository field came out as {repo!r} and the account that owns "
                    f"it is not in it: a contract that names somebody else's repository "
                    f"validates, sends the deploy key to the wrong place, and builds "
                    f"nothing on the first push — from a field that was shown already "
                    f"filled")
if not repo.startswith("git@github.com:"):
    findings.append(f"the repository field is {repo!r} and a contract names its repository "
                    f"the way git clones it over ssh: the generator will reject it, after "
                    f"the person filled in everything else")

# ── with nothing to derive from, it leaves it EMPTY ──────────────────
blind = console.import_fields("tienda-web", "TypeScript", None)
if blind.get("servicio0.repo"):
    findings.append(f"with no URL to derive from, the repository field was invented as "
                    f"{blind['servicio0.repo']!r}: a blank asks, and a wrong value does not")

# ── and it invents nothing else ──────────────────────────────────────
# A hostname made up from a repository name is a CNAME nobody later
# knows why is there, and this console has been careful about that from
# its first screen.
for field in ("dominio", "cuota"):
    if got.get(field):
        findings.append(f"the form arrived with `{field}` filled in as {got[field]!r}, "
                        f"and nothing measured it: a hostname invented from a repository "
                        f"name is a CNAME nobody later knows why is there")

# ── the name is the repository's, and only if the validator takes it ─
if got.get("organizacion") != "tienda-web":
    findings.append(f"the organization's name came out as {got.get('organizacion')!r} "
                    f"rather than the repository's")
import re as _re                                         # noqa: E402

# Names that SURVIVE being tidied up and still fail: a leading digit, a
# name too short, one that is only punctuation. Tidying is not
# validating, and the difference is what this line exists for.
for ugly_name in ("9lives", "ab", "...", "-x-", "A_Repo.With--Junk"):
    name = (console.import_fields(ugly_name, "Go",
                                  "https://github.com/x/y").get("organizacion") or "")
    if name and not _re.match(r"^[a-z][a-z0-9-]{2,29}$", name):
        findings.append(f"the repository {ugly_name!r} filled the organization's name as "
                        f"{name!r}, which the validator refuses: the form would be "
                        f"rejected at the end for a field it filled in itself, and the "
                        f"person would go looking for what they typed wrong")

# ── the guess is a guess, and it is labelled ─────────────────────────
if got.get("servicio0.tipo") not in ("http", "estatico", "worker"):
    findings.append(f"the suggested type is {got.get('servicio0.tipo')!r}, which is not a "
                    f"type a contract can carry")
astro = console.import_fields("un-sitio", "Astro", "https://github.com/x/un-sitio")
if astro.get("servicio0.tipo") != "estatico":
    findings.append("a static-site generator is not suggested as a static service, so the "
                    "suggestion is not worth making")
# The direction of the error matters: a static front declared `http`
# starts and serves; an http service declared `estatico` has nowhere to
# run. A guess has to fail loudly.
for lang in ("Go", "Python", "PHP", "Java", None, "AlgoQueNadieConoce"):
    if console.suggestion_for(lang) != "http":
        findings.append(f"a {lang!r} service is suggested as "
                        f"{console.suggestion_for(lang)!r}: a language nobody has a rule "
                        f"for has to fall towards the type that refuses least, or the "
                        f"guess fails quietly")

try:
    doc = json.loads(subprocess.run(
        [os.path.join(ROOT, "bin", "aegis"), "org", "schema", "--json"],
        capture_output=True, text=True).stdout)
except ValueError:
    doc = {"steps": []}
drawn = console.render_form(doc, "a-token", got)
if "suggested" not in drawn:
    findings.append("the form does not say that the type was guessed: every other value "
                    "on that screen was measured, and a person cannot tell which one was "
                    "not")
plain = console.render_form(doc, "a-token")
if "suggested" in plain:
    findings.append("a form nobody imported into says something was suggested: the label "
                    "has to mean this value came from a guess, or it means nothing")

# ── what goes into a style attribute ─────────────────────────────────
# The language's colour arrives from somebody else's API and is painted
# into an inline `style`. GitHub answering today is not a reason to hand
# its answer to a browser unread: a page that trusts a remote string
# with where it puts it has stopped being a page that only draws what it
# built.
for hostile in ("red; background:url(https://algun-lado/x)", "javascript:alert(1)",
                "#abc; position:fixed; inset:0", "expression(x)", "  #fff  ",
                "var(--ink)", "#12345", "rgb(1,2,3)"):
    if console._is_colour(hostile):
        findings.append(f"{hostile!r} is accepted as a colour and goes into a style "
                        f"attribute: what arrives from an API is not what this page may "
                        f"paint with unread")
for fine in ("#3178c6", "#f1e05a", "#ABC", "#dea584"):
    if not console._is_colour(fine):
        findings.append(f"{fine!r} is refused as a colour, so the dot this screen shows "
                        f"instead of a logo would never be drawn")

for f in findings:
    print(f)
print(f"SCOPE: 4 imports exercised, 6 languages fallen through, 8 hostile colours "
      f"refused, and the form read for its own label")
