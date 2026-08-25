# vps/ — the laboratory VPS

**What it is**: the reproducible definition of the operator's
laboratory machine — a small VPS that is born from cloud-init with
sshd on loopback, zero public ports, and cloudflared + Cloudflare
Access as the only way in. It is the test bench for the init (stage D
of the rebuild plan) and the development machine for the v3 seed: the
agents come in through Access, iterate there, and the home instance is
never at risk.

**What it is NOT**: it is not the `hetzner` profile, it is not an
aegis instance, and it is not platform infrastructure — `aegis
destroy` does not touch it. The init does NOT run here until the lab
has a domain or a zone of its own (the phase 25 CNAMEs would collide
with the home cluster; see `docs/protocols/vps-lab.md`).

Pieces:

- `clouding-lab.cloud-init.yaml.tpl` — the user-data with
  placeholders; `bin/aegis-vps render` renders it into `/dev/shm` (the
  tunnel token never touches disk).
- `../tofu/envs/vps-lab/` — the `aegis-lab-admin` tunnel + the
  `ssh-lab` CNAME + the Access app. Applied with the wrapper, like
  everything else.
- `../bin/aegis-vps` — render | entregar | shred.
- `../docs/protocols/vps-lab.md` — the whole protocol: the D11
  exception, rescue, break-glass, rotation, known drift.
