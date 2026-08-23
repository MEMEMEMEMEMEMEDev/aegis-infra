terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
  }
}

# ── Cloudflare Access delante del plano de OPERADOR (#76) ───────────
#
# Medido el 2026-08-12 desde fuera del cluster:
#   argocd.<dominio>/            HTTP 200   (login público)
#   argocd.<dominio>/api/version {"Version":"v3.4.3"} a ANÓNIMOS
#   jenkins.<dominio>/login      HTTP 200   X-Jenkins: 2.555.3
#   access_application/policy en tofu -> NINGUNO
#   middleware de Traefik        -> NINGUNO
#
# Los dos publican su versión exacta a cualquiera, que es justo lo que
# hace falta para elegir el CVE. Y el peor camino no es ArgoCD sino
# Jenkins: en jenkins-system viven cosign-signing-key, github-token y
# cloudflare-api-token. Quien entra ahí FIRMA IMÁGENES, y toda la cadena
# de Kyverno deja de significar algo.
#
# ── por qué CUATRO aplicaciones y no dos ────────────────────────────
#
# Poner Access sobre los dos hostnames y nada más rompe CI en silencio.
# Barrido del 2026-08-12 sobre quién entra por esas puertas:
#
#   GitHub  -> jenkins.<dom>/github-webhook/    (2 repos)
#   GitHub  -> argocd.<dom>/api/webhook
#   tooling -> jenkins.<dom>/api/json           (aegis-rotate --verificar)
#   tooling -> argocd.<dom>/api/v1/session      (aegis-rotate --verificar)
#   init    -> jenkins.<dom>/login              (fase 60)
#   init    -> argocd.<dom>                     (fase 35)
#
# Son TRES clases de visitante y cada una necesita una respuesta
# distinta:
#
#   humano     -> Access con OTP al mail. Es el que queremos proteger.
#   GitHub     -> no puede autenticarse: los webhooks no llevan
#                 cabeceras propias. Su ruta va en BYPASS, y por eso
#                 las rutas son aplicaciones separadas: en Access gana
#                 la aplicación de path MÁS ESPECÍFICO.
#   automatización propia -> service token (CF-Access-Client-Id /
#                 -Secret). Es lo que deja que aegis-rotate --verificar
#                 siga midiendo el camino PÚBLICO, que es el que importa.
#
# El bypass es la parte incómoda y conviene mirarla de frente: deja
# `/github-webhook/` abierto a internet. No es un agujero nuevo —hoy
# TODO jenkins.<dom> lo está— y esa ruta ya se defiende sola con el
# HMAC, que es lo que la firma. Lo que Access agrega es que el resto de
# Jenkins deja de estar expuesto.

variable "account_id" { type = string }
variable "root_domain" { type = string }
variable "operador_email" { type = string }
variable "session_duration" {
  type    = string
  default = "24h"
}

# ── el token de servicio para la automatización propia ──────────────
# client_secret sólo se devuelve al CREARLO. Vive en el tfstate, que va
# cifrado al repo (#46) — por eso el .sops.yaml cifra ese archivo ENTERO
# y no por lista de campos.
resource "cloudflare_zero_trust_access_service_token" "aegis" {
  account_id = var.account_id
  name       = "aegis-automatizacion"
  duration   = "8760h" # 1 año; rotarlo entra en aegis-rotate
}

# ── políticas reutilizables ─────────────────────────────────────────
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

# `bypass` + everyone: la ruta queda accesible sin identidad. Es lo
# único que GitHub puede atravesar.
resource "cloudflare_zero_trust_access_policy" "webhook_publico" {
  account_id = var.account_id
  name       = "aegis-webhook-publico"
  decision   = "bypass"
  include    = [{ everyone = {} }]
}

# ── las rutas de webhook, PRIMERO ───────────────────────────────────
# Van declaradas antes que las aplicaciones que las contienen para que
# quede claro en el archivo que son la excepción, no un agregado.
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

# ── el plano de operador, bajo llave ────────────────────────────────
resource "cloudflare_zero_trust_access_application" "jenkins" {
  account_id       = var.account_id
  name             = "aegis · Jenkins"
  domain           = "jenkins.${var.root_domain}"
  type             = "self_hosted"
  session_duration = var.session_duration
  # sin auto_redirect: que la pantalla de Access sea visible es parte de
  # la señal. Un redirect silencioso hace difícil distinguir "Access está
  # puesto" de "Access no llegó a aplicarse".
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
