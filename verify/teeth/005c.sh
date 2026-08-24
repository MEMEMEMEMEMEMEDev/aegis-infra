# dientes del check 005c (el seed del canario está completo)
# El renombre org-personal → org-canary quedó a medias el 2026-07-28 y
# la semilla dejó de arrancar; de ahí sale este check.
red_1() { rm -f "$AEGIS_ROOT/seed/canary/k8s/base/deployment.yaml"; }
red_2() { rm -f "$AEGIS_ROOT/seed/canary/go.mod"; }
