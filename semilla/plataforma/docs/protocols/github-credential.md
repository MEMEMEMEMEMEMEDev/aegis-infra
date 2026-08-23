# github-credential — la credencial GitHub de aegis v2 (D11)

## Qué es

La credencial que Jenkins usa para escanear el repo de la app
(github-branch-source) es el TOKEN DE LA SESIÓN gh del operador
(`gh auth token`), guardado como credencial username+password
(owner + token) en el Secret KSOPS `github-token` (jenkins-system).
La toma la fase 15 del init, automáticamente.

## Por qué NO es una GitHub App (decisión D11, con honestidad)

La GitHub App de v1 (aegis-ci) requería: crearla en el navegador
(el manifest flow de GitHub EXIGE un redirect web — no existe
creación headless), descargar el .pem, moverlo a mano, convertirlo
PKCS#1→PKCS#8, y anotar App ID/Installation ID. Acuñar PATs por API
tampoco existe (ni clásicos ni fine-grained). Conclusión honesta:
no hay forma de automatizar la App al 100% — así que se REEMPLAZÓ
por lo que sí se automatiza por completo.

## Modelo de seguridad (leer antes de objetar)

- El token gh tiene los scopes de la sesión del operador (amplios).
  Vive: (a) cifrado con age en el repo (.enc.yaml), (b) como Secret
  en jenkins-system. Es MÁS amplio que la App — trade-off aceptado
  explícitamente para dogfooding.
- Rotación: `gh auth refresh` (o re-login) + re-correr la fase 15
  con `--from 15` (el make_enc_secret regenera el .enc.yaml) +
  sync de jenkins-secrets. Un solo lugar.
- Revocación de emergencia: cerrar la sesión gh en github.com/
  settings/applications revoca el token en todos lados.

## Upgrade path a producción (cuando haya SLA)

Volver a una GitHub App (mejores rate limits, permisos acotados,
checks API) ES el camino para producción — asumiendo el paso manual
de navegador UNA vez, fuera del init: crear la App a mano, guardar
la key como Secret `github-app-aegis-ci` (gitHubApp), y cambiar
`scanCredentialsId('github-token')` → App en el values. El diseño
v1 completo está en git (histórico de este archivo y de la fase 15
pre-D11).
