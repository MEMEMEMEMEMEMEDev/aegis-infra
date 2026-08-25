# Rotation checklist — THE SAME SOURCE as the init's ceremony

Settles C6. The principle (27 §2.3): a greenfield init EXECUTES this
whole list by construction (all material is born new); a one-off
rotation executes ONE item. One document, two uses.

## THIS IS NO LONGER RUN BY HAND (2026-08-12)

```
aegis rotate                  # the menu: pick one or all of them
```

Until today this document **was** the procedure: eleven items that a
person executed from memory. Now it is the *why*, and the *what* is done
by the tool. The difference that matters is not convenience:

> The last step of every item —checking that the real consumer went
> back to working— nobody did. You rotated, you saw that nothing blew
> up in the first thirty seconds, and you called it good. That is
> exactly the signal that does not tell "it passed" apart from "it was
> not evaluated", and rotation had it right at its centre.

`aegis-rotate` now does the whole cycle: an inventory with the AGE and
the BLAST RADIUS of every credential, confirmation, invalidation of the
store (archiving the previous `.enc` into `.previo/`, not deleting it),
a run of the phase that regenerates and synchronises the third party,
and **a verification that can fail** — a webhook ping that has to give
200 *and* a made-up signature that has to give 400; an `ssh -T` with the
key from the live Secret; a real login into Jenkins; the hostnames
compared against the previous snapshot.

Three things worth knowing before running it:

- **Network preflight.** If GitHub, Cloudflare, the cluster or the age
  key do not answer, the rotation **does not start**. On this machine
  —WiFi, MTU #69, k3s storms #73— starting with the network down was the
  shortest path to leaving credentials half synchronised.
- **The retries are transport-only.** A timeout is retried; a
  «Permission denied» is not. The remote answered, and it answered no:
  retrying that is doing the wrong thing three times.
- **If the verification fails, nothing rolls back on its own.** By then
  the third party already has the new credential, and restoring only the
  store would recreate the desynchronisation. The tool says in which of
  the four places —git, cluster, third party, store— each half ended up,
  and with which command it gets closed.

The old contract still works (`aegis rotate [--yes] <name>...`), and
`aegis rotate continue` resumes an interrupted batch.

**What the tool refuses to do**, and why that is right:

| | reason |
|---|---|
| `cosign_*` | it invalidates every signature ever issued; whatever is deployed has to be re-signed BEFORE the new public half enters the ClusterPolicy → item 2 |
| age key | it is the root → `rotate-age-key.md`, written on 2026-08-12 (until that day it was a dangling reference: the procedure for the one irreducible did not exist) |
| `registry_pass` | it lives in ten places; `aegis registry rotate` rotates it, discovering the targets and refusing to move if they do not match → item 4 |
| `dk_app_rw` | rotating it RE-CREATES the write deploy key that #49 withdrew; phase 15 has to be fixed first (#83) |
| commit and push | a person gives them, the same as in `aegis registry` |

And a new check, the **89** of `aegis verify`, keeps the table from
ageing: every credential the init generates has to have a recipe. A
missing one is a FAIL, not a detail.

---

Items (order = sensitivity). They are still here because they explain
the WHY of each recipe, and because the ones the tool does not cover are
done by reading this:

1. **age key** — phase 10 ceremony (3 safeguards + roundtrip).
   Rotating it also demands: the recipient in .sops.yaml + `sops
   updatekeys` over ALL the encrypted files + recreating the Secret
   argocd-sops-age (kubectl) + restarting repo-server.
2. **cosign keypair** — protocol issue-cosign-keypair §5
   (2 steps! it includes RE-SIGNING whatever is deployed).
3. **write key hello-aegis-repo** — ssh-keygen → GitHub WRITE deploy
   key (withdraw the old one) → re-encrypt the repository Secret →
   verify ArgoCD's clone AND the Image Updater's push (2 consumers).
4. **htpasswd + 4 regcreds** — protocol registry-credentials
   (atomic or nothing) + restart of the registry pod.
