# Protocol: the lab VPS (SSH through Access, zero open ports)

Status: designed on 2026-08-22 (the operator's
`Problema-vps-ssh-seguridad.md`), coded on 2026-08-23. The current
machine was born BY HAND through the Clouding panel and was hardened
by hand; this protocol makes it operable over the tunnel and writes
down how the next one gets born.

## The shape

```
operator ──ssh──▶ cloudflared access ssh (ProxyCommand)
                        │  OTP to email (Access, app «aegis · SSH lab»)
                        ▼
              aegis-lab-admin tunnel (≠ aegis-tunnel: they coexist)
                        ▼
              cloudflared (a service on the VPS)
                        ▼
              sshd on 127.0.0.1:22  ← ListenAddress loopback
```

A public port 22 does NOT exist: ufw denies everything inbound, sshd
listens only on loopback, and the only process that talks to it is
the local cloudflared. No IP-ban daemon: everything arrives from
127.0.0.1 and banning that would be banning the loopback — Access
filters first.

Client (the operator's `~/.ssh/config`):

```
Host aegis-vps
    HostName ssh-lab.<ROOT_DOMAIN>
    User aegis
    IdentityFile ~/.ssh/aegis_vps_rsa
    IdentitiesOnly yes
    ProxyCommand cloudflared access ssh --hostname %h
Host aegis-vps-ip            # break-glass; only with the temporary ufw rule
    HostName <VPS IP>
    User aegis
    IdentityFile ~/.ssh/aegis_vps_rsa
    IdentitiesOnly yes
```

The first `ssh aegis-vps` opens the browser for the Access OTP and
caches the JWT (~24 h). `cloudflared` installed on the operator's
machine is a prerequisite.

## Decisions on record

- **D11 exception (declared)**: Clouding has no tofu provider. The
  panel is the only manual act, and it is TWO pastes back to back:
  the public key and the rendered user-data. Everything else is born
  out of code.
- **Quirk of Clouding's form**: it only accepts keys with the
  `ssh-rsa` prefix — that is why `aegis_vps_rsa` (RSA-4096) exists
  alongside the ed25519 one. Both go into the cloud-init.
- **`type = "self_hosted"` on the Access app**, not `"ssh"`: the
  `cloudflared access ssh` flow works identically and self_hosted is
  the type already proven by the five apps of the sibling module.
  Zero unnecessary premieres.
- **The hostname lives in the root zone** (`ssh-lab.<ROOT_DOMAIN>`):
  there is no lab zone. Stage D (running the whole init in the lab)
  will need a domain or a zone of its own — phase 25's
  aegis/argocd/jenkins CNAMEs would collide with the home cluster. A
  prerequisite of D, not of this protocol.
- **`envs/vps-lab` is NOT consumed by `aegis destroy`**: it is the
  operator's infrastructure, not the instance's. The platform's
  teardown leaves it alive (v3's workflow depends on it).

## Rescue and break-glass

- **Clouding's VNC console** (last resort): the user has no password
  (`lock_passwd: true`). From rescue mode: a temporary
  `passwd aegis`, do what is needed, `passwd -d aegis` on the way
  out. Never leave the password in place.
- **Break-glass by IP** (if Cloudflare is down and it is urgent),
  from a live session or from VNC:
  ```
  sudo ufw insert 1 allow from <operator-IP> to any port 22 proto tcp
  # + comment out ListenAddress 127.0.0.1 in 01-hardening.conf
  # + sudo sshd -t && sudo systemctl restart ssh
  ```
  When done, REVERT both. Documented, never the default.
- **cloudflared/Cloudflare going down**: no access until it comes
  back (the same accepted risk as the home cluster). `Restart=always`
  on the unit; the 04:30 reboot brings it back up.

## Rotating the tunnel token

```
./tofu-apply.sh -chdir=envs/vps-lab apply -replace=module.tunnel.random_id.tunnel_secret
aegis vps entregar aegis-vps   # already through Access, with a session open
```

`entregar` restarts cloudflared; the active SSH session survives (the
connection is already established). The corresponding line is in the
operator's `rotation-checklist.md`.

## Known drift

The current machine (2026-08) has EVERYTHING the cloud-init declares
but was not born from it: it was converged by hand during the
2026-08-23 transition (cloudflared installed through apt, ufw without
22, ListenAddress added, the IP-ban daemon purged,
`52unattended-upgrades-local` added). The proof that the cloud-init
is faithful is stage D: destroy and recreate — pending, and the
operator runs it when the time comes. If the IP changes on
recreating: the only things updated are `aegis-vps-ip` in the
operator's config and the figure in this file — the CNAME points at
the tunnel, not at the IP; that is the whole point. A new host key:
`ssh-keygen -R ssh-lab.<ROOT_DOMAIN>` and accept ONCE; never
`StrictHostKeyChecking=no`.
