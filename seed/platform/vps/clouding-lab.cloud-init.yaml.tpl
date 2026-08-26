#cloud-config
# clouding-lab.cloud-init.yaml.tpl — the laboratory VPS is BORN this
# way, or it was not born at all: sshd on loopback only, zero public
# ports, cloudflared as the only way in (Access with OTP in front of
# it). The root cause in the record of 2026-08-22 was «there is a
# public port 22»; here that public port does not exist from the very
# first boot.
#
# Placeholders (owner: `aegis vps render` — check 3):
#   __SSH_PUBKEY_RSA__      ~/.ssh/aegis_vps_rsa.pub (the Clouding
#                           form only accepts the ssh-rsa prefix)
#   __SSH_PUBKEY_ED25519__  ~/.ssh/aegis_vps.pub
#   __CF_TUNNEL_TOKEN__     sensitive output of the vps-lab env; it
#                           comes in through render into /dev/shm and
#                           dies with shred. The final runcmd deletes
#                           the copy cloud-init leaves on disk.
#
# No per-IP banning tool: with sshd on loopback everything arrives from
# 127.0.0.1 and such a tool would end up banning the loopback. Access
# filters BEFORE the packet exists.
hostname: aegis-vps
users:
  - name: aegis
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL" # preflight gate (ansible without become-pass)
    lock_passwd: true
    ssh_authorized_keys:
      - "__SSH_PUBKEY_RSA__"
      - "__SSH_PUBKEY_ED25519__"

ssh_pwauth: false
disable_root: true

package_update: true
package_upgrade: true
packages: [ufw, unattended-upgrades, curl, ca-certificates, gnupg]

write_files:
  - path: /etc/ssh/sshd_config.d/01-hardening.conf
    content: |
      AuthenticationMethods publickey
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      MaxAuthTries 3
      LoginGraceTime 30
      ListenAddress 127.0.0.1
  - path: /etc/apt/sources.list.d/cloudflared.list
    content: |
      deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main
  - path: /etc/apt/apt.conf.d/52unattended-upgrades-local
    content: |
      Unattended-Upgrade::Automatic-Reboot "true";
      Unattended-Upgrade::Automatic-Reboot-Time "04:30";

# The order matters: first the keyring and cloudflared (while port 22
# has not yet received anybody: the machine is newly born and ufw has
# not come up yet), then the lockdown, and the tunnel last. If
# cloudflared does not install, the machine is left closed and
# unreachable by design — it gets destroyed and recreated, which is the
# whole point of being born from cloud-init.
runcmd:
  - curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  - apt-get update
  - apt-get install -y cloudflared
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow in on lo
  - ufw --force enable
  - systemctl restart ssh
  - cloudflared service install __CF_TUNNEL_TOKEN__
  - rm -f /var/lib/cloud/instance/user-data.txt
