# module r2-bucket — the OFF-SITE destination of the backups.
#
# A backup that stays on the same machine it has to survive is not a
# backup. `aegis data backup` writes an age-encrypted bundle onto a
# second disk of the house, and until this module existed that was the
# end of the road: the disk and the machine burn together.
#
# What travels here is the `.age` bundle AS IT IS, never plaintext. The
# bucket is therefore a dumb shelf: it holds ciphertext whose key never
# left the house, so the worst case if this account is compromised is
# somebody deleting the copies — not reading them.
#
# WHY R2 AND NOT S3 OR GCS. Decided by the operator: R2's free tier is
# 10 GB with NO egress charge, and the recovery of a catastrophe is
# precisely a full download. On S3 or GCS the day you need the data is
# the day you pay for it, and a recovery that costs money is a recovery
# that gets postponed. It also lives in the account that already holds
# the zone and the tunnel, so it adds no third party to look after —
# with the consequence that §6 of the protocol states: if that account
# falls, DNS, tunnel and off-site copies fall together.

terraform {
  required_providers {
    # `~> 5.12` and not the house's usual `~> 5.0`: measured on
    # 2026-08-29 against the provider's own generated docs and its
    # CHANGELOG — `cloudflare_r2_bucket` has been there since 5.0, but
    # `cloudflare_r2_bucket_lifecycle` appears with 5.12.0 (2025-10).
    # Pinning `~> 5.0` here would let a lockfile resolve to a 5.x that
    # does not know the lifecycle resource, and the apply would fail
    # with «invalid resource type» on a tree that reads correct.
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.12" }
  }
}

variable "account_id" { type = string }

variable "name" {
  description = "Bucket name. Derived by `aegis data` from the instance's root domain, never written by hand: the same string is the one the token's access policy names, and two hands writing it twice is how they drift."
  type        = string
}

variable "jurisdiction" {
  description = "R2 jurisdiction. `default` unless the data has to stay inside a legal boundary. It is part of the token's resource string, so changing it here without changing the credential leaves a token that signs for another bucket."
  type        = string
  default     = "default"
}

variable "retention_days" {
  description = "Days after which a bundle is deleted by R2 itself. 0 disables the rule and the shelf grows for ever — which on a 10 GB free tier is a bill or a refusal, not a warning."
  type        = number
  default     = 90
}

resource "cloudflare_r2_bucket" "this" {
  account_id   = var.account_id
  name         = var.name
  jurisdiction = var.jurisdiction

  # NO `location` on purpose. The provider's own doc says it is honored
  # only the FIRST time a bucket of this name is created and is
  # best-effort even then, so writing it would be declaring something
  # tofu cannot converge on: a plan that never comes out empty.
}

# THE BUCKET IS PRIVATE, and it is private by NOT doing something: R2
# serves nothing publicly until a custom domain or the managed r2.dev
# subdomain is attached to it (`cloudflare_r2_custom_domain`,
# `cloudflare_r2_managed_domain`). Neither resource is declared here and
# neither ever should be — a public bucket of backups is a public bundle
# of everything the platform holds, encrypted, offered for offline
# cracking. There is no `public = false` to set: the guarantee is the
# absence, which is exactly the kind of thing a reader cannot see, hence
# this paragraph and the check that watches for those two resource types.

# ── The retention, which is what keeps this inside the free tier ────
#
# The bundles are cumulative: one per organization per run, and at 24 h
# a year is 365 of them. Nothing in aegis deletes them from the far
# side, and a `delete` issued by the machine that is being backed up is
# the one operation an attacker on that machine would love to have —
# so the deletion is R2's own, on a rule this account holds and the
# instance's token cannot edit (it only writes objects).
#
# `delete_objects_transition` with type `Age` and `max_age` in SECONDS
# — verified 2026-08-29 against the provider's generated schema, where
# max_age is a plain number and the condition type's only accepted
# value is "Age".
#
# `abort_multipart_uploads_transition` goes with it and is not
# decoration: a bundle upload cut halfway leaves parts that COUNT
# towards the stored bytes and that no listing shows. That is the exact
# shape of a free tier quietly exhausted by something nobody can see.
resource "cloudflare_r2_bucket_lifecycle" "retention" {
  count = var.retention_days > 0 ? 1 : 0

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.this.name
  jurisdiction = var.jurisdiction

  rules = [{
    id         = "aegis-backups-retention"
    enabled    = true
    conditions = { prefix = "" }

    delete_objects_transition = {
      condition = { type = "Age", max_age = var.retention_days * 86400 }
    }
    abort_multipart_uploads_transition = {
      condition = { type = "Age", max_age = 86400 }
    }
  }]
}

output "bucket" {
  value = cloudflare_r2_bucket.this.name
}

# The string an R2 API token's access policy has to name to be scoped to
# THIS bucket and nothing else. It comes out of here and not out of the
# phase that mints the token, so that the two cannot disagree about the
# jurisdiction: the format is
# `com.cloudflare.edge.r2.bucket.<ACCOUNT_ID>_<JURISDICTION>_<BUCKET>`,
# verified 2026-08-29 against developers.cloudflare.com/r2/api/tokens.
output "token_resource" {
  description = "The resource id an R2 token's access policy names to be scoped to this bucket alone."
  value       = "com.cloudflare.edge.r2.bucket.${var.account_id}_${var.jurisdiction}_${cloudflare_r2_bucket.this.name}"
}

output "s3_endpoint" {
  description = "S3-compatible endpoint. Region is `auto` — R2 ignores it, and the SigV4 signature does not."
  value       = "https://${var.account_id}.r2.cloudflarestorage.com"
}
