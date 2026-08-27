# title: every scan exception is dated, bounded (≤ 12 months) and justified
# origin: new in v3 — 2026-08-27, the day image-watch started counting down the exceptions
check() {
# mirror-images/trivyignore.yaml is the list of CVEs the mirror scan
# is allowed to look past. An exception is a MEASUREMENT («this code is
# not linked into the binary, checked on such a day») and it is only
# worth what the measurement is worth: a new upstream build can link
# the code in, and the entry goes on silencing a CVE that is now real.
# That is why every entry carries the day it was measured (in its
# statement) and the day it stops holding (expired_at), and why the
# distance between them is bounded.
#
# WHAT IS MEASURED HERE, and what is not:
#   · the file parses, the list is `vulnerabilities:`;
#   · every entry names a CVE, restricts itself to explicit `paths` (a
#     path-less entry silences the CVE wherever it appears, which is the
#     wildcard the file's own comment forbids), justifies itself in a
#     `statement` that carries the measurement date, and expires on an
#     ISO date;
#   · expired_at ≤ measurement + 12 months. A longer one is not a
#     measurement, it is a permanent hole with a date on it.
# NOT measured: whether the exception has ALREADY expired. That is a
# calendar comparison against today, and a check that does it goes red
# on the same morning in every clone of the product — the day being
# nobody's fault. Time is measured on the INSTANCE: image-watch pushes
# aegis_trivyignore_expires_in_seconds and TrivyIgnoreExpiring reads it.
F="$P/mirror-images/trivyignore.yaml"
[[ -f "$F" ]] || { fail "$F does not exist: the mirror scan has no exception file (an --ignorefile that is missing is a build that dies, not a scan without exceptions)"; return; }
D136=""
python3 - "$F" <<'PY' || D136=" (see the detail above);"
import datetime, re, sys, yaml
p = sys.argv[1]
try:
    doc = yaml.safe_load(open(p))
except Exception as e:
    print(f"    does not parse as YAML: {e}", file=sys.stderr); sys.exit(1)
bad = []
vulns = (doc or {}).get("vulnerabilities")
if not isinstance(vulns, list) or not vulns:
    print("    no `vulnerabilities:` list: trivy reads nothing from this file", file=sys.stderr); sys.exit(1)
DATE = re.compile(r"\b(\d{4}-\d{2}-\d{2})\b")
def iso(s):
    try: return datetime.date.fromisoformat(str(s))
    except ValueError: return None
for i, v in enumerate(vulns, 1):
    if not isinstance(v, dict):
        bad.append(f"entry {i} is not a mapping"); continue
    ident = str(v.get("id", "")) or f"entry {i}"
    if not re.fullmatch(r"CVE-\d{4}-\d{4,}", ident):
        bad.append(f"{ident}: `id` is not a CVE identifier")
    paths = v.get("paths")
    if not isinstance(paths, list) or not paths or not all(isinstance(x, str) and x.strip() for x in paths):
        bad.append(f"{ident}: `paths` is empty or missing — a path-less exception silences the CVE wherever it shows up, which is the wildcard the file forbids")
    st = v.get("statement")
    if not isinstance(st, str) or not st.strip():
        bad.append(f"{ident}: no `statement`: an exception without its reason is a hole, not a measurement")
        measured = None
    else:
        dates = [iso(d) for d in DATE.findall(st)]
        dates = [d for d in dates if d]
        measured = max(dates) if dates else None
        if measured is None:
            bad.append(f"{ident}: the statement carries no measurement date (YYYY-MM-DD): nothing bounds how long it may hold")
    exp = v.get("expired_at")
    exp_d = iso(exp) if exp is not None else None
    if exp is None:
        bad.append(f"{ident}: no `expired_at`: an exception with no end is permanent, and permanent is not what an exception means")
    elif exp_d is None:
        bad.append(f"{ident}: expired_at {exp!r} is not an ISO date (trivy ignores what it cannot parse — and silences the CVE forever)")
    elif measured is not None:
        limit = measured.replace(year=measured.year + 1)
        if exp_d > limit:
            bad.append(f"{ident}: expires {exp_d}, more than 12 months after it was measured ({measured}): the measurement holds for THIS binary, not for a binary two rebuilds away")
        if exp_d <= measured:
            bad.append(f"{ident}: expires {exp_d}, on or before the day it was measured ({measured})")
print(f"    {len(vulns)} exceptions", file=sys.stderr)
for b in bad: print(f"    {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D136" ]]; then fail "trivyignore.yaml:$D136"
else pass "every scan exception names a CVE, restricts its paths, states its measurement date and expires within 12 months of it (whether it has expired is measured on the instance, by image-watch)"; fi
}
