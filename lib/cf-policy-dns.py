#!/usr/bin/env python3
"""Payload para acuñar el token CF de cert-manager DNS-01 (fase 15).

Permisos (los del protocolo v1): Zone/Zone/Read + Zone/DNS/Edit,
acotado a LA zona. Match por nombre contra la lista viva — ver
cf-policy-tunnel.py para la mecánica y el fallo-con-evidencia.
Uso: cf-policy-dns.py <pgroups.json> <token-name> <account-id> <zone-id>
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
    print(f"NO MATCH para /{pattern}/ (scope ~{scope_hint}). Disponibles:",
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
