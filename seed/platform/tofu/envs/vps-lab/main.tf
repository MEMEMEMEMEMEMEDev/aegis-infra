# env vps-lab — el túnel de ADMINISTRACIÓN del VPS de laboratorio.
#
# NO es infraestructura de la instancia: es del OPERADOR. `aegis
# destroy` consume envs/cloudflare-tunnel y este env NO se toca (el
# lab sobrevive al teardown de la plataforma — plan/07 §2 de v3 lo
# lista como «lo que no se toca»).
#
# Qué crea: un túnel aparte (`aegis-lab-admin` — convive con
# `aegis-tunnel` de la fase 25: nombres distintos, cero colisión), su
# config con UNA regla de ingress (ssh://localhost:22 DEL VPS: quien
# corre cloudflared es el VPS, localhost es su loopback), el CNAME
# `ssh-lab` en la zona raíz, y la app de Access que solo deja pasar al
# operador. El hostname vive en la zona raíz existente porque no hay
# zona de lab y crearla sería otro acto de panel; para la etapa D
# (recrear e init completo en el lab) hará falta dominio propio o
# zona de lab — los CNAMEs aegis/argocd/jenkins de la fase 25
# chocarían con el cluster casero. Prerrequisito de D, no de esto.
#
# Se aplica con el wrapper, como todo tofu (A14):
#   ./tofu-apply.sh -chdir=envs/vps-lab init|plan|apply
# El token del túnel sale como output sensitive y lo consume
# bin/aegis-vps (render/entregar) — jamás se imprime.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
  # state local, cifrado por el wrapper a terraform.tfstate.enc.json
  # (#46). Contiene el token del túnel del LAB — rotable vía
  # -replace=module.tunnel.random_id.tunnel_secret (vps-lab.md).
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Mismo patrón que envs/cloudflare-tunnel (#76): el token del borde no
# puede tocar Access, así que Access va con SU token y SU provider.
provider "cloudflare" {
  alias     = "access"
  api_token = var.cloudflare_access_token
}

module "tunnel" {
  source = "../../modules/cloudflare-tunnel-edge"

  account_id  = var.cloudflare_account_id
  zone_id     = var.cloudflare_zone_id
  root_domain = var.root_domain
  tunnel_name = "aegis-lab-admin" # ≠ aegis-tunnel: conviven

  ingress_service  = "ssh://localhost:22"
  public_hostnames = ["ssh-lab"]
}

module "access_ssh" {
  source    = "../../modules/cloudflare-access-ssh"
  providers = { cloudflare = cloudflare.access }

  account_id     = var.cloudflare_account_id
  hostname       = "ssh-lab.${var.root_domain}"
  operador_email = var.operador_email
}

output "tunnel_token" {
  value     = module.tunnel.tunnel_token
  sensitive = true
}
output "tunnel_id" {
  value = module.tunnel.tunnel_id
}
output "ssh_hostname" {
  value = "ssh-lab.${var.root_domain}"
}
