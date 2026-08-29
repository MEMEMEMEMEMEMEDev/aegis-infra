# Note A17 (HCL): descriptions with no problematic $${} interpolation.

variable "cloudflare_api_token" {
  description = "CF token with Account:Workers R2 Storage:Edit. IT IS NOT THE TUNNEL ONE the wrapper injects by default: that one cannot create a bucket. Export TF_VAR_cloudflare_api_token before calling the wrapper for this env (backups.md section 2)."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Account ID (public, T1). Injected by the wrapper from aegis-init.conf, like everywhere else."
  type        = string
}

variable "backups_bucket" {
  description = "Bucket name. NO DEFAULT and no default is possible: it is derived from the instance's root domain by `aegis data remote bucket`, and a default here would be a second source that drifts from the one the backup actually writes to. Export TF_VAR_backups_bucket with the output of that command."
  type        = string
}

variable "backups_retention_days" {
  description = "Days R2 keeps a bundle before deleting it by itself. 90 by default: three months of history is what fits, with room to spare, in the free tier of one instance of this size, and the deletion is done by the far side so that the machine being backed up never needs the permission to erase its own copies."
  type        = number
  default     = 90
}
