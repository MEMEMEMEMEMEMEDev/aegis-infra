# RETIRADO — D10 (2026-07-07)

Este env NO se usa. El lado GitHub salió de tofu por completo:
- repos de trabajo: los CREA la fase 12 del init (gh repo create,
  idempotente con marcador `aegis-v2-disposable`)
- settings (B4 delete_branch_on_merge=false, squash): gh api PATCH
  en fase 12, con gate real contra la API
- webhook ArgoCD (+HMAC): gh api --input en fase 15 (el secret
  jamás toca argv)

Porqué: con los repos pre-creados por gh, tofu acá solo aportaba un
state extra, un PAT propio (eliminado del flujo) y el problema de
import de repos existentes. gh api hace lo mismo idempotente y sin
estado. tofu v2 queda Cloudflare-only.

Los .tf quedan como `.retired-d10` (historia, no config activa).
