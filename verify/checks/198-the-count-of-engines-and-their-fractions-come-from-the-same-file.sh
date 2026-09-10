# title: the VRAM threshold derives the number of engines from the same manifests as their fractions
# origin: new in v3 — measured on 2026-09-09, the day the fraction was derived and the count it multiplies was not
check() {
# `libexec/aegis-ai` opens with thirty lines explaining that the VRAM
# threshold is DERIVED and not written down, and that the history of
# the constant it replaced is "a history of the two halves of one
# decision drifting apart". The block is right and the fix was real.
#
# It was also one term short. The arithmetic is
#
#     total * (1 - frac) - n * overshoot - margin
#
# and on 2026-09-09 `frac` came from the engine manifests while `n`
# came from the ENGINES constant a hundred lines up in the same file.
# So the file that warns about two halves drifting apart kept a pair of
# halves that could drift: add a third engine to the manifests and the
# fraction moves, the count does not, and the threshold comes out
# 200 MiB too generous — permissive, silent, and in the direction that
# lets an OOM through rather than the one that refuses a good start.
#
# What this check protects is the RULE, not the two lines that broke
# it: the two numbers that multiply have to be read from the same
# place, on the same walk. ENGINES survives, because the kubectl loops
# need names to scale and to read; what it may no longer be is an input
# to arithmetic. It is a claim, and the manifests audit it.
#
# The three things measured, all structural — a mention is not a use:
#   · vram_fraction_sum prints TWO fields, from one walk;
#   · the `n` of the arithmetic traces back to that second field, and
#     is NOT the variable that `wc -w` fills;
#   · a disagreement between the two yields -1, which is the file's own
#     honesty rule (an unmeasured threshold is absent, not permissive).
SRC="$LIBEXEC/aegis-ai"
[[ -f "$SRC" ]] || { fail "libexec/aegis-ai is not there: $SRC"; return; }

OUT="$(python3 - "$SRC" <<'PY'
import re, sys

src = open(sys.argv[1], encoding="utf-8").read()

def body(fn, text):
    m = re.search(r'^%s\(\)\s*\{$(.*?)^\}$' % re.escape(fn), text, re.M | re.S)
    return m.group(1) if m else None

def nocomments(b):
    return "\n".join(l for l in b.splitlines() if not l.strip().startswith("#"))

fsum = body("vram_fraction_sum", src)
flim = body("vram_limit_mib", src)

if fsum is None or flim is None:
    missing = ", ".join(n for n, b in (("vram_fraction_sum", fsum),
                                       ("vram_limit_mib", flim)) if b is None)
    print("FAIL%s could not be read from libexec/aegis-ai: with no body there is "
          "nothing to measure, and that is a verdict about the reader" % missing)
    raise SystemExit

# ── 1 · the sum function reports how many it summed ──────────────────
# Two interpolations on one print: the sum and the count, out of the
# same loop. One field means the caller has to find the count
# somewhere else, which is the whole defect.
prints = [l for l in fsum.splitlines() if re.search(r'^\s*print\(', l)]
if not prints:
    print("FAILvram_fraction_sum prints nothing: its caller cannot derive a count "
          "from a function that reports no result")
else:
    if not any(len(re.findall(r'\{[^}]+\}', l)) >= 2 for l in prints):
        print("FAILvram_fraction_sum reports ONE field: the count of engines has to "
              "come out of the same walk as the sum of their fractions, or the "
              "caller reads it from a constant and the two halves drift apart again")

lim = nocomments(flim)

# ── 2 · where each shell variable comes from ─────────────────────────
from_wc = set(re.findall(r'(?:local\s+)?(\w+)\s*;?\s*\1=\$\(echo[^)]*\|\s*wc -w\)', lim))
from_wc |= set(re.findall(r'(\w+)=\$\([^)]*wc -w[^)]*\)', lim))
from_sum = set(re.findall(r'(\w+)=\$\(vram_fraction_sum\)', lim))
if not from_sum:
    print("FAILvram_limit_mib does not capture vram_fraction_sum's output: it cannot "
          "be deriving the count from the manifests if it never reads them")

# variables sliced out of the captured pair, e.g. ${pair#* }
derived_from_sum = set()
for var in from_sum:
    derived_from_sum |= set(re.findall(r'(\w+)=\$\{%s[#%%][^}]*\}' % re.escape(var), lim))

# ── 3 · the `n` of the arithmetic ────────────────────────────────────
m = re.search(r"int\('\$(\w+)'\)\s*,\s*int\('\$VLLM_OVERSHOOT_MIB'\)", lim)
if not m:
    print("FAILthe arithmetic of vram_limit_mib no longer names its terms in the "
          "expected shape: the count multiplying VLLM_OVERSHOOT_MIB could not be "
          "identified, so this check cannot say where it comes from")
else:
    n_var = m.group(1)
    if n_var in from_wc:
        print("FAILthe engine count multiplying VLLM_OVERSHOOT_MIB comes from `wc -w` "
              "over the ENGINES constant ($%s), while the fraction comes from the "
              "manifests: a third engine moves one and not the other, and the "
              "threshold silently grows by one overshoot" % n_var)
    elif n_var not in derived_from_sum:
        print("FAILthe engine count multiplying VLLM_OVERSHOOT_MIB ($%s) does not "
              "trace back to vram_fraction_sum's output: the two terms have to be "
              "read on the same walk or they are free to disagree" % n_var)

# ── 4 · and the claim is audited, not merely kept ────────────────────
# ENGINES may stay — the kubectl loops need it. What it may not do is
# disagree in silence. A comparison that ends in -1 is the file's own
# rule: not measurable means absent, never permissive.
if from_wc:
    guarded = False
    for blk in re.findall(r'if\s+\[[^\n]*\n(?:.*?\n)*?\s*fi', lim):
        if any(v in blk for v in from_wc) and re.search(r'echo\s+-1', blk):
            guarded = True
            break
    if not guarded:
        print("FAILENGINES is counted but never audited: if the list and the "
              "manifests disagree, nothing yields -1 and the threshold is computed "
              "from a claim nobody checked")
else:
    print("    (ENGINES is not counted inside vram_limit_mib at all)")

print("    vram_fraction_sum reports the pair · the arithmetic reads the derived count"
      + (" · the ENGINES claim is audited" if from_wc else ""))
PY
)" || { fail "the reading of libexec/aegis-ai could not be completed"; return; }
printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "the VRAM threshold mixes derived and written-down terms: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "the number of engines and their fractions are read from the same manifests, on the same walk"
fi
}
