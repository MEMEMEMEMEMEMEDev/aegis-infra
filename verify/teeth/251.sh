# teeth of check 251 — reads (GET, HEAD) without the response-holding buffering.
_sub() {
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
O251="$AEGIS_ROOT/lib/aegis/org.py"

# no sibling: the generator as it was on 2026-09-24
red_1() {
    python3 -c '
import sys; p = sys.argv[1]; s = open(p).read()
i = s.index("        stream = (f\"({match}) && \"")
j = s.index("port: 8080}}\"\"\")", i) + len("port: 8080}}\"\"\")")
open(p, "w").write(s[:i] + "        pass" + s[j:])
' "$O251"
}

# the sibling carries the buffering too
red_2() { _sub "$O251" '        - {{name: {org}-ritmo}}
      services:
        - {{name: {org}-{s['"'"'nombre'"'"']}, port: 8080}}""")
    return' '        - {{name: {org}-ritmo}}
        - {{name: {org}-cuerpo}}
      services:
        - {{name: {org}-{s['"'"'nombre'"'"']}, port: 8080}}""")
    return'; }

# any method: a POST takes the sibling and skips the 10 MiB cap
red_3() { _sub "$O251" '        stream = (f"({match}) && "
                  f"(Method(`GET`) || Method(`HEAD`))")' '        stream = (f"({match}) && "
                  f"(Method(`GET`) || Method(`HEAD`) || Method(`POST`))")'; }

# only GET: a HEAD (a download manager, a Range probe) is still buffered
red_4() { _sub "$O251" ' || Method(`HEAD`))")' ')")'; }

# control: the comment reworded
control_1() { _sub "$O251" 'Headers and the
        # per-visitor rate limit stay: an open stream is one request.' 'Headers and the
        # per-visitor rate limit are kept: an open stream is one request.'; }
