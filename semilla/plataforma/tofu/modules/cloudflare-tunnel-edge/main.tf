# módulo cloudflare-tunnel-edge v2 — SOLO recursos Cloudflare-API.
# (v1 tenía padre edge+k8s por historia de bootstrap; en v2 el lado
#  k8s es 100% GitOps, así que el módulo nace edge-only — la
#  simplificación que ADR-0013 hizo a mano, acá es de nacimiento.)

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

variable "account_id" { type = string }
variable "zone_id" { type = string }
variable "root_domain" { type = string }
variable "tunnel_name" { type = string }
variable "ingress_service" { type = string }
variable "public_hostnames" { type = list(string) }

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id    = var.account_id
  name          = var.tunnel_name
  tunnel_secret = random_id.tunnel_secret.b64_std
  # A16: config_src local desde el arranque (cambiarlo es ForceNew)
  config_src    = "local"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = concat(
      [for h in var.public_hostnames : {
        hostname = "${h}.${var.root_domain}"
        service  = var.ingress_service
        # A16: NO declarar origin_request (bug null deserialization
        # del provider v5 — 2026-06-13:195-207)
      }],
      [{ service = "http_status:404" }]
    )
  }
}

resource "cloudflare_dns_record" "cname" {
  for_each = toset(var.public_hostnames)

  zone_id = var.zone_id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true    # A19
  ttl     = 1       # A19: requerido con proxied
}

output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  sensitive = true
}
output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.this.id
}
