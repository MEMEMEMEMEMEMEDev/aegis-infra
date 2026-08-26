# env vps-lab — the ADMINISTRATION tunnel of the laboratory VPS.
#
# It is NOT instance infrastructure: it belongs to the OPERATOR. `aegis
# destroy` consumes envs/cloudflare-tunnel and this env is NOT touched
# (the lab survives the platform teardown — plan/07 §2 of v3 lists it
# under «what does not get touched»).
#
# What it creates: a separate tunnel (`aegis-lab-admin` — it coexists
# with `aegis-tunnel` from phase 25: different names, zero collision),
# its config with ONE ingress rule (ssh://localhost:22 OF THE VPS:
# whoever runs cloudflared is the VPS, localhost is its loopback), the
# `ssh-lab` CNAME in the root zone, and the Access app that lets only
# the operator through. The hostname lives in the existing root zone
# because there is no lab zone and creating one would be another act of
# dashboard; for stage D (recreate plus a full init in the lab) a domain
# of its own or a lab zone will be needed — the aegis/argocd/jenkins
# CNAMEs of phase 25 would collide with the home cluster. A prerequisite
# of D, not of this.
#
# It is applied with the wrapper, like all tofu (A14):
#   ./tofu-apply.sh -chdir=envs/vps-lab init|plan|apply
# The tunnel token comes out as a sensitive output and is consumed by
# `aegis vps` (render/entregar) — it is never printed.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
  # local state, encrypted by the wrapper to terraform.tfstate.enc.json
  # (#46). It contains the LAB tunnel's token — rotatable via
  # -replace=module.tunnel.random_id.tunnel_secret (vps-lab.md).
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Same pattern as envs/cloudflare-tunnel (#76): the edge token must not
# touch Access, so Access goes with ITS token and ITS provider.
provider "cloudflare" {
  alias     = "access"
  api_token = var.cloudflare_access_token
}

module "tunnel" {
  source = "../../modules/cloudflare-tunnel-edge"

  account_id  = var.cloudflare_account_id
  zone_id     = var.cloudflare_zone_id
  root_domain = var.root_domain
  tunnel_name = "aegis-lab-admin" # ≠ aegis-tunnel: they coexist

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
