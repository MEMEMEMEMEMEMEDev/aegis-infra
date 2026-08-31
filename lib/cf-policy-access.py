#!/usr/bin/env python3
"""Payload to mint the CF token for ACCESS (phase 15, #88).

WHY IT IS A TOKEN OF ITS OWN and not one more permission on the
tunnel's token: Jenkins' `edge-apply` job is designed to receive ONLY
the edge token. If that token could edit Access, a compromised CI
could un-protect itself — strip away the policies that keep it behind
Access and end up exposed without anything raising an alarm. The
separation is the mechanism; this file is the half that was missing
so that a NEW instance would not be born without it (#88).

Permissions:
  - Access: Apps and Policies / Write   (the 4 applications + 3 policies)
  - Access: Service Tokens / Write      (the automation's service token)

BOTH of them of ACCOUNT, not of zone, and that is not our decision:
Cloudflare Access is an account resource. It cannot be narrowed any
further. It is the declared exception to D6, and that is why the token
is exclusive to Access: if its radius cannot be shrunk, what it can
touch is.

The permission groups are matched BY NAME against the API's live list
(argv[1]) — zero IDs from memory. If a name does not match, it exits 1
LISTING what is available.

AN HONEST NOTE about the patterns below. The ones in
cf-policy-tunnel.py and cf-policy-dns.py are CONFIRMED against the
account (validation #3, 2026-07-09). These two were NOT, and on
2026-08-31 the first live run showed what that cost: the wide regex
matched the WRONG group, the token minted clean, and every Access
policy failed an hour later with a 403 that read like an account
problem. The names below are now the EXACT ones from Cloudflare's
documentation of the endpoints this token calls, with the regex kept
only as a loud fallback for a rename.

Usage: cf-policy-access.py <pgroups.json> <token-name> <account-id> <zone-id>
"""
import json
import re
import sys

pgroups_file, token_name, account_id, zone_id = sys.argv[1:5]
groups = json.load(open(pgroups_file))["result"]


def find(exact, pattern, scope_hint):
    """The EXACT name first, the regex only as a fallback, and loudly.

    Corrected on 2026-08-31, on the first run that ever used this file.
    The regex matched SOMETHING on the live account, the token was
    minted, and every Access policy then failed with 403 auth.forbidden
    — while the service token in the same token's other permission
    worked. A regex that matches the wrong group is worse than one that
    matches nothing: nothing fails at mint time, with the list in front
    of you; the wrong one fails an hour later, inside tofu, as a 403
    that looks like an account problem.

    The exact names come from Cloudflare's own documentation of the
    endpoints this token calls (`POST /accounts/{id}/access/policies`
    requires `Access: Apps and Policies Write`). That is a measurement
    against the docs, which is what this file said it was missing.

    The regex stays as a fallback because Cloudflare renames permission
    groups and a rename should degrade to «found it, but not by the
    name we expected» rather than to a dead init. It says so out loud:
    a fallback nobody hears is how a rename becomes tomorrow's silent
    403.
    """
    # THE SCOPE DISAMBIGUATES, because THE NAME IS NOT UNIQUE. Measured
    # against the live account on 2026-08-31, after a 403 that took most
    # of a day:
    #
    #   Access: Apps and Policies Write  scopes=[com.cloudflare.api.account.zone]
    #   Access: Apps and Policies Write  scopes=[com.cloudflare.api.account]
    #
    # Two different permission groups, same name, different ids. Taking
    # the first match returned the ZONE one, while the policy below
    # grants an ACCOUNT resource: a zone permission over an account
    # resource grants nothing, the token mints clean, and every Access
    # call fails later with 403 auth.forbidden.
    #
    # And the old scope test was no defence: it asked whether "account"
    # was CONTAINED in the scope, and `com.cloudflare.api.account.zone`
    # contains it too. A substring where an identity was needed.
    wanted_scope = f"com.cloudflare.api.{scope_hint}"
    for g in groups:
        if g["name"] == exact and wanted_scope in (g.get("scopes") or []):
            return {"id": g["id"], "name": g["name"]}
    rx = re.compile(pattern, re.I)
    for g in groups:
        if rx.search(g["name"]) and wanted_scope in (g.get("scopes") or []):
            print(f"WARNING: no permission group is named {exact!r} any more; "
                  f"falling back to {g['name']!r} by pattern. If Access calls "
                  f"start failing with 403, this line is where to look.",
                  file=sys.stderr)
            return {"id": g["id"], "name": g["name"]}
    print(f"NO MATCH for {exact!r} nor /{pattern}/ with scope "
          f"{wanted_scope!r}. Available:", file=sys.stderr)
    for g in groups:
        print(f"  - {g['name']}  scopes={g.get('scopes')}", file=sys.stderr)
    sys.exit(1)


apps_write = find("Access: Apps and Policies Write",
                  r"access.*app.*polic.*(write|edit)", "account")
tokens_write = find("Access: Service Tokens Write",
                    r"access.*service\s*token.*(write|edit)", "account")

# WHAT WAS CHOSEN, ON STDERR, ALWAYS. Not only when something fails.
#
# This file spent two days minting a token whose permissions nobody
# could see: the mint succeeded, the phase went green, and tofu got a
# 403 an hour later in another command. Diagnosing it meant asking the
# operator to re-run a curl with the master credential — a credential
# this init destroys on purpose — because the one process that HAD the
# list had printed nothing.
#
# The names are not secret. The token's value is, and it is not here.
# Printing what was granted costs two lines and turns «403 somewhere
# else» into «it was granted THIS, and this is what the account has».
print(f"access token: granting {apps_write['name']!r} + {tokens_write['name']!r}",
      file=sys.stderr)
_others = sorted(g["name"] for g in groups
                 if re.search(r"access|zero\s*trust", g["name"], re.I))
print(f"  (Access-related groups this account offers: {_others})", file=sys.stderr)

print(json.dumps({
    "name": token_name,
    "policies": [
        {"effect": "allow",
         "resources": {f"com.cloudflare.api.account.{account_id}": "*"},
         "permission_groups": [{"id": apps_write["id"]},
                               {"id": tokens_write["id"]}]},
    ],
}))
