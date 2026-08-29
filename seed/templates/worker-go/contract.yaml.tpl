# orgs/__ORG__.yaml — your organization's contract.
#
# IT WAS BORN FROM THE `worker-go` TEMPLATE AND THE TEMPLATE NO LONGER
# MATTERS. From this moment on this file is the ONLY truth
# (journeys/design.md §0.1): namespace, quota, ArgoCD Application,
# NetworkPolicy, CI job and credentials are all DERIVED from these
# lines. To change something you edit THIS file and re-run
# `aegis org apply orgs/__ORG__.yaml`.
version: 1
organizacion: __ORG__

# NO `dominio:`, and it is not an omission. The hostname exists to serve
# something, and nothing here is public: the contract only demands a
# domain when some service declares `publico`, and demanding one anyway
# would mean inventing a CNAME that nobody later knows why is there. Add
# it the day you add an `http` service beside this worker.
cuota: pequena                   # pequena | mediana | grande

servicios:
  # A WORKER: it processes, it does not listen. The type is what makes
  # that true instead of merely stated — the contract REJECTS `puerto`
  # and `publico` here, so nobody can declare a worker and then quietly
  # expose it. If it has to answer requests, the type is `http` and the
  # template is `service-node`, `service-python` or `base`.
  - nombre: app
    tipo: worker
    repo: __REPO__               # Application, deploy key and Jenkins
                                 # job all come from this one field
    # `usa:` is a network ALLOW-LIST: whatever is not named here, the
    # NetworkPolicy blocks — and a worker usually needs something, which
    # is the whole reason it exists. Declare it together with the
    # section that provides the thing, e.g. `usa: [postgres]` plus a
    # service of type postgres, or `usa: [bucket]` plus
    # `almacenamiento: {bucket: true}`.
