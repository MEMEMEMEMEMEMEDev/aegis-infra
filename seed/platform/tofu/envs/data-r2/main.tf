# env data-r2 — the bucket the backups leave the house through.
#
# It is applied by the OPERATOR, not by a phase, and that is a decision
# with a reason: the bucket has to exist before the token that writes
# into it is worth anything, and phase 15 (where the credential is
# minted) runs long before the platform has any data to send. Wiring it
# into the init would put an apply against a third party in the middle
# of the bootstrap for a destination nothing writes to until the first
# `aegis data backup`.
#
#   TF_VAR_cloudflare_api_token="$(...)" \
#   TF_VAR_backups_bucket="$(aegis data remote bucket)" \
#     ./tofu-apply.sh -chdir=envs/data-r2 init
#     ./tofu-apply.sh -chdir=envs/data-r2 apply
#
# READ THAT FIRST LINE. The wrapper injects `cloudflare_api_token` from
# tokens.enc.yaml, and the token in there is the TUNNEL one: it can edit
# a zone and it cannot create a bucket (`Workers R2 Storage Write` is
# another permission group). The wrapper lets the caller override it —
# that is the same door CI uses — and this env is the one place in the
# tree that needs it. The whole sequence is in
# docs/protocols/backups.md §2; it is written there and not only here
# because the day it is needed there is no repo to read, only a
# protocol somebody printed.
#
# THE BUCKET NAME IS NOT WRITTEN HERE. `aegis data remote bucket`
# derives it from the instance's root domain, and the same command is
# the one the backup uses to know where to put the bundle. One
# derivation, one source: the day the two disagree, the backup writes
# into a bucket nobody made and R2 answers 404 forever.
#
# WHAT THIS ENV DOES NOT DO: it does not mint the credential. Tofu can
# create an account token (`cloudflare_account_token`), but its VALUE
# would then live in the tfstate — and this tfstate is committed
# encrypted to the platform repo, where the tunnel's token already
# lives. Adding a second credential to that file widens the blast
# radius of the age key for no gain: phase 15 already mints scoped
# tokens over the API and hands them to a store that is not versioned.

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.12" }
  }
  # local state, encrypted by the wrapper into terraform.tfstate.enc.json
  # (#46). What it holds: the bucket's name and its lifecycle rule. No
  # credential — see the paragraph above.
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

module "backups" {
  source = "../../modules/r2-bucket"

  account_id     = var.cloudflare_account_id
  name           = var.backups_bucket
  retention_days = var.backups_retention_days
}

output "bucket" {
  value = module.backups.bucket
}

# Consumed by phase 15 when it mints the scoped token: the policy has to
# name THIS string or the credential ends up able to write into every
# bucket of the account, which is the opposite of what it is for.
output "token_resource" {
  value = module.backups.token_resource
}

output "s3_endpoint" {
  value = module.backups.s3_endpoint
}
