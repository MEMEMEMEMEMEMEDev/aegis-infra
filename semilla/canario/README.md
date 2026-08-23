# hello-aegis v2 — canary de la plataforma aegis

REPO DESECHABLE, creado y sembrado automáticamente por aegis-init
(fase 12). El init y la plataforma le ESCRIBEN: builds del CI, tags
`main-NNNNNN`, commits automáticos del Image Updater (write-back).
No poner acá nada que importe. Se borra y regenera con otro
bootstrap.

Estructura: `main.go` + `Containerfile` (app mínima), `Jenkinsfile`
(instanciado del template de plataforma), `k8s/` (base + overlay
dev que consume la Application `hello-aegis` de ArgoCD).
