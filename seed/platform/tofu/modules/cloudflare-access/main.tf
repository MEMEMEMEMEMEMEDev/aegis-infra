terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
  }
}

# ── Cloudflare Access in front of the OPERATOR plane (#76) ──────────
#
# Measured on 2026-08-12 from outside the cluster:
#   argocd.<domain>/            HTTP 200   (public login)
#   argocd.<domain>/api/version {"Version":"v3.4.3"} to ANONYMOUS
#   jenkins.<domain>/login      HTTP 200   X-Jenkins: 2.555.3
#   access_application/policy in tofu -> NONE
#   Traefik middleware                -> NONE
#
# Both of them publish their exact version to anybody, which is just
# what one needs in order to pick the CVE. And the worst path is not
# ArgoCD but Jenkins: cosign-signing-key, github-token and
# cloudflare-api-token live in jenkins-system. Whoever gets in there
# SIGNS IMAGES, and the whole Kyverno chain stops meaning anything.
#
# ── why FOUR applications and not two ───────────────────────────────
#
# Putting Access over the two hostnames and nothing else breaks CI in
# silence. Sweep of 2026-08-12 over who comes in through those doors:
#
#   GitHub  -> jenkins.<dom>/github-webhook/    (2 repos)
#   GitHub  -> argocd.<dom>/api/webhook
#   tooling -> jenkins.<dom>/api/json           (aegis rotate check)
#   tooling -> argocd.<dom>/api/v1/session      (aegis rotate check)
#   init    -> jenkins.<dom>/login              (phase 60)
#   init    -> argocd.<dom>                     (phase 35)
#
# They are THREE classes of visitor and each one needs a different
# answer:
#
#   human      -> Access with an OTP to the mail. This is the one we
#                 want to protect.
#   GitHub     -> cannot authenticate: webhooks carry no headers of
#                 their own. Its route goes in BYPASS, and that is why
#                 the routes are separate applications: in Access the
#                 application with the MOST SPECIFIC path wins.
#   our own automation -> service token (CF-Access-Client-Id /
#                 -Secret). It is what lets aegis rotate check
#                 keep measuring the PUBLIC path, which is the one that
#                 matters.
#
# The bypass is the uncomfortable part and it is worth looking at head
# on: it leaves `/github-webhook/` open to the internet. It is not a new
# hole —today ALL of jenkins.<dom> is— and that route already defends
# itself with the HMAC that signs it. What Access adds is that the rest
# of Jenkins stops being exposed.

variable "account_id" { type = string }
variable "root_domain" { type = string }
variable "operador_email" { type = string }
variable "session_duration" {
  type    = string
  default = "24h"
}

# ── the service token for our own automation ────────────────────────
# client_secret is returned ONLY WHEN IT IS CREATED. It lives in the
# tfstate, which goes encrypted into the repo (#46) — that is why the
# .sops.yaml encrypts that WHOLE file and not by a list of fields.
resource "cloudflare_zero_trust_access_service_token" "aegis" {
  account_id = var.account_id
  name       = "aegis-automatizacion"
  duration   = "8760h" # 1 year; rotating it goes into aegis-rotate
}

# ── reusable policies ───────────────────────────────────────────────
resource "cloudflare_zero_trust_access_policy" "operador" {
  account_id = var.account_id
  name       = "aegis-operador"
  decision   = "allow"
  include    = [{ email = { email = var.operador_email } }]
}

resource "cloudflare_zero_trust_access_policy" "automatizacion" {
  account_id = var.account_id
  name       = "aegis-automatizacion"
  decision   = "non_identity"
  include = [{ service_token = {
    token_id = cloudflare_zero_trust_access_service_token.aegis.id
  } }]
}

# `bypass` + everyone: the route stays reachable without identity. It is
# the only thing GitHub can get through.
resource "cloudflare_zero_trust_access_policy" "webhook_publico" {
  account_id = var.account_id
  name       = "aegis-webhook-publico"
  decision   = "bypass"
  include    = [{ everyone = {} }]
}

# ── the webhook routes, FIRST ───────────────────────────────────────
# They are declared before the applications that contain them so that
# the file makes it clear they are the exception, not an add-on.
resource "cloudflare_zero_trust_access_application" "jenkins_webhook" {
  account_id       = var.account_id
  name             = "aegis · jenkins webhook (GitHub)"
  domain           = "jenkins.${var.root_domain}/github-webhook/"
  type             = "self_hosted"
  session_duration = "0s"
  policies = [{
    id         = cloudflare_zero_trust_access_policy.webhook_publico.id
    precedence = 1
  }]
}

resource "cloudflare_zero_trust_access_application" "argocd_webhook" {
  account_id       = var.account_id
  name             = "aegis · argocd webhook (GitHub)"
  domain           = "argocd.${var.root_domain}/api/webhook"
  type             = "self_hosted"
  session_duration = "0s"
  policies = [{
    id         = cloudflare_zero_trust_access_policy.webhook_publico.id
    precedence = 1
  }]
}

# ── the operator plane, under lock ──────────────────────────────────
resource "cloudflare_zero_trust_access_application" "jenkins" {
  account_id       = var.account_id
  name             = "aegis · Jenkins"
  domain           = "jenkins.${var.root_domain}"
  type             = "self_hosted"
  session_duration = var.session_duration
  # no auto_redirect: the Access screen being visible is part of the
  # signal. A silent redirect makes it hard to tell "Access is in place"
  # apart from "Access never got applied".
  auto_redirect_to_identity = false
  policies = [
    { id = cloudflare_zero_trust_access_policy.operador.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.automatizacion.id, precedence = 2 },
  ]
}

resource "cloudflare_zero_trust_access_application" "argocd" {
  account_id                = var.account_id
  name                      = "aegis · ArgoCD"
  domain                    = "argocd.${var.root_domain}"
  type                      = "self_hosted"
  session_duration          = var.session_duration
  auto_redirect_to_identity = false
  policies = [
    { id = cloudflare_zero_trust_access_policy.operador.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.automatizacion.id, precedence = 2 },
  ]
}

output "service_token_client_id" {
  value     = cloudflare_zero_trust_access_service_token.aegis.client_id
  sensitive = true
}
output "service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.aegis.client_secret
  sensitive = true
}