5. **GitHub App private key** — protocol issue-github-app §5
   (PKCS#8 + delete pod jenkins-0 + withdraw the old key).
6. **Jenkins webhook HMAC** — four steps, and the fourth is the one
   that gets forgotten:

   ```
   aegis secret rotate k8s/base/platform/jenkins-secrets/secret-github-webhook-hmac.enc.yaml
   git add ... && git commit && git push
   aegis sync jenkins-secrets
   aegis webhook apply
   ```

   No restart needed: `secretText` is re-read on its own.

   `aegis secret rotate` replaces the hand-run `openssl rand` this used
   to say. The difference that matters is not convenience: that Secret
   carries the label `jenkins.io/credentials-type: secretText`, which is
   what makes Jenkins TAKE it as a credential, and the tool PRESERVES
   the document's metadata when rotating. By hand, or with the tool
   before #53, the new material came out correctly encrypted and the
   credential invisible, without a single error.

   `aegis webhook apply` replaces "paste it into the App (UI)": the
   command derives the repos from Jenkins' jobs, reads the HMAC from the
   LIVE Secret —the one Jenkins really validates— and rewrites it on
   every one of them. Always rewriting is deliberate: GitHub never
   returns `config.secret`, so "the hook already exists" does NOT imply
   "it is synchronised", and a hook signing with the old HMAC gives a
   permanent 400 that does not say why.

   **AND THE INIT'S STORE**, which is the step missing from almost every
   rotation. `init/.state-secrets/hmac_jenkins.enc` keeps the material
   so that re-running the init is boring; if it is left with the OLD
   value, a future run RESTORES it and undoes the rotation in silence.
   Two ways out:

   - `aegis rotate --yes hmac_jenkins` invalidates it, and the init's
     next run generates a NEW one — which means the `aegis webhook
     apply` step has to be done again.
   - re-seeding it with the already-rotated value leaves the four places
     (git, cluster, GitHub, store) with the SAME material, and
     re-running the init changes nothing. That is what was done on
     2026-08-07 and it is the preferable one.

   Verification, and one that can fail: `gh api -X POST
   repos/<owner>/<repo>/hooks/<id>/pings` and read the delivery. It has
   to give **200**. Check as well that a made-up signature gives
   **400** — otherwise the 200 is saying nothing.
7. **ArgoCD webhook HMAC** — openssl rand → tokens.enc.yaml (the
   github-repos tofu apply side) + re-encrypt the github-webhook
   Secret + restart argocd-server + verify the webhook gives 200.
8. **TUNNEL_TOKEN** — rotate via API / recreate the tunnel →
   re-encrypt the Secret → roll out cloudflared.
9. **CF tokens (x2) and PAT** — re-issue them in the UI (issue-*
   protocols) → tokens.enc.yaml / KSOPS Secret → REVOKE the old ones.
10. **read deploy keys (ops-stack, hello-aegis RO)** — ssh-keygen →
    GitHub → re-encrypt → withdraw the old ones.
10b. **the ORGANIZATIONS' deploy keys** (`secret-<app>-repo`, one per
    repo declared in a contract). They were missing from this list
    until 2026-08-05: they had been created by hand, nobody produced
    them and nobody rotated them (#48, #49). They are a command now:

    ```
    aegis secret rotate k8s/base/platform/argocd-secrets/secret-<app>-repo.enc.yaml
    ```

    It prints the public half for you to register. **NO "Allow write
    access"**: ArgoCD only READS, and a deploy key with write access
    lets whoever holds the cluster write into the app's repo — the
    wrong direction. The two that existed were read-write because of
    the Image Updater, withdrawn in #37.

    **THE ORDER IS NOT OPTIONAL**, and it is the one followed on
    2026-08-05:

    1. rotate (the encrypted file already ends up with the new key)
    2. register the public half on GitHub as **read-only**
    3. commit + push + `aegis sync argocd-secrets`
    4. wait until the cluster's Secret has the new key
    5. **prove that it authenticates** — the App being Synced is not
       enough, because while the old one is still registered either of
       the two works:
       ```
       kubectl get secret <app>-repo -n argocd -o jsonpath='{.data.sshPrivateKey}' \
         | base64 -d > /dev/shm/k && chmod 600 /dev/shm/k
       ssh -i /dev/shm/k -o IdentitiesOnly=yes -T git@github.com   # "Hi ORG/REPO!"
       shred -u /dev/shm/k
       ```
    6. only then `gh repo deploy-key delete <id> -R <owner>/<repo>`
    7. a hard refresh of the App, and check Synced + Healthy

    The other way round —deleting before checking— leaves ArgoCD
    unable to read the repo.
11. **jenkins-admin** — new random → re-encrypt → check whether the
    chart re-reads existingSecret or demands a restart (NOT VERIFIED —
    write the result down here the first time it is done).

**Steps the init does NOT cover and rotation DOES** (27 §2.3):
withdrawing OLD credentials on the third parties' side (deploy
keys/App keys on GitHub, tokens on CF) and the re-signing of images
(item 2). An init that has run leaves no NEW residue, but rotating
over a live environment leaves OLD residue active if this part is
skipped.

Trigger for the batch rotation: first customer with an SLA / public
exposure / cut-over to Hetzner. Review 1 week beforehand.
