# dientes del check 005c (el seed del canario está completo)
# El renombre org-personal → org-canary quedó a medias el 2026-07-28 y
# la semilla dejó de arrancar; de ahí sale este check.
rojo_1() { rm -f "$AEGIS_ROOT/semilla/canario/k8s/base/deployment.yaml"; }
rojo_2() { rm -f "$AEGIS_ROOT/semilla/canario/go.mod"; }
