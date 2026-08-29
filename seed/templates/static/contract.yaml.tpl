# orgs/__ORG__.yaml — your organization's contract.
#
# IT WAS BORN FROM THE `static` TEMPLATE AND THE TEMPLATE NO LONGER
# MATTERS. From this moment on this file is the ONLY truth
# (journeys/design.md §0.1): namespace, quota, ArgoCD Application,
# NetworkPolicy, routing, CI job and edge hostname are all DERIVED from
# these lines. To change something you edit THIS file and re-run
# `aegis org apply orgs/__ORG__.yaml`.
version: 1
organizacion: __ORG__
dominio: __DOMINIO__             # the public FQDN; the edge CNAME comes from here
cuota: pequena                   # pequena | mediana | grande

servicios:
  # A STATIC FRONT. The type is not decoration: it is what forbids the
  # two mistakes this kind of service makes.
  - nombre: app
    tipo: estatico
    # NO `puerto:`, and the contract rejects one: the platform serves
    # static fronts on 8080, which is the only port the edge's
    # NetworkPolicy lets in. A front on any other port starts fine and
    # never receives a request — the silent failure.
    publico: /                   # the root of the domain above
    repo: __REPO__               # Application, deploy key and Jenkins
                                 # job all come from this one field
    # NO `usa:`, and the contract rejects one: a static front has
    # NOWHERE to keep a credential — whatever is handed to it travels
    # to the browser inside the bundle. Whatever needs the database,
    # the bucket or the AI goes behind an `http` service (the BFF
    # pattern; the `service-node` template is one).
