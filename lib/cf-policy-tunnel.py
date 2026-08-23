#!/usr/bin/env python3
"""Payload para acuñar el token CF del TUNNEL (fase 15, D11).

Permisos (los mismos que el protocolo v1 pedía crear a mano):
  - Account / Cloudflare Tunnel / Edit  (crear+configurar el tunnel)
  - Zone / DNS / Edit sobre LA zona     (los CNAMEs del módulo tofu)

Los permission groups se matchean POR NOMBRE contra la lista viva
de la API (argv[1]) — cero IDs de memoria. Si un nombre no matchea,
sale 1 LISTANDO lo disponible (evidencia para ajustar el patrón).

Nombres REALES confirmados contra la cuenta (validación #3,
2026-07-09, endpoint /accounts/{id}/tokens/permission_groups):
  "Cloudflare Tunnel Write"  scope com.cloudflare.api.account
  "DNS Write" / "Zone Read"  scope com.cloudflare.api.account.zone
Los regex de abajo los matchean; se mantiene el match dinámico
(sobrevive renombres futuros con fallo-con-evidencia).
Uso: cf-policy-tunnel.py <pgroups.json> <token-name> <account-id> <zone-id>
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
