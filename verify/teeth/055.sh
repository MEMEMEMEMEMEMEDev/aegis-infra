# dientes del check 055 (todo seed con Service declara su exposición)
# CR-5: una app con Service y sin ruta nace invisible desde el borde.
# Nadie la ve fallar — el manifiesto está perfecto y el tráfico no
# llega. Es el defecto más caro de encontrar en producción y el más
# barato de encontrar acá.
red_1() {
    cat >> "$AEGIS_ROOT/seed/canary/k8s/base/deployment.yaml" <<'YAML'
---
apiVersion: v1
kind: Service
metadata:
  name: servicio-sin-ruta
spec:
  selector: {app: hello-aegis}
  ports: [{port: 8080}]
YAML
}
