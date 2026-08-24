# teeth for check 055 (every seed with a Service declares its exposure)
# CR-5: an app with a Service and no route is born invisible from the
# edge. Nobody sees it fail — the manifest is perfect and the traffic
# does not arrive. It is the most expensive defect to find in production
# and the cheapest to find here.
red_1() {
    cat >> "$AEGIS_ROOT/seed/canary/k8s/base/deployment.yaml" <<'YAML'
---
apiVersion: v1
kind: Service
metadata:
  name: service-without-route
spec:
  selector: {app: hello-aegis}
  ports: [{port: 8080}]
YAML
}
