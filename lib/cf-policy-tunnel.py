#!/usr/bin/env python3
"""Payload to mint the CF token for the TUNNEL (phase 15, D11).

Permissions (the same ones protocol v1 asked to be created by hand):
  - Account / Cloudflare Tunnel / Edit  (create+configure the tunnel)
  - Zone / DNS / Edit over THE zone     (the CNAMEs of the tofu module)

The permission groups are matched BY NAME against the API's live list
(argv[1]) — zero IDs from memory. If a name does not match, it exits 1
LISTING what is available (evidence for adjusting the pattern).

REAL names confirmed against the account (validation #3, 2026-07-09,
endpoint /accounts/{id}/tokens/permission_groups):
  "Cloudflare Tunnel Write"  scope com.cloudflare.api.account
  "DNS Write" / "Zone Read"  scope com.cloudflare.api.account.zone
The regexes below match them; the dynamic match is kept (it survives
future renames, with failure-with-evidence).
Usage: cf-policy-tunnel.py <pgroups.json> <token-name> <account-id> <zone-id>
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


tunnel_edit = find(r"(cloudflare|argo)\s*tunnel.*(write|edit)", "account")
dns_edit = find(r"^dns\s*write$", "zone")

print(json.dumps({
    "name": token_name,
    "policies": [
        {"effect": "allow",
         "resources": {f"com.cloudflare.api.account.{account_id}": "*"},
         "permission_groups": [{"id": tunnel_edit["id"]}]},
        {"effect": "allow",
         "resources": {f"com.cloudflare.api.account.zone.{zone_id}": "*"},
         "permission_groups": [{"id": dns_edit["id"]}]},
    ],
}))
