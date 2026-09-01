# scanner of check 168 — a build that installs OS packages must not run
# through the container exec API. Kept as its own file because the
# check's own prose names the offending shape, and the first version
# accused the paragraph that explains the fix. Seventh time in one day.
import pathlib, re, sys

seed = pathlib.Path(sys.argv[1])
# `#` opens a comment in the pod YAML, `//` in Groovy — both only at
# the start of a line or after whitespace, so ${var#pat} and https://
# survive.
HASH = re.compile(r'(^|\s)#.*$')
SLASH = re.compile(r'(^|\s)//.*$')
def code_of(text):
    return "\n".join(SLASH.sub(r'\1', HASH.sub(r'\1', l)) for l in text.splitlines())

# `upgrade` as well as `install`: both unpack packages, and the CPU
# lane needed only an upgrade to bring its base's openssl up to the
# fixed version — which is enough to meet the exec-API fault.
APT = re.compile(r'apt-get\s+(install|upgrade)')
EXECAPI = re.compile(r"container\(\s*['\"]kaniko['\"]\s*\)")

n = 0
for cf in sorted(seed.rglob("Containerfile*")):
    if not cf.is_file():
        continue
    if not APT.search(code_of(cf.read_text(encoding="utf-8", errors="replace"))):
        continue
    n += 1
    jf = cf.parent / "Jenkinsfile"
    rel = cf.relative_to(seed)
    if not jf.is_file():
        print(f"{rel} installs OS packages and has no pipeline beside it, so nothing says how it is built")
        continue
    body = code_of(jf.read_text(encoding="utf-8", errors="replace"))
    if EXECAPI.search(body):
        print(f"{jf.relative_to(seed)} builds {rel} — which runs apt-get install — through "
              f"container('kaniko'), the exec API: the build dies with «permission denied» AFTER "
              f"the apt RUN prints its whole output, and the cause is nowhere near the symptom")
    if "kaniko.args" not in body:
        print(f"{jf.relative_to(seed)} builds a Containerfile that installs OS packages and does not "
              f"drive kaniko from the container's own process tree (no arguments file): the "
              f"arrangement measured to work is not the one in place")
print(f"__COUNT__ {n}", file=sys.stderr)
