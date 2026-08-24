# vps/ — el VPS de laboratorio

**Qué es**: la definición reproducible de la máquina de laboratorio
del operador — un VPS chico que nace por cloud-init con sshd en
loopback, cero puertos públicos, y cloudflared + Cloudflare Access
como único camino de entrada. Es el banco de pruebas del init
(etapa D del plan de reconstrucción) y la máquina de desarrollo de
la semilla v3: los agentes entran por Access, iteran ahí, y la
instancia de casa no corre riesgo.

**Qué NO es**: no es el perfil `hetzner`, no es una instancia de
aegis, y no es infraestructura de la plataforma — `aegis destroy` no
lo toca. El init NO corre acá hasta que el lab tenga dominio o zona
propios (los CNAMEs de la fase 25 chocarían con el cluster casero;
ver `docs/protocols/vps-lab.md`).

Piezas:

- `clouding-lab.cloud-init.yaml.tpl` — el user-data con placeholders;
  lo renderiza `bin/aegis-vps render` a `/dev/shm` (el token del
  túnel jamás toca el disco).
- `../tofu/envs/vps-lab/` — túnel `aegis-lab-admin` + CNAME
  `ssh-lab` + app de Access. Se aplica con el wrapper, como todo.
- `../bin/aegis-vps` — render | entregar | shred.
- `../docs/protocols/vps-lab.md` — el protocolo entero: excepción
  D11, rescate, break-glass, rotación, deriva conocida.
