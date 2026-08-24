#!/usr/bin/env python3
"""Payload to mint the CF token for cert-manager's DNS-01 (phase 15).

Permissions (the ones from protocol v1): Zone/Zone/Read +
Zone/DNS/Edit, scoped to THE zone. Matched by name against the live
list — see cf-policy-tunnel.py for the mechanics and the
failure-with-evidence.
Usage: cf-policy-dns.py <pgroups.json> <token-name> <account-id> <zone-id>
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


zone_read = find(r"^zone\s*read$", "zone")
dns_edit = find(r"^dns\s*write$", "zone")

print(json.dumps({
    "name": token_name,
    "policies": [
        {"effect": "allow",
         "resources": {f"com.cloudflare.api.account.zone.{zone_id}": "*"},
         "permission_groups": [{"id": zone_read["id"]},
                               {"id": dns_edit["id"]}]},
    ],
}))
