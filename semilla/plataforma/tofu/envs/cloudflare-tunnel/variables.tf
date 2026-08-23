# Nota A17 (HCL): descriptions sin interpolación $${} problemática.
variable "cloudflare_api_token" {
  description = "Token CF con Account:Cloudflare Tunnel:Edit + Zone:DNS:Edit. Inyectado por el wrapper (TF_VAR). Sin default: sin wrapper el plan ABORTA en vez de planear destroys fantasma (A14)."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "ID de cuenta (publico, T1). Inyectado por el wrapper desde aegis-init.conf (corrida #4: sin esto, tofu lo pedia interactivo)."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "ID de la zona del dominio raiz (publico, T1)"
  type        = string
}

variable "root_domain" {
  description = "Dominio raiz (ADR-0005: la UNICA fuente del valor)"
  type        = string
}

variable "operador_email" {
  description = "Mail del operador que puede entrar a argocd/jenkins por Access (#76). Inyectado por el wrapper desde ACME_EMAIL de aegis-init.conf: es el mismo humano y no hay razon para tener dos fuentes."
  type        = string
}

variable "cloudflare_access_token" {
  description = "Token CF acotado a Access (Apps and Policies + Service Tokens, Write). SEPARADO del api_token a proposito (#76): el job edge-apply recibe solo el del borde, asi que un CI comprometido no puede desactivar Access. Medido 2026-08-12: este token da 403 al crear tunel y al crear DNS."
  type        = string
  sensitive   = true
}
