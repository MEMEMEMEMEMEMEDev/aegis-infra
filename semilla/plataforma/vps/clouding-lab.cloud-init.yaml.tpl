#cloud-config
# clouding-lab.cloud-init.yaml.tpl — el VPS de laboratorio NACE así,
# o no nació: sshd solo en loopback, cero puertos públicos, cloudflared
# como único camino de entrada (Access con OTP delante). La causa raíz
# del archivo del 2026-08-22 era «hay un 22 público»; acá el 22 público
# no existe desde el primer boot.
#
# Placeholders (dueño: bin/aegis-vps render — check 3):
#   __SSH_PUBKEY_RSA__      ~/.ssh/aegis_vps_rsa.pub (el form de
#                           Clouding solo acepta prefijo ssh-rsa)
#   __SSH_PUBKEY_ED25519__  ~/.ssh/aegis_vps.pub
#   __CF_TUNNEL_TOKEN__     output sensitive del env vps-lab; entra
#                           por render a /dev/shm y muere con shred.
#                           El runcmd final borra la copia que
#                           cloud-init deja en disco.
#
# Sin herramienta de baneos por IP: con sshd en loopback todo llega
# desde 127.0.0.1 y un baneador banearía al loopback. Access filtra
# ANTES de que el paquete exista.
hostname: aegis-vps
users:
  - name: aegis
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL" # gate del preflight (ansible sin become-pass)
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

# El orden importa: primero el keyring y cloudflared (mientras el 22
# aún no recibió a nadie: la máquina recién nace y ufw todavía no
# levantó), después el cierre, al final el túnel. Si cloudflared no
# instala, la máquina queda cerrada e inaccesible por diseño — se
# destruye y se recrea, que es el punto de nacer por cloud-init.
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
