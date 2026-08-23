# ── Grafana, bajo la misma llave (B4 — fase-85 §5) ──────────────────
#
# Archivo NUEVO y no una edición de main.tf A PROPÓSITO: HCL fusiona
# todos los .tf del directorio, así que esta application viaja de la
# semilla a una instancia viva como copia verbatim, sin cirugía de
# merge (la fase 85 hace exactamente esa copia si falta). El check 90
# la descubre solo: deriva la lista de hostnames protegidos de los
# `domain` de TODOS los .tf del módulo.
#
# Grafana entra al molde de jenkins/argocd — las mismas DOS clases de
# visitante, las mismas dos políticas:
#
#   humano     -> Access con OTP al mail. Grafana conserva además su
#                 login propio: Access es la puerta, no la única
#                 cerradura (fase-85 §3).
#   automatización propia -> service token. `aegis-rotate --verificar`
#                 (ver_grafana_admin) mide la credencial por el camino
#                 PÚBLICO atravesando Access con curl_access; sin esta
#                 política la rotación de grafana_admin_pass no
#                 tendría cómo verificarse.
#
# Sin ruta de webhook: a Grafana no entra GitHub ni nadie sin
# identidad, así que acá no hay bypass. Y ntfy NO aparece en este
# módulo a propósito: la app del teléfono no puede presentar service
# token ni pasar el login de Access — su cerradura es el deny-all
# propio + los tres middlewares del borde (fase-85 §5, check 91).

resource "cloudflare_zero_trust_access_application" "grafana" {
  account_id       = var.account_id
  name             = "aegis · Grafana"
  domain           = "grafana.${var.root_domain}"
  type             = "self_hosted"
  session_duration = var.session_duration
  # sin auto_redirect, como jenkins/argocd (main.tf): que la pantalla
  # de Access sea visible es parte de la señal.
  auto_redirect_to_identity = false
  policies = [
    { id = cloudflare_zero_trust_access_policy.operador.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.automatizacion.id, precedence = 2 },
  ]
}
