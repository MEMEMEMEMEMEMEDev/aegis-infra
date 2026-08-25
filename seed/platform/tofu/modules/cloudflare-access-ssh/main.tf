# ── Cloudflare Access in front of the laboratory VPS's SSH ──────────
#
# The LITTLE brother of modules/cloudflare-access, separate on purpose:
# that one drags along the operator plane's HTTP apps, the webhook
# bypasses and an automation service token that have no business here.
# This module does ONE single thing: the lab's SSH hostname is crossed
# by the operator alone, with an OTP to the mail.
#
# The client is `cloudflared access ssh` (a ProxyCommand in the
# operator's ~/.ssh/config); on the VPS side, cloudflared runs as a
# service with the tunnel token and sshd listens ONLY on loopback.
# With no public port there is no scanning — the root cause the
# 2026-08-22 record identified: the problem was never «we are being
# scanned», it was «there is a public port 22».
#
# type = "self_hosted" and NOT "ssh": the original plan said to try
# type = "ssh" with a fallback. We went straight to the fallback
# because the client flow (`cloudflared access ssh --hostname`) works
# identically with self_hosted, and self_hosted is the type ALREADY
# PROVEN by the sibling module's five applications with this provider
# (~>5.0). Debuting a new app type to gain a label in the dashboard is
# risk without benefit. Documented in docs/protocols/vps-lab.md.

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
  }
}

variable "account_id" { type = string }
variable "hostname" {
  description = "FULL hostname of the SSH app (ssh-lab.<root_domain>); the env assembles it, this module does not know the root domain"
  type        = string
}
variable "operador_email" { type = string }
variable "session_duration" {
  type    = string
  default = "24h"
}

# The only identity that gets through. No service token: automation
# does not come into the lab over SSH — if one day it needs to, that
# is a new decision, not an inherited default.
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
  # no auto_redirect: the visible Access screen is part of the signal
  # (same rule as the sibling module).
  auto_redirect_to_identity = false
  policies = [{
    id         = cloudflare_zero_trust_access_policy.operador.id
    precedence = 1
  }]
}

output "app_id" {
  value = cloudflare_zero_trust_access_application.ssh.id
}
