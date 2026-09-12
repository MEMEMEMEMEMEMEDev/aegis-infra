# teeth for check 130 (the traffic goes to the organization the generator named)
#
# Every red produces numbers. That is the whole problem with this class:
# nothing throws, no query is rejected, every panel fills in — and the
# figures belong to somebody else, or to nobody.

T130="$AEGIS_ROOT/libexec/aegis-traffic"
O130="$AEGIS_ROOT/lib/aegis/org.py"

# THE CLEVER VERSION, which is what this command shipped with for about
# an hour: one loose pattern instead of an exact matcher. It reads `a`
# out of `a-b-c` and gave the portfolio 3 requests out of 3043.
red_1() { python3 - "$T130" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    return f'service=~"org-{org}-{org}-ruteo.*"\''''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    return f'service=~"org-{org}-.*-ruteo.*"\'''', 1))
P
}

# the generator renames the route and nothing over here follows: the
# matcher keeps compiling, vmsingle keeps accepting it, every chart is
# empty, and an empty chart looks like a quiet day
red_2() { sed -i 's/^  name: {org}-ruteo$/  name: {org}-entrada/' "$O130"; }

# the reconciliation goes: requests that belong to no listed
# organization and are not platform traffic simply stop existing
red_3() { sed -i '/steps.already("traffic:total", requests=total, hours=hours)/d' "$T130"; }

# ── controls: real changes that must NOT move the verdict ────────────

# the window changes and the prose with it: neither touches attribution
control_1() { sed -i 's/help="the window to read (24 by default)"/help="hours to read back (24 by default)"/g' "$T130"; }

# one more metric per organization: growing what is measured is not
# changing who it belongs to
control_2() { python3 - "$T130" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "        steps.already(f\"traffic:{org}\", requests=int(requests), errors=int(errors),"
assert s.count(old) == 1
p.write_text(s.replace(old, "        steps.already(f\"traffic:{org}\", requests=int(requests), errors=int(errors), window=w,", 1))
P
}

# prose that names the forbidden shape right beside the code
control_3() { printf '\n# note: the name appears TWICE in the label, so no regular expression\n# can split it — RE2 has no back-references. The names are asked for.\n' >> "$T130"; }
