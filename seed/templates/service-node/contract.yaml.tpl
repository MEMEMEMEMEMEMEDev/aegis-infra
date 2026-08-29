# orgs/__ORG__.yaml — your organization's contract.
#
# IT WAS BORN FROM THE `service-node` TEMPLATE AND THE TEMPLATE NO
# LONGER MATTERS. From this moment on this file is the ONLY truth
# (journeys/design.md §0.1): namespace, quota, ArgoCD Application,
# NetworkPolicy, routing, CI job and edge hostname are all DERIVED from
# these lines. To change something you edit THIS file and re-run
# `aegis org apply orgs/__ORG__.yaml`.
version: 1
organizacion: __ORG__
dominio: __DOMINIO__             # the public FQDN; the edge CNAME comes from here
cuota: pequena                   # pequena | mediana | grande

servicios:
  # A JAVASCRIPT SERVER behind the edge. This is the type that CAN hold
  # a credential: it is the BFF a static front talks to when it needs
  # the database, the bucket or the AI.
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
