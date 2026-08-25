# orgs/__ORG__.yaml — your organization's contract.
#
# IT WAS BORN FROM THE `base` TEMPLATE AND THE TEMPLATE NO LONGER
# MATTERS. From this moment on this file is the ONLY truth
# (journeys/design.md §0.1): everything the platform builds for you
# —namespace, quota, ArgoCD Application, NetworkPolicy, routing, CI job,
# edge hostname— is DERIVED from these lines. To change something you do
# not go back to the template: you edit THIS file and re-run
# `aegis org apply orgs/__ORG__.yaml`. You are one more artisan, exactly
# like whoever wrote it by hand.
#
# Read it whole before signing (committing): it is short on purpose.
version: 1                       # required; only version 1 exists today
organizacion: __ORG__            # immutable: changing it creates ANOTHER org
dominio: __DOMINIO__             # the public FQDN; the edge CNAME comes from here

# A PLAN WITH A NAME, never numbers. The numbers live in plans.yaml and
# are readjusted for every organization at once. `pequena` is the sane
# starting point: moving up a plan is editing ONE word.
cuota: pequena                   # pequena | mediana | grande

# NO `almacenamiento:` and NO `ai:` on purpose: the `base` template is
# the smallest one that compiles and deploys. The day you need them,
# they are ADDED here (see orgs/ejemplo.yaml, which uses both) and it is
# reapplied — there is no going back to any template.

servicios:
  # A single HTTP service. The platform expects it to listen on the
  # declared port and exposes it as the Service `__ORG__-app` on 8080;
  # the seeded skeleton already does both.
  - nombre: app
    tipo: http
    puerto: 8080
    publico: /                   # the root of the domain above
    repo: __REPO__               # from here come the Application, the
                                 # deploy key and the Jenkins job — one
                                 # field, three derivations
    # NO `usa:`. It is a network allow-list: whatever is not there, the
    # NetworkPolicy blocks. It is declared when needed
    # (usa: [postgres, bucket, ai]) together with its section above.
