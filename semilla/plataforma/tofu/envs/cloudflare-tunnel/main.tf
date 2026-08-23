# env cloudflare-tunnel v2 — SOLO el lado Cloudflare-API (D6: tofu
# no gestiona K8s). El Deployment cloudflared y el Secret del token
# viven en GitOps (k8s/base/ingress/cloudflare-tunnel, KSOPS).
#
# El TUNNEL_TOKEN lo emite Cloudflare: sale de acá como OUTPUT
# sensitive y la fase 25 del init lo cifra a KSOPS (make_enc_secret).
# CASO BORDE documentado (Q2/27 §5.2): recrear el tunnel emite token
# nuevo => la fase 25 SIEMPRE re-cifra el Secret tras un apply que
# recree; y los CNAMEs de un tunnel anterior perdido pueden requerir
# limpieza manual en el dashboard (sin fuente — probar en la
# validación greenfield y documentar el resultado).
#
# Reglas horneadas: provider v5 — NO setear origin_request (A16),
# config_src local desde el arranque (ForceNew).

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
  # state local (backend por default). Sin secretos de cluster (D2);
  # contiene: token del tunnel (data source, rotable vía API), IDs.
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Provider aparte para Access (#76). No es ceremonia: es lo que hace que
# la separacion de tokens sea REAL. Con un solo provider, tofu usaria el
# token del borde para todo, y ese token -que es el que va a CI- podria
# desactivar Access.
provider "cloudflare" {
  alias     = "access"
  api_token = var.cloudflare_access_token
}

module "tunnel" {
  source = "../../modules/cloudflare-tunnel-edge"

  account_id  = var.cloudflare_account_id
  zone_id     = var.cloudflare_zone_id
  root_domain = var.root_domain # ADR-0005: variable única
  tunnel_name = "aegis-tunnel"

  # ingress: todo al Traefik in-cluster por HTTP (TLS termina en el
  # edge de Cloudflare; server.insecure aguas abajo — A21):
  ingress_service = "http://traefik.infra-edge.svc.cluster.local:80"

  # hostnames públicos (CNAMEs proxied, ttl=1 — A19).
  #
  # ACOPLE: agregar acá crea el CNAME y la regla de ingress del túnel,
  # pero NO enruta nada dentro del cluster. Cada hostname necesita además
  # un IngressRoute de traefik que mapee el Host a un Service — vive en
  # el repo de la app. Si falta ese lado, el hostname resuelve, el TLS
  # funciona, y traefik contesta 404.
  #
  # `ai` tiene hostname PROPIO y no vive bajo portafolio.__ROOT_DOMAIN__/api
  # a propósito: así el kill switch, las reglas de WAF y los rate limits
  # de la AI son independientes del sitio. Se apaga la AI y el portafolio
  # queda intacto y 100% cacheable, porque ninguna de sus rutas es
  # dinámica.
  #
  # En v1 ese hostname sirve UN endpoint: /status (un JSON de ~80 bytes,
  # cacheable 10 s). La inferencia NO es alcanzable desde internet
  # todavía — el navegador pasa por el BFF del portafolio, que tiene la
  # API key del lado servidor. El hostname se crea ahora igual porque le
  # da a #25 un blanco al que atarse, prueba el camino completo del borde
  # antes de poner algo caro detrás, y deja un chequeo de salud desde
  # afuera del cluster.
  # ↓ ESTA LÍNEA LA ESCRIBE `bin/aegis-org`. No editarla a mano.
  #   Se deriva de edge.yaml (las puertas de la plataforma) más el
  #   `dominio:` de cada contrato en orgs/. Agregar un hostname a mano
  #   acá funciona hasta el próximo `aegis-org aplicar`, que lo va a
  #   borrar sin avisar porque no sale de ningún contrato.
  public_hostnames = ["aegis", "argocd", "jenkins"]
}

output "tunnel_token" {
  description = "Connector token — consumido por la fase 25 del init para cifrar el Secret KSOPS. NUNCA imprimir fuera del flujo make_enc_secret."
  value       = module.tunnel.tunnel_token
  sensitive   = true
}

output "tunnel_id" {
  value = module.tunnel.tunnel_id
}

# ── Access delante del plano de operador (#76) ──────────────────────
# El borde deja de ser sólo «qué hostnames existen» y pasa a ser
# también «quién puede entrar». Va en el MISMO env que el túnel a
# propósito: si estuviera aparte, agregar un hostname y protegerlo
# serían dos aplicaciones distintas y una podría olvidarse.
module "access" {
  source    = "../../modules/cloudflare-access"
  providers = { cloudflare = cloudflare.access }

  account_id     = var.cloudflare_account_id
  root_domain    = var.root_domain
  operador_email = var.operador_email
}

output "access_service_token_client_id" {
  description = "CF-Access-Client-Id para la automatizacion propia (aegis-rotate --verificar). Se cifra al Secret KSOPS; nunca se imprime."
  value       = module.access.service_token_client_id
  sensitive   = true
}

output "access_service_token_client_secret" {
  value     = module.access.service_token_client_secret
  sensitive = true
}
