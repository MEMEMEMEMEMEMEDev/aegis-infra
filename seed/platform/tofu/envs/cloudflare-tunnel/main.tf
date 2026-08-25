# env cloudflare-tunnel v2 — ONLY the Cloudflare-API side (D6: tofu
# does not manage K8s). The cloudflared Deployment and the token Secret
# live in GitOps (k8s/base/ingress/cloudflare-tunnel, KSOPS).
#
# The TUNNEL_TOKEN is issued by Cloudflare: it leaves here as a
# sensitive OUTPUT and phase 25 of the init encrypts it to KSOPS
# (make_enc_secret). DOCUMENTED EDGE CASE (Q2/27 §5.2): recreating the
# tunnel issues a new token => phase 25 ALWAYS re-encrypts the Secret
# after an apply that recreates it; and the CNAMEs of a lost previous
# tunnel may need manual cleanup in the dashboard (no source — test it
# in the greenfield validation and document the result).
#
# Baked-in rules: provider v5 — do NOT set origin_request (A16),
# config_src local from the start (ForceNew).

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
  # local state (the default backend). No cluster secrets (D2); it
  # contains: the tunnel token (data source, rotatable via API), IDs.
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# A separate provider for Access (#76). It is not ceremony: it is what
# makes the token separation REAL. With a single provider, tofu would
# use the edge token for everything, and that token -the one that goes
# to CI- could disable Access.
provider "cloudflare" {
  alias     = "access"
  api_token = var.cloudflare_access_token
}

module "tunnel" {
  source = "../../modules/cloudflare-tunnel-edge"

  account_id  = var.cloudflare_account_id
  zone_id     = var.cloudflare_zone_id
  root_domain = var.root_domain # ADR-0005: the single variable
  tunnel_name = "aegis-tunnel"

  # ingress: everything to the in-cluster Traefik over HTTP (TLS
  # terminates at the Cloudflare edge; server.insecure downstream —
  # A21):
  ingress_service = "http://traefik.infra-edge.svc.cluster.local:80"

  # public hostnames (proxied CNAMEs, ttl=1 — A19).
  #
  # COUPLING: adding one here creates the CNAME and the tunnel's ingress
  # rule, but it routes NOTHING inside the cluster. Each hostname also
  # needs a traefik IngressRoute mapping the Host to a Service — that
  # one lives in the app's repo. If that side is missing, the hostname
  # resolves, TLS works, and traefik answers 404.
  #
  # `ai` has its OWN hostname and does not live under
  # portafolio.__ROOT_DOMAIN__/api on purpose: this way the kill switch,
  # the WAF rules and the AI rate limits are independent of the site.
  # Turn the AI off and the portfolio stays intact and 100% cacheable,
  # because none of its routes is dynamic.
  #
  # In v1 that hostname serves ONE endpoint: /status (a ~80 byte JSON,
  # cacheable for 10 s). Inference is NOT reachable from the internet
  # yet — the browser goes through the portfolio's BFF, which holds the
  # API key on the server side. The hostname is created now anyway
  # because it gives #25 a target to bind to, it exercises the whole
  # edge path before putting something expensive behind it, and it
  # leaves a health check from outside the cluster.
  # ↓ THIS LINE IS WRITTEN BY `aegis org edge`. Do not edit it by hand.
  #   It is derived from edge.yaml (the platform's doors) plus the
  #   `dominio:` of each contract in orgs/. Adding a hostname by hand
  #   here works until the next `aegis org apply`, which will delete it
  #   without warning because it comes from no contract.
  public_hostnames = ["aegis", "argocd", "jenkins", "grafana", "ntfy"]
}

output "tunnel_token" {
  description = "Connector token — consumed by phase 25 of the init to encrypt the KSOPS Secret. NEVER print it outside the make_enc_secret flow."
  value       = module.tunnel.tunnel_token
  sensitive   = true
}

output "tunnel_id" {
  value = module.tunnel.tunnel_id
}

# ── Access in front of the operator plane (#76) ─────────────────────
# The edge stops being only «which hostnames exist» and becomes also
# «who may come in». It goes in the SAME env as the tunnel on purpose:
# if it were separate, adding a hostname and protecting it would be two
# different applies and one of them could be forgotten.
module "access" {
  source    = "../../modules/cloudflare-access"
  providers = { cloudflare = cloudflare.access }

  account_id     = var.cloudflare_account_id
  root_domain    = var.root_domain
  operador_email = var.operador_email
}

output "access_service_token_client_id" {
  description = "CF-Access-Client-Id for our own automation (aegis rotate check). It is encrypted into the KSOPS Secret; it is never printed."
  value       = module.access.service_token_client_id
  sensitive   = true
}

output "access_service_token_client_secret" {
  value     = module.access.service_token_client_secret
  sensitive = true
}
