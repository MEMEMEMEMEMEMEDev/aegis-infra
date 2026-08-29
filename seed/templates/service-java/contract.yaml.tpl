# orgs/__ORG__.yaml — your organization's contract.
#
# IT WAS BORN FROM THE `service-java` TEMPLATE AND THE TEMPLATE NO
# LONGER MATTERS. From this moment on this file is the ONLY truth
# (journeys/design.md §0.1): namespace, quota, ArgoCD Application,
# NetworkPolicy, routing, CI job and edge hostname are all DERIVED from
# these lines. To change something you edit THIS file and re-run
# `aegis org apply orgs/__ORG__.yaml`.
version: 1
organizacion: __ORG__
dominio: __DOMINIO__             # the public FQDN; the edge CNAME comes from here

# A JVM DOES NOT FIT IN THE SMALLEST PLAN'S HABITS. `pequena` is the
# right plan for this one service —its quota is the whole namespace's
# ceiling, not one pod's— but the DEPLOYMENT asks for more memory than
# the other templates do, and it must: a JVM given the 64Mi limit the Go
# template runs on does not start slowly, it is OOM-killed while the
# heap is being reserved, and the pod loops in CrashLoopBackOff with no
# message of its own. k8s/base/deployment.yaml carries 256Mi/512Mi and
# -XX:MaxRAMPercentage for that reason.
#
# PREPARED AND COMMENTED OUT: the contract does not yet accept a `tamano`
# field, and the validator refuses any key it does not know. The day it
# does, uncomment this line and the numbers stop living in the manifest:
#   tamano: mediano              # a JVM: see k8s/base/deployment.yaml
cuota: pequena                   # pequena | mediana | grande

servicios:
  # A JVM SERVER behind the edge. This is the type that CAN hold a
  # credential: it is the BFF a static front talks to when it needs the
  # database, the bucket or the AI.
  - nombre: app
    tipo: http
    puerto: 8080                 # part of the contract: without it the
                                 # platform does not know where to send
                                 # traffic, and the failure is silent
    publico: /                   # the root of the domain above
    repo: __REPO__               # Application, deploy key and Jenkins
                                 # job all come from this one field
    # `usa:` is a network ALLOW-LIST: whatever is not named here, the
    # NetworkPolicy blocks. Declare it together with the section that
    # provides the thing, e.g. `usa: [postgres]` plus a service of type
    # postgres, or `usa: [bucket]` plus `almacenamiento: {bucket: true}`.
