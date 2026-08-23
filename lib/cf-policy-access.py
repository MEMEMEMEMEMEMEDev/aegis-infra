#!/usr/bin/env python3
"""Payload para acuñar el token CF de ACCESS (fase 15, #88).

POR QUÉ ES UN TOKEN APARTE y no un permiso más del token del túnel:
el job `edge-apply` de Jenkins está diseñado para recibir SOLO el
token del borde. Si ese token pudiera editar Access, un CI
comprometido podría desprotegerse a sí mismo — quitar las políticas
que lo tienen detrás de Access y quedar expuesto sin que nada avise.
La separación es el mecanismo; este archivo es la mitad que faltaba
para que una instancia NUEVA no naciera sin ella (#88).

Permisos:
  - Access: Apps and Policies / Write   (las 4 aplicaciones + 3 políticas)
  - Access: Service Tokens / Write      (el service token de la automatización)

AMBOS de CUENTA, no de zona, y eso no es una decisión nuestra:
Cloudflare Access es un recurso de cuenta. No se puede acotar más.
Es la excepción declarada a D6, y por eso el token es exclusivo de
Access: si su radio no se puede achicar, se achica lo que puede
tocar.

Los permission groups se matchean POR NOMBRE contra la lista viva de
la API (argv[1]) — cero IDs de memoria. Si un nombre no matchea, sale
1 LISTANDO lo disponible.

NOTA HONESTA sobre los patrones de abajo. Los de cf-policy-tunnel.py
y cf-policy-dns.py están CONFIRMADOS contra la cuenta (validación #3,
2026-07-09). Estos dos NO: la maestra CF es efímera y muere en la
fase 15, así que no había con qué listar los grupos al escribirlos.
Los regex son deliberadamente anchos y el fallo es con evidencia — si
no matchean, el operador ve la lista real y ajusta una línea. Eso es
mejor que un ID de memoria que falla en silencio, pero peor que una
medición, y se dice acá para que no se lea como confirmado.

Uso: cf-policy-access.py <pgroups.json> <token-name> <account-id> <zone-id>
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
