# La plataforma, para el equipo de desarrollo

Contexto de la infraestructura sobre la que corren tus aplicaciones. No cubre
todo — cubre lo que necesitás saber para desplegar sin chocar. Si algo acá te
frena y no sabés por qué, la respuesta casi siempre está en la sección
"Reglas que te van a rechazar".

---

## En una frase

Es una plataforma de Kubernetes self-hosted con GitOps. Vos escribís código;
la plataforma lo buildea, lo escanea, lo firma, lo despliega y lo expone a
internet — sin que toques infraestructura. Tu trabajo termina en `git push`.

No hay AWS/GCP/Azure detrás. Corre en hardware propio y está diseñada para ser
portable (el mismo stack corre en un VPS si algún día migramos). Para vos eso
es transparente.

---

## El trato: qué ponés vos, qué hace la plataforma

**Vos, en el repo de tu app:**
- Tu código.
- Un `Containerfile` (cómo se construye tu imagen).
- Un `Jenkinsfile` — **te lo damos como template**, casi no lo tocás.
- Los manifiestos K8s de tu app (Deployment, Service, etc.) — también con
  plantilla.

**La plataforma, sola, en cada push:**
1. **Buildea** tu imagen (sin privilegios — build aislado y seguro).
2. **Escanea** la imagen (Trivy). Vulnerabilidad grave con fix disponible =
   build roja. No se despliega código con CVEs conocidos.
3. **Firma** la imagen (cosign, por digest).
4. La **publica** en el registry interno.
5. **Despliega** vía GitOps (ArgoCD sincroniza el estado del repo al cluster).
6. La **expone** con TLS y la publica a internet — vos no tocás DNS, ni
   certificados, ni el túnel.

---

## El ciclo de vida de un push

```
git push
   │
   ▼
webhook ──▶ Jenkins (build de tu rama)
              │
              ├─ build de la imagen (sin privilegios)
              ├─ scan de vulnerabilidades  ── CRITICAL/HIGH con fix ⇒ FALLA
              ├─ push al registry interno
              └─ firma (cosign)
                    │
                    ▼
              ArgoCD detecta el cambio y sincroniza
                    │
                    ▼
              Kyverno admite SOLO imágenes firmadas por la plataforma
                    │
                    ▼
              tu app corriendo, con TLS, en tu-app.<dominio>
```

Todo esto es automático. Si el build queda rojo, el log del stage en Jenkins
te dice exactamente en qué paso (build / scan / push / firma) y por qué.

---

## Reglas que te van a rechazar (leé esto)

Estas son las barandas de la plataforma. No son negociables desde tu app — son
del cluster. Conocerlas te ahorra horas de "por qué no arranca mi pod".

1. **Solo corren imágenes firmadas por la plataforma.**
   No podés levantar `nginx:latest` de Docker Hub ni una imagen que armaste en
   tu máquina. Si no pasó por el pipeline (build + scan + firma), el cluster la
   **rechaza en admisión** citando la política de firma. Todo lo que corre,
   corre porque la plataforma lo construyó y lo firmó.

2. **El scan bloquea.**
   Un CVE CRITICAL o HIGH con parche disponible rompe el build. La solución es
   actualizar la dependencia, no saltear el scan. El scan es el que envejece
   solo y te avisa cuando tu base quedó vieja.

3. **Todo container necesita `resources.limits`.**
   Hay una cuota estricta por namespace. Un container sin `limits` (cpu y
   memoria) **no se crea** — ni los init containers ni los sidecars. La
   plantilla ya los trae; si agregás un container, agregale limits.

4. **La red arranca cerrada (default-deny).**
   Tu app, por defecto, no puede hablar con nada salvo lo explícitamente
   permitido (DNS y el borde que la expone). Si tu app necesita salir a otro
   servicio (una DB, una API externa), eso se habilita con una regla de red
   explícita — pedila, no asumas que hay salida abierta.

5. **Cada app vive en el namespace de su organización.**
   No ves ni tocás las apps de otras organizaciones. El aislamiento es por
   diseño: namespace, cuota y red propias por organización.

6. **Nada de pods privilegiados.**
   Tu app corre como un proceso normal, sin privilegios de nodo. Si tu imagen
   necesita root para algo raro, hablémoslo antes — casi siempre hay otra forma.

7. **Secrets nunca en claro en Git.**
   Contraseñas, tokens, claves: nunca commiteados en texto plano. Hay un
   mecanismo cifrado (SOPS+age) para eso. Si necesitás un secret para tu app,
   se gestiona por ahí, no en un `.env` commiteado.

---

## Lo que NO tenés que hacer (la plataforma se lo come)

- No administrás el registry de imágenes.
- No emitís ni renovás certificados TLS.
- No configurás DNS ni el túnel de salida a internet.
- No firmás imágenes a mano.
- No tocás la infraestructura de Kubernetes ni el IaC.
- No contratás ni pagás servicios cloud.

Si te encontrás haciendo alguna de estas, algo se salió del carril — avisá.

---

## El stack que te toca ver

| Pieza                 | Qué es para vos                                   |
|-----------------------|---------------------------------------------------|
| **GitHub**            | Donde vive tu código y desde donde disparás todo. |
| **Jenkins**           | Donde ves el build de tu rama (logs, estado).     |
| **Registry interno**  | Donde queda tu imagen (no lo tocás directo).      |
| **ArgoCD**            | Lo que sincroniza tu repo → cluster (GitOps).     |
| **Ingress + TLS**     | Lo que expone tu app con HTTPS (automático).      |
| **Cloudflare**        | El borde que la publica a internet (automático).  |

También hay **modelos de lenguaje locales** (Ollama y afines) disponibles como
servicio si tu app los necesita — sin depender de OpenAI ni de un proveedor
externo. Tu app los consume como una URL más (config por entorno); dónde corre
la inferencia es transparente para vos.

---

## Cómo empezar

1. Pedí tu repo y tu organización (namespace) en la plataforma.
2. Partí del template: `Containerfile` + `Jenkinsfile` (el canónico vive en
   `platform/docs/protocols/templates/Jenkinsfile.app`) + manifiestos de la app.
3. `git push`.
4. Mirá el build en Jenkins.
5. Tu app aparece en `tu-app.<dominio>`, con HTTPS, firmada y escaneada.

El primer deploy es la mejor forma de entender el ciclo completo. Si algo falla,
el log del stage en Jenkins es el primer lugar donde mirar; la causa está ahí.
