# ── Cloudflare Access delante del SSH del VPS de laboratorio ────────
#
# Hermano CHICO de modules/cloudflare-access, separado a propósito:
# aquél arrastra las apps HTTP del plano de operador, los bypass de
# webhooks y un service token de automatización que acá no pintan
# nada. Este módulo hace UNA sola cosa: el hostname SSH del lab lo
# atraviesa únicamente el operador, con OTP al mail.
#
# El cliente es `cloudflared access ssh` (ProxyCommand en el
# ~/.ssh/config del operador); del lado del VPS, cloudflared corre
# como servicio con el token del túnel y sshd escucha SOLO en
# loopback. Sin puerto público no hay escaneo — la causa raíz que
# identificó el archivo del 2026-08-22: el problema nunca fue «nos
# escanean», fue «hay un 22 público».
#
# type = "self_hosted" y NO "ssh": el plan original decía probar
# type = "ssh" con fallback. Se fue directo al fallback porque el
# flujo del cliente (`cloudflared access ssh --hostname`) funciona
# idéntico con self_hosted, y self_hosted es el tipo YA PROBADO por
# las cinco aplicaciones del módulo hermano con este provider (~>5.0).
# Estrenar un tipo de app nuevo para ganar una etiqueta en el
# dashboard es riesgo sin beneficio. Documentado en
# docs/protocols/vps-lab.md.

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
  }
}

variable "account_id" { type = string }
variable "hostname" {
  description = "Hostname COMPLETO de la app SSH (ssh-lab.<root_domain>); lo arma el env, este módulo no conoce el dominio raíz"
  type        = string
}
variable "operador_email" { type = string }
variable "session_duration" {
  type    = string
  default = "24h"
}

# La única identidad que pasa. Sin service token: la automatización
# no entra al lab por SSH — si un día hace falta, es una decisión
# nueva, no un default heredado.
resource "cloudflare_zero_trust_access_policy" "operador" {
  account_id = var.account_id
  name       = "aegis-lab-operador"
  decision   = "allow"
  include    = [{ email = { email = var.operador_email } }]
}

resource "cloudflare_zero_trust_access_application" "ssh" {
  account_id       = var.account_id
  name             = "aegis · SSH lab"
  domain           = var.hostname
  type             = "self_hosted"
  session_duration = var.session_duration
  # sin auto_redirect: la pantalla de Access visible es parte de la
  # señal (misma regla que el módulo hermano).
  auto_redirect_to_identity = false
  policies = [{
    id         = cloudflare_zero_trust_access_policy.operador.id
    precedence = 1
  }]
}

output "app_id" {
  value = cloudflare_zero_trust_access_application.ssh.id
}
