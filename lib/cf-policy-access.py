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
account (validation #3, 2026-07-09). These two are NOT: the CF master
token is ephemeral and dies in phase 15, so there was nothing to list
the groups with when they were written. The regexes are deliberately
wide and the failure comes with evidence — if they do not match, the
operator sees the real list and adjusts one line. That is better than
an ID from memory that fails silently, but worse than a measurement,
and it is said here so that it is not read as confirmed.

Usage: cf-policy-access.py <pgroups.json> <token-name> <account-id> <zone-id>
"""
import json
import re
import sys

pgroups_file, token_name, account_id, zone_id = sys.argv[1:5]
groups = json.load(open(pgroups_file))["result"]


def find(pattern, scope_hint):
    rx = re.compile(pattern, re.I)
    for g in groups:
        if rx.search(g["name"]) and any(scope_hint in s for s in
                                        g.get("scopes", []) or [scope_hint]):
            return {"id": g["id"], "name": g["name"]}
    print(f"NO MATCH for /{pattern}/ (scope ~{scope_hint}). Available:",
          file=sys.stderr)
    for g in groups:
        print(f"  - {g['name']}  scopes={g.get('scopes')}", file=sys.stderr)
    sys.exit(1)


apps_write = find(r"access.*app.*polic.*(write|edit)", "account")
tokens_write = find(r"access.*service\s*token.*(write|edit)", "account")

print(json.dumps({
    "name": token_name,
    "policies": [
        {"effect": "allow",
         "resources": {f"com.cloudflare.api.account.{account_id}": "*"},
         "permission_groups": [{"id": apps_write["id"]},
                               {"id": tokens_write["id"]}]},
    ],
}))
