# Note A17 (HCL): descriptions with no problematic $${} interpolation.
variable "cloudflare_api_token" {
  description = "CF token with Account:Cloudflare Tunnel:Edit + Zone:DNS:Edit. Injected by the wrapper (TF_VAR). No default: without the wrapper the plan ABORTS instead of planning phantom destroys (A14)."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Account ID (public, T1). Injected by the wrapper from aegis-init.conf (run #4: without this, tofu asked for it interactively)."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "ID of the root domain's zone (public, T1)"
  type        = string
}

variable "root_domain" {
  description = "Root domain (ADR-0005: the ONLY source of the value)"
  type        = string
}

variable "operador_email" {
  description = "Mail of the operator who may enter argocd/jenkins through Access (#76). Injected by the wrapper from ACME_EMAIL in aegis-init.conf: it is the same human and there is no reason to keep two sources."
  type        = string
}

variable "cloudflare_access_token" {
  description = "CF token scoped to Access (Apps and Policies + Service Tokens, Write). SEPARATE from api_token on purpose (#76): the edge-apply job receives only the edge one, so a compromised CI cannot disable Access. Measured 2026-08-12: this token returns 403 when creating a tunnel and when creating DNS."
  type        = string
  sensitive   = true
}
