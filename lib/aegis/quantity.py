"""Kubernetes quantities, read and written in ONE place.

These four functions lived inside `org.py` and were private to it,
which was right while `org.py` was the only thing in the product doing
arithmetic with memory. It stopped being true on 2026-09-09, when
`aegis host` started adding up what the cluster reserves against what
the machine has: two parsers for `2Gi` is two chances to read it
differently, and the way that failure shows up is a budget that closes
on one side of the product and not on the other.

The subtlety worth keeping visible is in `_MEM_UNITS`: the two-letter
units come FIRST so that `Ki` wins over `K`. Read the other way round,
a `Ki` parses as a `K` with a stray letter and every sum lands ~2.4 %
short — small enough never to be noticed, big enough to admit a
contract that does not fit.
"""


def cpu(q):
    """A CPU quantity -> millicores. `2` is 2000m, `500m` is 500m."""
    s = str(q).strip()
    return int(s[:-1]) if s.endswith("m") else int(float(s) * 1000)


# Two-letter units FIRST: `Ki` has to win over `K`, or a `Ki` is read as
# a `K` with a stray letter and the sum comes out ~2.4% short — small
# enough never to be noticed and big enough to admit a contract that
# does not fit.
_MEM_UNITS = (("Ki", 2 ** 10), ("Mi", 2 ** 20), ("Gi", 2 ** 30), ("Ti", 2 ** 40),
              ("K", 10 ** 3), ("M", 10 ** 6), ("G", 10 ** 9), ("T", 10 ** 12))


def mem(q):
    """A memory quantity -> bytes."""
    s = str(q).strip()
    for unit, mult in _MEM_UNITS:
        if s.endswith(unit):
            return int(float(s[: -len(unit)]) * mult)
    return int(float(s))


def cpu_str(millis):
    return f"{millis // 1000}" if millis % 1000 == 0 else f"{millis}m"


def mem_str(byts):
    gi = 2 ** 30
    return f"{byts // gi}Gi" if byts >= gi and byts % gi == 0 else f"{byts // 2 ** 20}Mi"
