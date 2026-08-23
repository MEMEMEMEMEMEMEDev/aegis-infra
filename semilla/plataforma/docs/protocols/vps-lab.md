# Protocolo: el VPS de laboratorio (SSH por Access, cero puertos)

Estado: diseñado el 2026-08-22 (`Problema-vps-ssh-seguridad.md` del
operador), codificado el 2026-08-23. La máquina actual nació A MANO
por el panel de Clouding y se endureció a mano; este protocolo la
vuelve operable por túnel y deja escrito cómo nace la próxima.

## La forma

```
operador ──ssh──▶ cloudflared access ssh (ProxyCommand)
                        │  OTP al mail (Access, app «aegis · SSH lab»)
                        ▼
              túnel aegis-lab-admin (≠ aegis-tunnel: conviven)
                        ▼
              cloudflared (servicio en el VPS)
                        ▼
              sshd en 127.0.0.1:22  ← ListenAddress loopback
```

El 22 público NO existe: ufw niega todo lo entrante, sshd escucha
solo en loopback, y el único proceso que le habla es el cloudflared
local. Sin baneador de IPs: todo llega desde 127.0.0.1 y banearlo
sería banear al loopback — Access filtra antes.

Cliente (`~/.ssh/config` del operador):

```
Host aegis-vps
    HostName ssh-lab.<ROOT_DOMAIN>
    User aegis
    IdentityFile ~/.ssh/aegis_vps_rsa
    IdentitiesOnly yes
    ProxyCommand cloudflared access ssh --hostname %h
Host aegis-vps-ip            # break-glass; solo con la regla ufw temporal
    HostName <IP del VPS>
    User aegis
    IdentityFile ~/.ssh/aegis_vps_rsa
    IdentitiesOnly yes
```

El primer `ssh aegis-vps` abre el navegador para el OTP de Access y
cachea el JWT (~24 h). `cloudflared` instalado en la máquina
operadora es prerrequisito.

## Decisiones registradas

- **Excepción D11 (declarada)**: Clouding no tiene provider de tofu.
  El panel es el único acto manual y son DOS pegados: la llave
  pública y el user-data renderizado. Todo lo demás nace de código.
- **Quirk del form de Clouding**: solo acepta llaves con prefijo
  `ssh-rsa` — por eso existe `aegis_vps_rsa` (RSA-4096) además de la
  ed25519. Las dos van en el cloud-init.
- **`type = "self_hosted"` en la app de Access**, no `"ssh"`: el
  flujo `cloudflared access ssh` funciona idéntico y self_hosted es
  el tipo ya probado por las cinco apps del módulo hermano. Cero
  estrenos innecesarios.
- **El hostname vive en la zona raíz** (`ssh-lab.<ROOT_DOMAIN>`): no
  hay zona de lab. La etapa D (correr el init entero en el lab)
  necesitará dominio o zona propios — los CNAMEs aegis/argocd/jenkins
  de la fase 25 chocarían con el cluster casero. Prerrequisito de D,
  no de este protocolo.
- **`envs/vps-lab` NO lo consume `aegis destroy`**: es infra del
  operador, no de la instancia. El teardown de la plataforma lo deja
  vivo (el flujo de trabajo de v3 depende de él).

## Rescate y break-glass

- **Consola VNC de Clouding** (último recurso): el usuario no tiene
  password (`lock_passwd: true`). Desde el modo rescue: `passwd aegis`
  temporal, hacer lo necesario, `passwd -d aegis` al salir. Nunca
  dejar el password puesto.
- **Break-glass por IP** (si Cloudflare está caído y hay urgencia),
  desde una sesión viva o VNC:
  ```
  sudo ufw insert 1 allow from <IP-del-operador> to any port 22 proto tcp
  # + comentar ListenAddress 127.0.0.1 en 01-hardening.conf
  # + sudo sshd -t && sudo systemctl restart ssh
  ```
  Al terminar, REVERTIR los dos. Documentado, jamás default.
- **Caída de cloudflared/Cloudflare**: sin acceso hasta que vuelva
  (mismo riesgo aceptado que el cluster casero). `Restart=always` en
  la unit; el reboot de las 04:30 lo re-levanta.

## Rotación del token del túnel

```
./tofu-apply.sh -chdir=envs/vps-lab apply -replace=module.tunnel.random_id.tunnel_secret
platform/bin/aegis-vps entregar aegis-vps   # ya por Access, con sesión abierta
```

`entregar` reinicia cloudflared; la sesión SSH activa sobrevive
(conexión establecida). Línea correspondiente en
`rotation-checklist.md` del operador.

## Deriva conocida

La máquina actual (2026-08) tiene TODO lo que el cloud-init declara
pero no nació de él: se convergió a mano en la transición del
2026-08-23 (cloudflared instalado por apt, ufw sin 22, ListenAddress
añadido, baneador de IPs purgado, `52unattended-upgrades-local`
añadido). La prueba de que el cloud-init es fiel es la etapa D:
destruir y recrear — pendiente, la ejecuta el operador cuando toque.
Si al recrear cambia la IP: solo se actualiza `aegis-vps-ip` en el
config del operador y el dato de este archivo — el CNAME apunta al
túnel, no a la IP; ese es el punto. Host key nueva: `ssh-keygen -R
ssh-lab.<ROOT_DOMAIN>` y aceptar UNA vez; jamás
`StrictHostKeyChecking=no`.
