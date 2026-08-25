# ── Grafana, under the same lock (B4 — phase-85 §5) ─────────────────
#
# A NEW file and not an edit of main.tf ON PURPOSE: HCL merges every
# .tf in the directory, so this application travels from the seed to a
# live instance as a verbatim copy, with no merge surgery (phase 85
# makes exactly that copy if it is missing). Check 90 discovers it on
# its own: it derives the list of protected hostnames from the `domain`
# of ALL the module's .tf files.
#
# Grafana fits the jenkins/argocd mould — the same TWO classes of
# visitor, the same two policies:
#
#   human      -> Access with an OTP to the mail. Grafana also keeps
#                 its own login: Access is the door, not the only lock
#                 (phase-85 §3).
#   our own automation -> service token. `aegis rotate check`
#                 (check_grafana_admin) measures the credential over the
#                 PUBLIC path, crossing Access with curl_access;
#                 without this policy the rotation of
#                 grafana_admin_pass would have no way to be verified.
#
# No webhook route: neither GitHub nor anybody without identity gets
# into Grafana, so there is no bypass here. And ntfy does NOT appear in
# this module on purpose: the phone app cannot present a service token
# nor pass the Access login — its lock is its own deny-all plus the
# three edge middlewares (phase-85 §5, check 91).

resource "cloudflare_zero_trust_access_application" "grafana" {
  account_id       = var.account_id
  name             = "aegis · Grafana"
  domain           = "grafana.${var.root_domain}"
  type             = "self_hosted"
  session_duration = var.session_duration
  # no auto_redirect, like jenkins/argocd (main.tf): the Access screen
  # being visible is part of the signal.
  auto_redirect_to_identity = false
  policies = [
    { id = cloudflare_zero_trust_access_policy.operador.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.automatizacion.id, precedence = 2 },
  ]
}
