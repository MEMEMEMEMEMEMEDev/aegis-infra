"""aegis-org — el contrato de una organización, materializado.

Implementa docs/protocols/organization.md. Lee un contrato de
`orgs/<nombre>.yaml` y escribe los manifiestos en
`k8s/organizations/org-<nombre>/`.

NO HABLA CON EL CLUSTER. No importa kubernetes, no invoca kubectl, no
lee un kubeconfig. Escribe archivos en el repo y termina; quien despliega
es ArgoCD después de que un humano revise el diff y commitee. Eso no es
purismo: es lo que hace que correr esto sea seguro en cualquier momento,
porque lo peor que puede pasar es un diff feo que nadie commitea.

Está en python3 y no en bash por una razón concreta: hay que validar un
esquema y rendear determinísticamente. En bash eso termina siendo sed
sobre YAML, que es la Enfermedad A del repo ("YAML como string").
python3 y no yq por la regla C7.
"""
import argparse
import difflib
import hashlib
import json
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit("falta pyyaml (python3-yaml)")

from . import cli, markers, paths

# ── Clase E: ningún nombre de comando escrito a mano ─────────────────
# En v2 este archivo tenía 15 (y el árbol entero ~155). Cada uno es una
# promesa que envejece: el día que el comando se llama distinto, los
# mensajes —y peor, los COMENTARIOS de los manifiestos generados, que
# el operador lee meses después— siguen diciendo el nombre viejo. No se
# traducen uno por uno: se derivan de uno solo, que sale de argv[0].
CMD_ORG        = cli.cmd("org")
CMD_ORG_APPLY  = cli.cmd("org apply")
CMD_SECRET     = cli.cmd("secret create")
CMD_CHECK      = cli.cmd("check")
CMD_SYNC_ROOT  = cli.cmd("sync root")

# RAIZ es la INSTANCIA, no el producto.
#
# Hasta el 2026-08-23 esta línea decía `dirname(dirname(__file__))`, y
# estaba bien mientras el comando vivía en <instancia>/platform/bin/:
# dos niveles arriba daba <instancia>/platform. Al mudar el código al
# producto (02 §1) la MISMA línea siguió compilando y pasó a apuntar a
# <producto>, buscando orgs/ y k8s/ donde no están. Nada lo habría
# avisado: es la «dependencia invisible a un grep» de C1/C2 del
# registro, con fecha. Ahora lo decide un solo resolvedor, el mismo
# que usa bash (lib/paths.sh).
RAIZ = str(paths.platform_dir())
DIR_ORGS = os.path.join(RAIZ, "orgs")
DIR_K8S = os.path.join(RAIZ, "k8s", "organizations")
PLANES = os.path.join(RAIZ, "plans.yaml")
EDGE = os.path.join(RAIZ, "edge.yaml")
SERVICIOS = os.path.join(RAIZ, "services.yaml")
RUTEO = os.path.join(RAIZ, "ai", "routes.yaml")
TAREAS_AI = os.path.join(RAIZ, "ai", "tasks.yaml")
REGISTRO_AI = os.path.join(RAIZ, "k8s", "base", "ai-system", "registro.yaml")
RUTEO_K8S = os.path.join(RAIZ, "k8s", "base", "ai-system", "routes.yaml")
DIR_AI = os.path.join(RAIZ, "k8s", "base", "ai-system")
TENANTS_K8S = os.path.join(RAIZ, "k8s", "argocd-apps", "tenants.yaml")
APROVISIONAR_JS = os.path.join(RAIZ, "ai", "aprovisionar-bucket.mjs")
DIR_GARAGE = os.path.join(RAIZ, "k8s", "base", "garage-system")
APROVISIONAR_K8S = os.path.join(DIR_GARAGE, "aprovisionar.yaml")
GARAGE_KUSTOMIZATION = os.path.join(DIR_GARAGE, "kustomization.yaml")
GARAGE_SECRETGEN = os.path.join(DIR_GARAGE, "secret-generator.yaml")
APPPROJECTS_K8S = os.path.join(RAIZ, "k8s", "bootstrap", "appprojects-tenants.yaml")
ARGOCD_SECRETGEN = os.path.join(RAIZ, "k8s", "base", "platform", "argocd-secrets",
                                "secret-generator.yaml")
def _repo_ops():
    """La URL del repo de plataforma, leída del conf de la instancia.

    En v2 esto era un literal con placeholders —
    `git@github.com:__GH_OWNER__/__PLATFORM_REPO__.git`— porque
    aegis-org viajaba DENTRO de la semilla y el init lo renderizaba
    junto con los manifiestos: el programa era también artefacto. Con
    el código en el producto eso deja de tener sentido (el producto no
    se renderiza) y además sería justo lo que el check 86 prohíbe: una
    instancia horneada en el código.
    """
    c = paths.leer_conf()
    dueno, repo = c.get("GH_OWNER"), c.get("PLATFORM_REPO")
    if not dueno or not repo:
        raise SystemExit(
            f"no puedo derivar el repo de plataforma: falta GH_OWNER/PLATFORM_REPO "
            f"en {paths.conf()} (¿corriste el wizard?)")
    return f"git@github.com:{dueno}/{repo}.git"
MAIN_TF = os.path.join(RAIZ, "tofu", "envs", "cloudflare-tunnel", "main.tf")
JENKINS_VALUES = os.path.join(RAIZ, "k8s", "base", "platform", "jenkins", "values.yaml")
VMAGENT_VALUES = os.path.join(RAIZ, "k8s", "base", "observability", "vmagent", "values.yaml")
JENKINSFILE_TPL = os.path.join(RAIZ, "docs", "protocols", "templates", "Jenkinsfile.app")
DIR_STAGING = os.path.join(RAIZ, ".aegis-app")

VERSION_CONTRATO = 1
NOMBRE_VALIDO = re.compile(r"^[a-z][a-z0-9-]{2,29}$")
TIPOS = {"estatico", "http", "postgres", "worker"}
# Los que salen de una imagen que alguien COMPILA Y FIRMA. El resto los
# provee la plataforma (postgres sale de services.yaml), y esa
# diferencia es la que decide si el contrato necesita un `repo`.
TIPOS_CON_IMAGEN = {"estatico", "http", "worker"}
# `internet` entró el 2026-08-21 con org-shop: su API habla con Webpay
# (Transbank) y era la PRIMERA app de tenant que necesita salir al
# mundo — el vocabulario no tenía cómo decirlo y el síntoma fue un
# ECONNREFUSED del CNI a mitad de una compra. No exige bloque a nivel
# de organización (a diferencia de bucket/ai/postgres): es una
# capacidad del servicio, no un recurso que la plataforma provea.
USOS = {"ai", "bucket", "postgres", "internet"}

# Puerto en el que la plataforma ESPERA a cada tipo que no lo declara.
# No es un default cómodo: es parte del contrato. Un front que escuche
# en otro lado arranca bien y no recibe tráfico nunca — un fallo
# silencioso, que es la peor clase.
PUERTO_ESTATICO = 8080


def _coherencia_de_tipo(n, tipo, s):
    """Un `tipo` que no restringe nada no es un tipo, es una etiqueta.

    Hasta acá el campo se validaba contra una lista y después no lo
    consumía nadie: se podía declarar un `worker` público en el puerto
    443 y el generador decía que sí. Estas reglas son las que hacen que
    el tipo signifique algo.
    """
    tiene = lambda k: s.get(k) is not None

    if tipo == "estatico":
        # SIN `usa`, y esta es la única regla de acá que es de
        # SEGURIDAD y no de coherencia: un front estático no tiene lado
        # servidor donde guardar una credencial. Todo lo que se le
        # entregue queda publicado en el bundle que baja el navegador.
        # Lo que necesite hablar con la AI o con el bucket va detrás de
        # un `http`, que es exactamente el rol del BFF.
        if s.get("usa"):
            raise Invalido(
                f"servicio {n!r} es estatico y declara usa: {s['usa']}.\n"
                f"  Un front estático NO tiene dónde guardar una credencial: lo que\n"
                f"  se le entregue viaja al navegador. Lo que necesite AI o bucket\n"
                f"  va detrás de un servicio `http` (el patrón BFF).")
        if tiene("puerto"):
            raise Invalido(
                f"servicio {n!r} es estatico y declara puerto {s['puerto']}.\n"
                f"  Los estáticos los sirve la plataforma en el {PUERTO_ESTATICO}, que es el\n"
                f"  único que la NetworkPolicy del borde deja entrar.")
        if not tiene("publico"):
            raise Invalido(
                f"servicio {n!r} es estatico y no declara `publico`.\n"
                f"  Un front que nadie puede visitar no es un front.")

    elif tipo == "http":
        if not tiene("puerto"):
            raise Invalido(
                f"servicio {n!r} es http y no declara `puerto`.\n"
                f"  El puerto es parte del contrato: sin él la plataforma no sabe\n"
                f"  a dónde mandar el tráfico y el fallo sería silencioso.")

    elif tipo == "worker":
        # Un worker no escucha. Si tuviera puerto o ruta pública sería
        # otra cosa y habría que llamarla por su nombre.
        for campo in ("puerto", "publico"):
            if tiene(campo):
                raise Invalido(
                    f"servicio {n!r} es worker y declara `{campo}`.\n"
                    f"  Un worker no escucha: procesa. Si necesita atender pedidos,\n"
                    f"  el tipo es `http`.")

    elif tipo == "postgres":
        # Lo provee la PLATAFORMA: imagen firmada, disco, credencial y
        # políticas salen de services.yaml, no de un repo del tenant.
        if tiene("repo"):
            raise Invalido(
                f"servicio {n!r} es postgres y declara `repo`.\n"
                f"  Las bases las provee la plataforma (services.yaml): imagen\n"
                f"  firmada, disco y credencial. Un repo acá significa que se quiso\n"
                f"  otra cosa.")
        for campo in ("puerto", "publico"):
            if tiene(campo):
                raise Invalido(
                    f"servicio {n!r} es postgres y declara `{campo}`.\n"
                    f"  El puerto lo fija la plataforma y una base NUNCA se publica:\n"
                    f"  se alcanza desde dentro del namespace y de ningún otro lado.")
        if s.get("usa"):
            raise Invalido(
                f"servicio {n!r} es postgres y declara usa: {s['usa']}.\n"
                f"  Una base no consume servicios: los presta.")


def capacidades():
    """Las capacidades que se pueden pedir son las que ai/routes.yaml sabe
    servir HOY, no una lista escrita acá.

    La versión anterior tenía el conjunto a mano e incluía `embeddings` y
    `transcripcion`, que todavía no tienen engine. Un contrato que las
    pidiera pasaba esta validación y después impedía que el gateway
    ARRANCARA — el generador daba el visto bueno a algo que la
    plataforma no puede cumplir, que es la forma más cara de equivocarse:
    el error aparece lejos de la causa."""
    r = yaml.safe_load(open(RUTEO, encoding="utf-8")) or {}
    return set((r.get("capacidades") or {}).keys())

rojo = "\033[31m"; verde = "\033[32m"; ama = "\033[33m"; gris = "\033[90m"; fin = "\033[0m"
if not sys.stdout.isatty():
    rojo = verde = ama = gris = fin = ""


class Invalido(Exception):
    """El contrato no sirve. Se aborta ANTES de escribir nada (regla I5)."""


# ──────────────────────────────────────────────────────────────────
# Validación
#
# Los campos desconocidos son ERROR, no se ignoran. Un typo en
# `almacenamineto:` tiene que fallar ruidoso; ignorarlo desactivaría el
# bucket sin que nadie se entere, que es la peor forma de fallar.
# ──────────────────────────────────────────────────────────────────

def _solo(d, permitidos, donde):
    sobra = set(d) - permitidos
    if sobra:
        raise Invalido(f"{donde}: campo(s) desconocido(s): {', '.join(sorted(sobra))}")


def _exige(d, campo, donde):
    if campo not in d:
        raise Invalido(f"{donde}: falta el campo obligatorio '{campo}'")
    return d[campo]


def validar(c, planes):
    if not isinstance(c, dict):
        raise Invalido("el contrato no es un mapa YAML")
    _solo(c, {"version", "organizacion", "dominio", "cuota", "repo",
              "almacenamiento", "ai", "servicios"}, "contrato")

    # La versión es OBLIGATORIA y se rechaza lo desconocido. Un contrato
    # sin versión NO es "v1 por defecto": es un error. Asumir la versión
    # es cómo un contrato viejo termina renderizado con reglas nuevas.
    v = _exige(c, "version", "contrato")
    if v != VERSION_CONTRATO:
        raise Invalido(f"version {v!r} desconocida (esta herramienta habla v{VERSION_CONTRATO})")

    nombre = _exige(c, "organizacion", "contrato")
    if not isinstance(nombre, str) or not NOMBRE_VALIDO.match(nombre):
        raise Invalido(f"organizacion {nombre!r}: debe ser [a-z][a-z0-9-]{{2,29}}")

    # `dominio` NO es obligatorio, y el chequeo de verdad está más abajo:
    # hace falta si —y solo si— algún servicio es `publico`. Un hostname
    # existe para servir algo; una organización que solo tiene una base y
    # un bucket no tiene a quién exponer. Exigirlo igual obligaba a
    # inventar un nombre, y un CNAME inventado es un CNAME que después
    # nadie sabe por qué está.

    cuota = _exige(c, "cuota", "contrato")
    if cuota not in planes["cuota"]:
        raise Invalido(f"cuota {cuota!r} no existe. Hay: {', '.join(sorted(planes['cuota']))}\n"
                       f"  Si hace falta una nueva, se AGREGA UN PLAN en plans.yaml.\n"
                       f"  No se ponen números en el contrato (§3 del protocolo).")

    alm = c.get("almacenamiento") or {}
    _solo(alm, {"bucket"}, "almacenamiento")
    # El VALOR, no solo la clave. Todo lo que no sea booleano se lee como
    # falso más adelante (`alm.get("bucket")` por verdad), así que
    # `bucket: {}` valida bien y significa "sin bucket" EN SILENCIO: ni
    # Job, ni credencial, ni error. Me pasó a mí escribiendo la prueba
    # del generador el 2026-08-04.
    if "bucket" in alm and not isinstance(alm["bucket"], bool):
        raise Invalido(
            f"almacenamiento.bucket: se esperaba true o false, no {alm['bucket']!r}\n"
            f"  El bucket no se configura desde el contrato: su nombre, su\n"
            f"  endpoint y su clave los decide la plataforma. Acá solo se\n"
            f"  dice si la organización quiere uno.")

    ai = c.get("ai")
    if ai is not None:
        _solo(ai, {"plan", "tareas"}, "ai")
        plan = _exige(ai, "plan", "ai")
        if plan not in planes["ai"]:
            raise Invalido(f"ai.plan {plan!r} no existe. Hay: {', '.join(sorted(planes['ai']))}")
        for t in ai.get("tareas") or []:
            _solo(t, {"nombre", "capacidad", "prompt"}, "ai.tareas[]")
            _exige(t, "nombre", "ai.tareas[]")
            cap = _exige(t, "capacidad", "ai.tareas[]")
            disponibles = capacidades()
            if cap not in disponibles:
                raise Invalido(
                    f"capacidad {cap!r} no se sirve hoy. Hay: {', '.join(sorted(disponibles))}\n"
                    f"  Una organización nombra CAPACIDADES, nunca modelos ni\n"
                    f"  proveedores (§5 del protocolo). Si ve un nombre de modelo\n"
                    f"  acá, el contrato está mal escrito.\n"
                    f"  Si la capacidad es la correcta y falta el engine, se agrega\n"
                    f"  en ai/routes.yaml DESPUÉS de implementarlo — no antes.")

    servicios = _exige(c, "servicios", "contrato")
    if not servicios:
        raise Invalido("contrato: 'servicios' vacío — una organización sin servicios no es nada")
    vistos = set()
    hay_postgres = any(s.get("tipo") == "postgres" for s in servicios)
    for s in servicios:
        # SIN `version`. Estaba permitido y no lo consumía nadie: un
        # contrato podía declarar `version: "17"` en su base y el
        # generador la ignoraba, dejando a quien lo escribió creyendo
        # que había fijado algo. La versión de un servicio provisto por
        # la plataforma la decide services.yaml, y para eso está.
        _solo(s, {"nombre", "tipo", "repo", "puerto", "publico", "usa"}, "servicios[]")
        n = _exige(s, "nombre", "servicios[]")
        if n in vistos:
            raise Invalido(f"servicio {n!r} declarado dos veces")
        vistos.add(n)
        tipo = _exige(s, "tipo", "servicios[]")
        if tipo not in TIPOS:
            raise Invalido(f"servicio {n!r}: tipo {tipo!r} desconocido. Hay: {', '.join(sorted(TIPOS))}")
        _coherencia_de_tipo(n, tipo, s)
        for u in s.get("usa") or []:
            if u not in USOS:
                raise Invalido(f"servicio {n!r}: usa {u!r} desconocido ({' | '.join(sorted(USOS))})")
            if u == "bucket" and not alm.get("bucket"):
                raise Invalido(f"servicio {n!r} declara usa:[bucket] pero la organización "
                               f"no pidió almacenamiento.bucket")
            if u == "ai" and ai is None:
                raise Invalido(f"servicio {n!r} declara usa:[ai] pero la organización "
                               f"no tiene sección ai")
            if u == "postgres" and not hay_postgres:
                raise Invalido(f"servicio {n!r} declara usa:[postgres] pero la organización "
                               f"no declaró ningún servicio de tipo postgres")

    # ── repo: solo si algún servicio SE CONSTRUYE ─────────────────
    #
    # Decía "sin repo no hay nada que desplegar", y era cierto cuando
    # todo servicio salía de un build. Desde #41 dejó de serlo: un
    # `postgres` lo provee la plataforma desde services.yaml, y un
    # bucket lo aprovisiona un Job. Un contrato de pura infraestructura
    # se rechazaba con una razón que ya no era verdad.
    #
    # Y bloqueaba el orden natural, que es al revés del que pedía:
    # primero la base y el bucket, después la app que los usa. Obligaba
    # a inventar un repo vacío para poder empezar.
    de_build = [s for s in servicios if s["tipo"] in TIPOS_CON_IMAGEN]
    if de_build and not c.get("repo") and not any(s.get("repo") for s in de_build):
        cuales = ", ".join(f"{s['nombre']} ({s['tipo']})" for s in de_build)
        raise Invalido(
            f"hace falta 'repo' —a nivel organización o en el servicio— porque "
            f"estos servicios se CONSTRUYEN: {cuales}.\n"
            f"  Los tipos {', '.join(sorted(TIPOS_CON_IMAGEN))} salen de una imagen que\n"
            f"  alguien tiene que compilar y firmar. `postgres` no: lo provee la\n"
            f"  plataforma desde services.yaml, y para eso no hace falta repo.")

    # ── dominio: solo si algo es PÚBLICO ──────────────────────────
    publicos = [s["nombre"] for s in servicios if s.get("publico")]
    if publicos and not c.get("dominio"):
        raise Invalido(
            f"hace falta 'dominio': {', '.join(publicos)} declara(n) `publico` y sin\n"
            f"  hostname nadie puede llegar. El CNAME del borde se DERIVA de este\n"
            f"  campo (§2 del protocolo del borde); sin él el servicio arranca\n"
            f"  bien y no recibe tráfico nunca, que es la peor clase de fallo.")
    if c.get("dominio") and not publicos:
        raise Invalido(
            f"el contrato declara dominio {c['dominio']!r} pero ningún servicio es\n"
            f"  `publico`. Ese CNAME apuntaría a un sitio que no existe. Si la app\n"
            f"  todavía no está, el dominio se agrega junto con ella.")

    # ── dos servicios no pueden reclamar la misma ruta ────────────
    # Desde que la IngressRoute se DERIVA de estos campos (#54), un
    # `publico` repetido no es un descuido de documentación: son dos
    # reglas de traefik con el mismo match. Traefik elige una y la otra
    # no recibe tráfico jamás, sin error en ningún lado.
    vistas = {}
    for s in servicios:
        if not s.get("publico"):
            continue
        if (duenio := vistas.get(s["publico"])) is not None:
            raise Invalido(
                f"{duenio!r} y {s['nombre']!r} declaran el mismo `publico: "
                f"{s['publico']}'.\n"
                f"  De ahí sale UNA regla de ruteo por servicio: con la misma ruta,\n"
                f"  traefik se queda con una y la otra no recibe tráfico nunca. No\n"
                f"  hay error que lo delate — la app arranca sana y queda muda.")
        vistas[s["publico"]] = s["nombre"]
    return c


# ──────────────────────────────────────────────────────────────────
# Render
#
# Plantillas de texto y no yaml.dump() a propósito: los comentarios que
# explican POR QUÉ cada cosa es como es valen tanto como el YAML, y
# yaml.dump los borra. El costo es escribir las plantillas a mano; el
# beneficio es que el archivo generado se puede LEER.
# ──────────────────────────────────────────────────────────────────

# La cabecera de lo derivado y el resto de los centinelas viven en
# lib/aegis/markers.py: el que los ESCRIBE y el que los RECONOCE tienen
# que usar la misma cadena, y en v2 estaba copiada ocho veces (clase B
# del registro, regla 5.6).
CABECERA = markers.CABECERA


def _hash(texto):
    """Huella del contrato Y DEL GENERADOR que lo renderiza.

    Incluir el generador no es exceso de celo: sin eso, cambiar una
    plantilla acá deja el hash intacto mientras la salida cambia, y el
    guard I3 lo lee como "alguien editó el archivo a mano" y se niega a
    escribir. Pasó el 2026-08-03 al sacar el ignoreDifferences: el guard
    bloqueó su propio cambio.

    Con el generador adentro, tocar una plantilla cambia el hash de
    TODOS los archivos generados —que es la verdad: son distintos— y la
    reescritura procede. Lo que I3 sigue cazando es lo que tiene que
    cazar: mismo contrato y mismo generador, contenido distinto = mano
    humana.
    """
    mio = open(os.path.abspath(__file__), "rb").read()
    return hashlib.sha256(texto.encode() + b"\x00" + mio).hexdigest()[:16]


def render_bundle(c, planes, h):
    org = c["organizacion"]
    ns = f"org-{org}"
    cuota = planes["cuota"][c["cuota"]]
    lineas = [CABECERA.format(org=org, hash=h)]
    lineas.append(f"""\
#
# Namespace, cuota y la identidad con la que se pullea.
---
apiVersion: v1
kind: Namespace
metadata:
  name: {ns}
  labels:
    # ESTA ETIQUETA ES LA FRONTERA DE SEGURIDAD, no una clasificación.
    # Es lo que mete al namespace en el alcance del webhook de Kyverno:
    # sin ella, acá entrarían imágenes sin firmar y NADA avisaría. Pasó
    # el 2026-07-27 con org-portafolio y org-ecommerce, que nacieron
    # fuera del alcance y admitieron un busybox público.
    aegis.dev/part-of: aegis-tenants
    pod-security.kubernetes.io/enforce: restricted
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: {ns}-quota
  namespace: {ns}
spec:
  # Plan `{c["cuota"]}` de plans.yaml. Los números NO se editan acá:
  # se cambia el plan, o se le cambia la cuota al contrato.
  hard:""")
    for k in ("requests.cpu", "requests.memory", "limits.cpu", "limits.memory",
              "pods", "persistentvolumeclaims", "requests.storage"):
        # A mano y no con yaml.safe_dump: para un escalar suelto,
        # safe_dump emite el marcador de fin de documento `...`, que
        # partía el stream a la mitad de la ResourceQuota. Un cantidad de
        # K8s va SIEMPRE entre comillas — `2` sin comillas es un entero y
        # el apiserver rechaza el objeto.
        lineas.append(f'    {k}: "{cuota[k]}"')
    lineas.append(f"""\
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: {ns}
# El tenant NO usa la API de K8s: la app corre, no se administra. Un pod
# comprometido no puede hablarle al apiserver. Una app que SÍ necesite la
# API lo pide a nivel de pod y queda visible en su manifiesto.
automountServiceAccountToken: false
imagePullSecrets:
  # Patrón A: la plataforma provee el CÓMO pullear; las apps no declaran
  # credenciales de registry.
  - name: regcred-internal
""")
    return "\n".join(lineas)


def render_datos(c, h):
    """Los servicios que provee la PLATAFORMA, no un repo del tenant.

    Hoy solo postgres. Sale de services.yaml, que es la tabla de "con
    qué se cumple cada tipo" — el mismo papel que ai/routes.yaml cumple
    para las capacidades de AI.
    """
    bases = [s for s in c["servicios"] if s["tipo"] == "postgres"]
    if not bases:
        return None

    org = c["organizacion"]
    ns = f"org-{org}"
    cat = yaml.safe_load(open(SERVICIOS, encoding="utf-8"))
    t = cat["tipos"]["postgres"]
    imagen = f"{cat['registro']}/{t['imagen']}@{t['digest']}"

    partes = [CABECERA.format(org=org, hash=h), f"""\
#
# Bases de datos de esta organización.
#
# UNA BASE POR ORGANIZACIÓN, nunca compartida. Un `DROP` de una no puede
# tocar a la vecina, y el costo en RAM de un postgres ocioso es
# despreciable frente a esa garantía.
#
# La imagen va POR DIGEST (services.yaml). Con un tag, Kyverno le
# agregaría el digest al admitir y desired != live para siempre; la
# salida obvia —ignoreDifferences sobre la imagen— APAGA el auto-sync.
# Con el digest en git la mutación es un no-op. Es el hallazgo #36."""]

    for s in sorted(bases, key=lambda x: x["nombre"]):
        n = s["nombre"]
        app = f"{org}-{n}"
        partes.append(f"""\
---
# Headless: cada réplica tiene DNS propio. Con una sola réplica da
# igual, pero un Service normal delante de un StatefulSet es la clase de
# atajo que después nadie se anima a cambiar.
apiVersion: v1
kind: Service
metadata:
  name: {n}
  namespace: {ns}
  labels: {{app: {app}, aegis.dev/component: datos}}
spec:
  clusterIP: None
  selector: {{app: {app}}}
  ports:
    - {{name: postgres, port: {t['puerto']}, targetPort: {t['puerto']}}}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {n}
  namespace: {ns}
  labels: {{app: {app}, aegis.dev/component: datos}}
spec:
  serviceName: {n}
  # UNA réplica. Postgres no se replica poniendo replicas: 2 — eso da
  # dos bases distintas peleando por el mismo disco. La alta
  # disponibilidad real es otra decisión y otro operador.
  replicas: 1
  selector:
    matchLabels: {{app: {app}}}
  template:
    metadata:
      labels: {{app: {app}, aegis.dev/component: datos}}
    spec:
      # El tenant no habla con la API de Kubernetes.
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: {t['uid']}
        runAsGroup: {t['uid']}
        # fsGroup para que el PVC nazca escribible por ese UID: sin
        # esto el arranque muere en "permission denied" sobre PGDATA y
        # el mensaje no se parece a la causa.
        fsGroup: {t['uid']}
        seccompProfile: {{type: RuntimeDefault}}
      containers:
        - name: postgres
          image: {imagen}
          ports:
            - {{name: postgres, containerPort: {t['puerto']}}}
          env:
            # La credencial NUNCA en el manifiesto: sale del secreto
            # cifrado con SOPS que lista secret-generator.yaml.
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef: {{name: {n}-credenciales, key: password}}
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef: {{name: {n}-credenciales, key: usuario}}
            - name: POSTGRES_DB
              value: {org}
            # PGDATA en un SUBDIRECTORIO del volumen, no en la raíz: el
            # `lost+found` de un ext4 hace que initdb se niegue a
            # arrancar sobre un directorio "no vacío".
            - {{name: PGDATA, value: /var/lib/postgresql/data/pgdata}}
          volumeMounts:
            - {{name: datos, mountPath: /var/lib/postgresql/data}}
            # /tmp y /run escribibles porque el root filesystem no lo es:
            # postgres necesita el socket unix y archivos temporales.
            - {{name: tmp, mountPath: /tmp}}
            - {{name: run, mountPath: /var/run/postgresql}}
          # `pg_isready` y no un TCP genérico: el puerto abre antes de
          # que la base acepte consultas, y una sonda que solo mira el
          # puerto declara listo un servicio que todavía rechaza todo.
          readinessProbe:
            exec: {{command: ["pg_isready", "-U", "$(POSTGRES_USER)", "-d", "{org}"]}}
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            exec: {{command: ["pg_isready", "-U", "$(POSTGRES_USER)", "-d", "{org}"]}}
            initialDelaySeconds: 30
            periodSeconds: 20
            failureThreshold: 3
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {{drop: [ALL]}}
            readOnlyRootFilesystem: true
          resources:
            requests: {{cpu: 100m, memory: 256Mi}}
            limits: {{cpu: "1", memory: 1Gi}}
      volumes:
        - name: tmp
          emptyDir: {{}}
        - name: run
          emptyDir: {{}}
  volumeClaimTemplates:
    # apiVersion, kind y volumeMode los rellena el apiserver por default.
    # Van DECLARADOS: sin ellos desired != live en cada refresh y el
    # StatefulSet queda OutOfSync PARA SIEMPRE. Medido con el Garage el
    # 2026-08-04, antes de que existiera el primer postgres generado.
    #
    # La salida obvia —ampliar ignoreDifferences a todo el
    # volumeClaimTemplate— apaga el auto-sync y de paso tapa un cambio
    # real de tamaño o de accessMode (#36). Declarar un default es
    # gratis; ignorarlo se paga.
    - apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: datos
      spec:
        accessModes: [ReadWriteOnce]
        volumeMode: Filesystem
        resources:
          requests: {{storage: {t['disco']}}}""")
    return "\n".join(partes) + "\n"


def repos_de(c):
    """Los repos de un contrato, mapeados al nombre de su Application.

    UNA sola fuente para las dos cosas que dependen de esta lista: las
    Applications que se generan, y el `sourceRepos` del AppProject que
    las acota. Calcularla dos veces es cómo se desincronizan — y la
    forma de fallar sería fea: la App existe, el proyecto no la deja
    leer su propio repo, y el error habla de permisos y no de que
    faltó una línea.

    El repo puede estar en el contrato (uno para toda la organización)
    o en un servicio (un repo propio). El validador acepta las dos, así
    que las dos tienen que llegar al proyecto.
    """
    org = c["organizacion"]
    repos = {}
    if c.get("repo"):
        repos[c["repo"]] = org
    for s in c.get("servicios") or []:
        if s.get("repo"):
            repos.setdefault(s["repo"], f"{org}-{s['nombre']}")
    return repos


def render_apps(c, h):
    """Una Application de ArgoCD por repo declarado.

    Servicios que comparten repo comparten Application: el repo trae su
    propio overlay de kustomize con todos sus manifiestos. Dos
    Applications sobre el mismo objeto se lo disputan y dejan la app
    OutOfSync para siempre — un recurso, un dueño.
    """
    org = c["organizacion"]
    ns = f"org-{org}"
    repos = repos_de(c)

    # Sin repos no hay Applications, y entonces no hay archivo. Devolver
    # el encabezado solo produce un YAML sin objetos, que kustomize
    # acepta y `kubectl apply` rechaza con "no objects passed to apply".
    if not repos:
        return None

    partes = [CABECERA.format(org=org, hash=h), """\
#
# Las Applications de esta organización.
#
# Viven acá, CON su organización, y no en argocd-apps/. Declararlas en
# los dos lados hace que dos Applications se disputen el mismo objeto y
# la App root quede OutOfSync de forma permanente."""]
    for repo, nombre in sorted(repos.items()):
        partes.append(f"""\
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  # El nombre de la Application. Hasta #59 tenía que coincidir con el
  # namePattern del Image Updater; ese componente se retiró —el digest
  # lo escribe el propio pipeline desde #36/#37— así que el nombre ya
  # no acopla con nada de la plataforma.
  name: {nombre}
  namespace: argocd
  labels: {{aegis.dev/part-of: aegis-tenants}}
spec:
  # Proyecto de ESTA organización: solo puede leer de su repo y solo
  # puede escribir en su namespace. cluster-scoped vacío.
  project: aegis-tenant-{org}
  source:
    repoURL: {repo}
    targetRevision: main
    path: k8s/overlays/dev
  destination: {{server: https://kubernetes.default.svc, namespace: {ns}}}
  syncPolicy:
    automated: {{selfHeal: true}}
    syncOptions: [ServerSideApply=true]
  # SIN ignoreDifferences sobre la imagen, y es deliberado.
  #
  # Tenerlo era la respuesta obvia a que Kyverno reescribe la imagen
  # agregándole el digest verificado. Pero APAGABA EL AUTO-SYNC: si la
  # única diferencia entre git y el cluster es la imagen, y la imagen
  # está ignorada, ArgoCD no ve nada que hacer y nada se despliega. La
  # app queda verde y quieta. Medido el 2026-08-03 (#36): 4 syncs en 8
  # días, todos por cambios estructurales.
  #
  # La solución no es ignorar la deriva: es NO PRODUCIRLA. El pipeline
  # escribe el DIGEST en git (etapa `desplegar`), con lo cual la
  # mutación de Kyverno es un no-op —verificado por admisión, entrada
  # idéntica a salida— y no queda nada que ignorar.
  #
  # Si una organización vuelve a quedar OutOfSync por la imagen,
  # significa que su pipeline está escribiendo un TAG. El arreglo va
  # ahí, no acá.""")
    return "\n".join(partes) + "\n"


def render_netpol(c, h):
    org = c["organizacion"]
    ns = f"org-{org}"
    partes = [CABECERA.format(org=org, hash=h), f"""\
#
# Aislamiento de red. TODO denegado salvo lo que el contrato concedió.
#
# Lo que un servicio no declara en `usa:`, no alcanza. No por convención
# ni por revisión de código: porque el kernel no lo deja.
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: {ns}
spec:
  podSelector: {{}}
  policyTypes: [Ingress, Egress]
---
# Entrada SOLO desde el borde, y solo al 8080. El puerto es parte del
# contrato: una app que escuche en otro lado arranca bien y no recibe
# tráfico nunca — un fallo silencioso.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-edge-ingress
  namespace: {ns}
spec:
  podSelector: {{}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: {{kubernetes.io/metadata.name: infra-edge}}
      ports:
        - {{protocol: TCP, port: 8080}}
---
# Entre pods de la MISMA organización se permite: un front hablándole a
# su propio backend es el caso normal, y obligar a declararlo uno por
# uno solo produce políticas que nadie mantiene.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intra-namespace
  namespace: {ns}
spec:
  podSelector: {{}}
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - podSelector: {{}}
  egress:
    - to:
        - podSelector: {{}}
---
# DNS. Sin esto nada resuelve y el síntoma no se parece a la causa.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: {ns}
spec:
  podSelector: {{}}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: {{kubernetes.io/metadata.name: kube-system}}
      ports:
        - {{protocol: UDP, port: 53}}
        - {{protocol: TCP, port: 53}}"""]

    for s in sorted(c["servicios"], key=lambda x: x["nombre"]):
        etiqueta = f"{org}-{s['nombre']}"
        for u in sorted(s.get("usa") or []):
            if u == "ai":
                partes.append(f"""\
---
# {s['nombre']} -> gateway de AI, PUERTA INTERNA (8081).
#
# La puerta interna y la pública son PUERTOS distintos, no rutas: así la
# separación la impone el kernel y no un `if` en el código. Un pod de
# tenant no puede alcanzar la puerta pública ni falsificar cabeceras de
# cliente.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-{s['nombre']}-a-ai-gateway
  namespace: {ns}
spec:
  podSelector:
    matchLabels: {{app: {etiqueta}}}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: {{kubernetes.io/metadata.name: ai-system}}
          podSelector:
            matchLabels: {{app: ai-gateway}}
      ports:
        - {{protocol: TCP, port: 8081}}""")
            elif u == "postgres":
                # Egress explícito aunque `allow-intra-namespace` ya lo
                # permitiría: esta política no AGREGA permiso, DOCUMENTA
                # la dependencia. El día que el intra-namespace se
                # cierre —que es hacia donde debería ir— lo declarado en
                # el contrato es lo que va a seguir funcionando.
                partes.append(f"""\
---
# {s['nombre']} -> la base de la organización.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-{s['nombre']}-a-postgres
  namespace: {ns}
spec:
  podSelector:
    matchLabels: {{app: {etiqueta}}}
  policyTypes: [Egress]
  egress:
    - to:
        - podSelector:
            matchLabels: {{aegis.dev/component: datos}}
      ports:
        - {{protocol: TCP, port: 5432}}""")
            elif u == "bucket":
                partes.append(f"""\
---
# {s['nombre']} -> almacenamiento S3 compartido (Garage).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-{s['nombre']}-a-garage
  namespace: {ns}
spec:
  podSelector:
    matchLabels: {{app: {etiqueta}}}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: {{kubernetes.io/metadata.name: garage-system}}
      ports:
        - {{protocol: TCP, port: 3900}}""")
            elif u == "internet":
                partes.append(f"""\
---
# {s['nombre']} -> internet, SOLO 443 y SOLO fuera de lo privado.
#
# Nació con org-shop (2026-08-21): la pasarela de pago vive afuera y
# ningún otro uso lo cubría. Dos recortes deliberados:
#   - puerto 443 únicamente: lo que una app de tenant tiene que
#     hablar con el mundo es HTTPS; abrir más es abrir por si acaso.
#   - except de los rangos privados: sin él, «internet» sería también
#     un pase al cluster entero por IP de pod/servicio, saltándose
#     todas las políticas de arriba. El kernel no sabe de intenciones.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-{s['nombre']}-a-internet
  namespace: {ns}
spec:
  podSelector:
    matchLabels: {{app: {etiqueta}}}
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]
      ports:
        - {{protocol: TCP, port: 443}}""")
    return "\n".join(partes) + "\n"


def render_ruteo(c, h):
    """La IngressRoute de la organización, derivada del contrato.

    Hasta #54 esto lo escribía a mano el repo de cada app, repitiendo lo
    que el contrato ya decía (`dominio` + `publico`). Dos motivos para
    traerlo acá, y el segundo pesa más que el primero:

    1. Si las dos copias discrepan, el modo de fallo es el peor: el CNAME
       existe, la red permite, el pod corre, y el visitante recibe un 404.
       Nada está caído y ningún chequeo se pone rojo.

    2. AISLAMIENTO. Un AppProject solo puede filtrar por *kind*, nunca por
       el valor de un campo, así que mientras el inquilino pueda crear
       IngressRoutes puede reclamar el `Host` de otra organización.
       MEDIDO el 2026-08-06: org-blog reclamó un hostname, org-ejemplo
       reclamó EL MISMO, los dos fueron admitidos sin queja y traefik
       terminó sirviendo el de org-ejemplo. El dueño legítimo no tiene
       defensa. Con el ruteo acá, el kind entra al blacklist del proyecto
       de inquilino y el robo deja de ser expresable.

    A cambio, la plataforma IMPONE la convención de nombres: el Service
    de un servicio `X` se llama `<org>-X` y escucha en 8080 — el mismo
    8080 que abre allow-edge-ingress, para que haya UN número en todo el
    sistema y no uno por capa.

    Desde #81/#90 emite además los TRES middlewares del borde y los
    engancha a cada ruta. Van en el namespace de la organización y no en
    infra-edge porque traefik corre SIN `allowCrossNamespace` (medido en
    sus args el 2026-08-13): una referencia cruzada no falla ruidosa —
    se ignora, y la ruta queda sin protección con todo en verde.
    """
    org = c["organizacion"]
    ns = f"org-{org}"
    if not c.get("dominio"):
        return None
    # El validador ya garantiza que dominio y `publico` van juntos; esto
    # es solo para no depender de ese orden desde acá.
    publicos = [s for s in c["servicios"] if s.get("publico")]
    if not publicos:
        return None

    # Del MÁS específico al menos: traefik evalúa por orden, y una regla
    # de Host suelta capturaría /api antes de que se la mire. Ordenar por
    # largo descendente deja `/` al final por construcción, sin ningún
    # caso especial que después alguien tenga que recordar.
    publicos.sort(key=lambda s: (-len(s["publico"]), s["nombre"]))

    partes = [CABECERA.format(org=org, hash=h), f"""\
#
# El ruteo de esta organización — DERIVADO de `dominio` y de los
# `publico:` del contrato. El repo de la app ya no lo escribe: no puede,
# IngressRoute está en el namespaceResourceBlacklist de su proyecto.
#
# ── LOS TRES MIDDLEWARES DEL BORDE (#81, #90) ─────────────────────
#
# Hasta el 2026-08-13 el cluster tenía CERO middlewares y los sitios
# públicos no mandaban una sola cabecera de seguridad: lo único que
# volvía era `server: cloudflare`. Con demos abiertas a internet eso
# deja de ser cosmético.
#
# Van en ESTE namespace y no en infra-edge: traefik corre sin
# `allowCrossNamespace`, así que una referencia cruzada no explota —
# se ignora en silencio y la ruta queda desnuda con todo en verde.
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: {org}-cabeceras
  namespace: {ns}
  labels: {{aegis.dev/part-of: aegis-organizaciones}}
spec:
  headers:
    # forceSTSHeader es OBLIGATORIO acá y no una preferencia: el TLS lo
    # termina Cloudflare, así que traefik ve HTTP plano y sin esto NO
    # emitiría STS nunca. La cabecera saldría ausente y el chequeo
    # diría «configurado» — enfermedad E.
    forceSTSHeader: true
    stsSeconds: 15552000            # 180 días
    stsIncludeSubdomains: false     # hay subdominios que no controlamos
    # sin `preload`: entrar a la lista de precarga de los navegadores es
    # prácticamente irreversible, y esto es un portafolio en desarrollo.
    contentTypeNosniff: true
    browserXssFilter: false         # obsoleto y con fallos propios
    referrerPolicy: strict-origin-when-cross-origin
    # frame-ancestors es la defensa REAL contra clickjacking; el
    # X-Frame-Options de abajo es para los navegadores viejos que no
    # miran CSP. Medido: los 4 sitios sirven CERO iframes, así que
    # 'none' no rompe nada de lo que hay hoy.
    #
    # NO se declara un CSP completo (default-src/script-src) a
    # propósito: el portafolio sirve 3 scripts inline (hidratación de
    # las islas de Astro) y un `script-src 'self'` los mataría en el
    # navegador, sin error en ningún log del cluster. Eso es trabajo de
    # medir sitio por sitio; queda declarado, no fingido.
    contentSecurityPolicy: "frame-ancestors 'none'"
    customResponseHeaders:
      X-Frame-Options: "DENY"
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: {org}-ritmo
  namespace: {ns}
  labels: {{aegis.dev/part-of: aegis-organizaciones}}
spec:
  rateLimit:
    # Por VISITANTE, no por sitio. Es la parte que se puede hacer mal
    # sin notarlo: traefik ve como par a cloudflared —una sola IP de
    # pod— así que un criterio ingenuo metería a todo internet en un
    # mismo balde y un visitante ocupado ahogaría a los demás.
    #
    # Acá funciona porque el entrypoint `web` lleva
    # forwardedHeaders.trustedIPs=10.42.0.0/16, y con eso la estrategia
    # por defecto resuelve la IP del visitante real. MEDIDO el
    # 2026-08-13: el origen recibe `XFF: 186.9.x.x, 10.42.0.206` — la
    # IP pública primero, la del pod de cloudflared después.
    #
    # Y es resistente a falsificación por construcción: Cloudflare
    # AÑADE la IP real al final de la XFF que mande el cliente, y
    # traefik toma la última NO confiable. Inventar entradas por la
    # izquierda no corre el resultado.
    average: 50                     # req/s sostenidos por visitante
    burst: 100                      # una carga de página son ~20-50
    period: 1s
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: {org}-cuerpo
  namespace: {ns}
  labels: {{aegis.dev/part-of: aegis-organizaciones}}
spec:
  buffering:
    # SOLO la petición. `maxResponseBodyBytes` está ausente a
    # propósito: bufferear la RESPUESTA rompería el streaming del chat
    # de AI (SSE), y el síntoma —«el chat se quedó pensando»— no se
    # parece en nada a la causa.
    maxRequestBodyBytes: 10485760   # 10 MiB
    memRequestBodyBytes: 1048576    # 1 MiB en RAM, el resto a disco
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: {org}-ruteo
  namespace: {ns}
  labels: {{aegis.dev/part-of: aegis-organizaciones}}
spec:
  # `web` y no `websecure`: el TLS lo termina Cloudflare y el túnel
  # entrega HTTP plano acá adentro. Un certificado en traefik sería un
  # segundo lugar donde vencerse.
  entryPoints: [web]
  routes:"""]
    for s in publicos:
        # PathPrefix solo cuando la ruta no es la raíz: `PathPrefix(/)`
        # matchea todo y convertiría la regla en un Host suelto escrito
        # de forma más larga.
        ruta = s["publico"]
        match = f"Host(`{c['dominio']}`)"
        if ruta != "/":
            match += f" && PathPrefix(`{ruta}`)"
        # Los middlewares van POR RUTA y no una vez por IngressRoute
        # porque traefik no tiene «middlewares de la IngressRoute»: se
        # declaran en cada regla. Repetirlos acá no es duplicación —
        # una ruta sin la lista es una ruta sin protección.
        partes.append(f"""\
    # {s['nombre']} — `publico: {ruta}` en el contrato
    - kind: Rule
      match: {match}
      middlewares:
        - {{name: {org}-cabeceras}}
        - {{name: {org}-ritmo}}
        - {{name: {org}-cuerpo}}
      services:
        - {{name: {org}-{s['nombre']}, port: 8080}}""")
    return "\n".join(partes) + "\n"


def render_kustomization(c, h, secretos):
    org = c["organizacion"]
    partes = [CABECERA.format(org=org, hash=h), """\
#
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - bundle.yaml
  - netpol.yaml"""]
    # Condicionales por la misma razón que en garage-system: kustomize
    # FALLA si un recurso listado no existe en disco. Listar apps.yaml
    # cuando la organización todavía no tiene repo rompería el render
    # entero, y el error apuntaría a kustomize y no al contrato.
    if any(s.get("repo") for s in c["servicios"]) or c.get("repo"):
        partes.append("  - apps.yaml")
    if any(s["tipo"] == "postgres" for s in c["servicios"]):
        partes.append("  - datos.yaml")
    if c.get("dominio") and any(s.get("publico") for s in c["servicios"]):
        partes.append("  - routes.yaml")
    if secretos:
        partes.append("generators:\n  - secret-generator.yaml")
    return "\n".join(partes) + "\n"


def render_secret_generator(c, h, secretos):
    org = c["organizacion"]
    partes = [CABECERA.format(org=org, hash=h), f"""\
#
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: org-{org}-secrets
  annotations:
    config.kubernetes.io/function: |
      exec: {{path: ksops}}
# LISTA EXPLÍCITA (A7): nada de globs. Un glob incorpora en silencio
# cualquier .enc.yaml que caiga en el directorio.
files:"""]
    for s in secretos:
        partes.append(f"  - {s}")
    return "\n".join(partes) + "\n"


def secretos_de(c):
    """Qué secretos necesita esta organización, en orden estable."""
    s = ["secret-regcred-internal.enc.yaml"]
    if c.get("ai") is not None:
        s.append("secret-ai-gateway-key.enc.yaml")
    if (c.get("almacenamiento") or {}).get("bucket"):
        s.append("secret-garage.enc.yaml")
    # Uno por base y no uno por organización: dos bases con la misma
    # credencial son una sola base con dos nombres.
    for b in sorted(x["nombre"] for x in c["servicios"] if x["tipo"] == "postgres"):
        s.append(f"secret-{b}-credenciales.enc.yaml")
    return s


def renderizar(c, planes, crudo):
    h = _hash(crudo)
    secretos = secretos_de(c)
    salida = {
        "bundle.yaml": render_bundle(c, planes, h),
        "netpol.yaml": render_netpol(c, h),
        "kustomization.yaml": render_kustomization(c, h, secretos),
    }
    # apps.yaml SOLO si hay algún repo. Sin repos el archivo salía con
    # el encabezado y ni un objeto adentro: `kubectl apply` responde "no
    # objects passed to apply". Un archivo generado que no produce nada
    # es ruido que después alguien lee buscando por qué no se despliega.
    if (apps := render_apps(c, h)) is not None:
        salida["apps.yaml"] = apps
    if (datos := render_datos(c, h)) is not None:
        salida["datos.yaml"] = datos
    if (ruteo := render_ruteo(c, h)) is not None:
        salida["routes.yaml"] = ruteo
    if secretos:
        salida["secret-generator.yaml"] = render_secret_generator(c, h, secretos)
    return salida, secretos


# ──────────────────────────────────────────────────────────────────
# Aplicar
# ──────────────────────────────────────────────────────────────────

def _sin_hash(t):
    return markers.sin_hash(t)


def aplicar(ruta, escribir):
    crudo = open(ruta, encoding="utf-8").read()
    planes = yaml.safe_load(open(PLANES, encoding="utf-8"))
    c = validar(yaml.safe_load(crudo), planes)
    org = c["organizacion"]
    destino = os.path.join(DIR_K8S, f"org-{org}")
    salida, secretos = renderizar(c, planes, crudo)

    print(f"\norganización {verde}{org}{fin}  ·  contrato v{c['version']}  ·  "
          f"cuota {c['cuota']}" + (f"  ·  ai {c['ai']['plan']}" if c.get("ai") else ""))
    print(f"{gris}destino: k8s/organizations/org-{org}/{fin}\n")

    cambios = 0
    generados = set(salida)
    for nombre in sorted(salida):
        camino = os.path.join(destino, nombre)
        nuevo = salida[nombre]
        if not os.path.exists(camino):
            print(f"  {verde}+{fin} {nombre}  {gris}(nuevo){fin}")
            cambios += 1
            if escribir:
                os.makedirs(destino, exist_ok=True)
                open(camino, "w", encoding="utf-8").write(nuevo)
            continue
        viejo = open(camino, encoding="utf-8").read()
        if viejo == nuevo:
            print(f"  {gris}={fin} {nombre}")
            continue
        # I3: si el archivo fue editado a mano, negarse y mostrar qué
        # cambió. La salida es el contrato, no el archivo — pero pisar
        # el trabajo de alguien sin mostrarlo es peor que no generar.
        if markers.es_generado(viejo) and _sin_hash(viejo) != _sin_hash(nuevo):
            marca_vieja = [l for l in viejo.splitlines() if l.startswith("# hash:")]
            marca_nueva = [l for l in nuevo.splitlines() if l.startswith("# hash:")]
            if marca_vieja == marca_nueva:
                print(f"  {rojo}!{fin} {nombre}  {rojo}EDITADO A MANO{fin} "
                      f"{gris}(mismo contrato, contenido distinto){fin}")
                for l in list(difflib.unified_diff(
                        viejo.splitlines(), nuevo.splitlines(),
                        "en disco", "generado", lineterm=""))[:40]:
                    print(f"      {gris}{l}{fin}")
                print(f"      {ama}no se pisó. Revisá si el cambio debe ir al contrato.{fin}")
                cambios += 1
                continue
        print(f"  {ama}~{fin} {nombre}")
        cambios += 1
        if escribir:
            open(camino, "w", encoding="utf-8").write(nuevo)

    # I4: convergencia. Lo que el generador ya no produce, sobra.
    if os.path.isdir(destino):
        for nombre in sorted(os.listdir(destino)):
            if nombre in generados or nombre.endswith(".enc.yaml"):
                continue
            print(f"  {rojo}-{fin} {nombre}  {gris}(ya no lo produce el contrato){fin}")
            cambios += 1
            if escribir:
                os.remove(os.path.join(destino, nombre))

    faltan = [s for s in secretos
              if not os.path.exists(os.path.join(destino, s))]
    if faltan:
        print(f"\n  {ama}secretos que faltan{fin}")
        for s in faltan:
            print(f"    · {s}")
        # El comando exacto, no "creá los secretos". Este generador NO
        # los crea a propósito: escribe manifiestos y no maneja material
        # criptográfico, y separar las dos cosas es lo que permite
        # correrlo sin pensarlo.
        print(f"  {gris}se crean con:{fin}  {CMD_SECRET} {ruta}")
        print(f"  {gris}se crean si faltan y NUNCA se regeneran: reaplicar no rota nada{fin}")

    if not cambios:
        print(f"\n{verde}sin cambios{fin} — ya converge\n")
        return 0
    if escribir:
        print(f"\n{verde}{cambios} cambio(s) escritos.{fin} Revisá el diff y commiteá.\n")
    else:
        print(f"\n{ama}{cambios} cambio(s).{fin} Nada escrito (esto fue `plan`).\n")
    return 0


# ──────────────────────────────────────────────────────────────────
# El borde
#
# `public_hostnames` de tofu se DERIVA: plataforma (edge.yaml) + los
# `dominio:` de TODOS los contratos. Nadie edita esa lista a mano.
#
# El modo de fallo que esto elimina es el peor de todos: si un hostname
# falta, simplemente NO EXISTE. Sin error, sin alarma, sin nada rojo —
# el IngressRoute del cluster está perfecto y nadie llega. Ya pasó con
# ai.__ROOT_DOMAIN__ (#35) y casi pasa con blog.
#
# Se lee TODO orgs/*.yaml y no solo el contrato que se está aplicando:
# la lista es de la instancia entera, no de una organización. Aplicar
# uno solo y reescribir la lista con él borraría a los demás.
# ──────────────────────────────────────────────────────────────────

PATRON_HOSTNAMES = re.compile(r"^(\s*)public_hostnames\s*=\s*\[[^\]]*\]", re.M)


def etiquetas_del_borde():
    edge = yaml.safe_load(open(EDGE, encoding="utf-8"))
    raiz = edge["root_domain"]
    etiquetas = list(edge.get("platform") or [])
    de_contratos = []
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8"))
        dom = (c or {}).get("dominio")
        if not dom:
            continue
        if not dom.endswith("." + raiz):
            raise Invalido(
                f"{nombre}: dominio {dom!r} no está bajo {raiz!r}.\n"
                f"  El borde solo puede crear CNAMEs dentro de su zona. Un dominio\n"
                f"  de otra zona necesita otra decisión, no una entrada más.")
        de_contratos.append(dom[: -(len(raiz) + 1)])
    # Orden estable: plataforma primero (en el orden declarado), después
    # los tenants alfabéticos. Sin esto el diff cambia según el sistema
    # de archivos y rompe I1.
    for e in sorted(de_contratos):
        if e not in etiquetas:
            etiquetas.append(e)
    return etiquetas


def aplicar_borde(escribir):
    etiquetas = etiquetas_del_borde()
    linea = 'public_hostnames = [' + ", ".join(f'"{e}"' for e in etiquetas) + "]"
    tf = open(MAIN_TF, encoding="utf-8").read()
    m = PATRON_HOSTNAMES.search(tf)
    if not m:
        raise Invalido(f"no encontré `public_hostnames = [...]` en {MAIN_TF}")
    nuevo = PATRON_HOSTNAMES.sub(lambda mm: mm.group(1) + linea, tf, count=1)
    print(f"\nborde  {gris}(tofu/envs/cloudflare-tunnel/main.tf){fin}")
    if nuevo == tf:
        print(f"  {gris}={fin} public_hostnames  {gris}{len(etiquetas)} hostnames{fin}")
        return 0
    print(f"  {ama}~{fin} public_hostnames -> {', '.join(etiquetas)}")
    if escribir:
        open(MAIN_TF, "w", encoding="utf-8").write(nuevo)
        # NO dice "el job lo hace solo". Lo decía, y desde #46 es falso:
        # el state va cifrado con la age key y la age key no entra a CI,
        # así que CI no puede aplicar. Una instrucción que promete que
        # algo pasa solo es peor que no tenerla — el hostname no existe
        # y nadie lo espera.
        print(f"  {ama}el CNAME no existe hasta que corras esto:{fin}")
        print(f"  {gris}  SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key \\{fin}")
        print(f"  {gris}    tofu/tofu-apply.sh -chdir=envs/cloudflare-tunnel apply{fin}")
        print(f"  {gris}  (después, commiteá el state recifrado){fin}")
    return 0


# ──────────────────────────────────────────────────────────────────
# Borrar
#
# El punto más débil del protocolo, y conviene decirlo antes que
# descubrirlo: `prune` está OMITIDO en toda la plataforma (A19). Quitar
# archivos de git NO quita nada del cluster. Un `borrar` que solo tocara
# git dejaría el namespace, sus datos y su cuota corriendo, y la
# organización parecería borrada.
#
# Por eso son dos pasos separados y en este orden:
#
#   1. lo de GIT, que es reversible: se quitan los archivos generados y
#      las derivaciones (borde, ruteo) dejan de nombrarla solas.
#   2. lo del CLUSTER, que NO es reversible: se IMPRIMEN los comandos y
#      no se ejecutan.
#
# El paso 2 no se automatiza porque borrar un namespace se lleva puestos
# los datos, y eso no puede pasar por un comando corrido con un nombre
# mal tipeado. El día que haya prune con confirmación, puede cambiar.
# ──────────────────────────────────────────────────────────────────


def borrar(nombre, escribir):
    if not NOMBRE_VALIDO.match(nombre):
        raise Invalido(f"{nombre!r} no es un nombre de organización válido")

    contrato = None
    for ext in (".yaml", ".yml"):
        p = os.path.join(DIR_ORGS, nombre + ext)
        if os.path.exists(p):
            contrato = p
            break
    destino = os.path.join(DIR_K8S, f"org-{nombre}")
    if contrato is None and not os.path.isdir(destino):
        raise Invalido(
            f"no existe orgs/{nombre}.yaml ni k8s/organizations/org-{nombre}/.\n"
            f"  Nada que borrar. Si la organización está viva en el cluster pero\n"
            f"  no en git, es un huérfano: lo reporta `{CMD_CHECK}`.")
    # El contrato se lee AHORA, antes de que el paso 1 lo borre del
    # disco: el paso 2 lo necesita para nombrar las Applications.
    contrato_dict = (yaml.safe_load(open(contrato, encoding="utf-8")) or {}) \
        if contrato else None

    ns = f"org-{nombre}"
    print(f"\norganización {rojo}{nombre}{fin}  ·  {gris}borrar{fin}")

    # ── paso 1: git ────────────────────────────────────────────────
    print(f"\n{gris}1) en git (reversible){fin}")
    quitar = []
    if contrato:
        quitar.append(contrato)
    if os.path.isdir(destino):
        for f in sorted(os.listdir(destino)):
            quitar.append(os.path.join(destino, f))

    cifrados = [q for q in quitar if q.endswith(".enc.yaml")]
    for q in quitar:
        rel = os.path.relpath(q, RAIZ)
        marca = f"  {rojo}-{fin}"
        extra = f"  {ama}(secreto cifrado){fin}" if q.endswith(".enc.yaml") else ""
        print(f"{marca} {rel}{extra}")

    if cifrados:
        print(f"\n  {ama}OJO con los .enc.yaml.{fin} {gris}Borrarlos del repo NO revoca nada:\n"
              f"  la credencial sigue siendo válida donde la acepten. Revocar es\n"
              f"  el paso 2, y va ANTES de borrar el archivo si te importa poder\n"
              f"  auditarla después.{fin}")

    if escribir:
        for q in quitar:
            os.remove(q)
        if os.path.isdir(destino) and not os.listdir(destino):
            os.rmdir(destino)
        print(f"\n  {verde}quitado de git.{fin} {gris}El borde y el ruteo se rederivan abajo:\n"
              f"  su hostname y su plan desaparecen solos porque salen de los\n"
              f"  contratos, no de una lista aparte.{fin}")
    else:
        print(f"\n  {ama}nada escrito{fin} {gris}(esto fue `plan-borrar`){fin}")

    # ── paso 2: el cluster ─────────────────────────────────────────
    print(f"\n{gris}2) en el cluster{fin} {rojo}— NO se ejecuta{fin}")
    print(f"{gris}   Revisá cada línea. Se ordenan de menos a más destructivo, y la\n"
          f"   del namespace va última porque se lleva los datos con ella.{fin}\n")

    # Los nombres de las Applications salen del CONTRATO, con la misma
    # regla que render_apps. Decir "revisá cuál" sería devolverle al
    # operador un trabajo que el contrato ya tiene resuelto, y es
    # justamente en ese paso donde un nombre a ojo borra la app de otra
    # organización.
    #
    # OJO con el orden: si `escribir`, el paso 1 YA BORRÓ el archivo —
    # se lee la copia que quedó en memoria, no el disco. Leído acá del
    # disco reventaba con FileNotFoundError justo en la corrida real
    # (con `plan-borrar` andaba, que es la peor forma de fallar).
    apps = []
    if contrato and contrato_dict is not None:
        c = contrato_dict
        if c.get("repo"):
            apps.append(nombre)
        for s in c.get("servicios") or []:
            if s.get("repo"):
                apps.append(f"{nombre}-{s['nombre']}")
    cmd_apps = (" ".join(f"kubectl delete application -n argocd {a};" for a in sorted(set(apps)))
                if apps else
                "# el contrato ya no está: mirá cuáles quedaron con\n"
                "    #   kubectl get applications -n argocd -l aegis.dev/part-of=aegis-tenants")

    pasos = [
        ("las Applications, PRIMERO: mientras vivan, recrean lo que borres",
         cmd_apps),
        # El documento SÍ se quita solo desde #19: appprojects-tenants.yaml
        # es derivado y esta misma corrida lo rederiva sin la
        # organización. Lo que no se hace solo es sacarlo del CLUSTER:
        # ArgoCD no gestiona los AppProjects a propósito (W-06 / R1-B),
        # así que vale la regla A19 de siempre — quitarlo de git no lo
        # quita de acá.
        ("el AppProject de la organización (el documento ya lo quitó el generador)",
         f"kubectl delete appproject aegis-tenant-{nombre} -n argocd"),
        # El archivo cifrado lo quita esta misma corrida (es derivado),
        # pero eso NO revoca nada: la deploy key sigue autorizada en
        # GitHub hasta que se la borre allá. Es la misma distinción que
        # con el bucket y con la clave de Garage — quitar la credencial
        # del repo no es lo mismo que retirarle el permiso al tercero.
        ("su deploy key en GitHub (el archivo ya lo quitó el generador)",
         f"# gh repo deploy-key list -R <owner>/<repo>\n"
         f"    # gh repo deploy-key delete -R <owner>/<repo> <id>"),
        ("sus tareas de AI y su clave (archivos compartidos, a mano)",
         f"# k8s/base/ai-system/registro.yaml   -> quitar las tareas '{nombre}.*'\n"
         f"    # k8s/base/ai-system/secret-ai-keys.enc.yaml -> quitar su entrada\n"
         f"    #   (sops k8s/base/ai-system/secret-ai-keys.enc.yaml)"),
        ("su bucket, SI tenía almacenamiento",
         f"# el bucket vive en el Garage compartido: borrarlo es una decisión\n"
         f"    # aparte y con backup previo"),
        ("el namespace y TODO lo que contiene, incluidos los datos",
         f"kubectl delete namespace {ns}"),
    ]
    for i, (que, cmd) in enumerate(pasos, 1):
        print(f"  {i}. {que}")
        print(f"    {gris}{cmd}{fin}\n")

    print(f"{ama}Los PVC pueden sobrevivir al namespace{fin} {gris}según la reclaimPolicy.\n"
          f"Comprobalo DESPUÉS, que es cuando se nota:{fin}")
    print(f"  {gris}kubectl get pv | grep {ns}{fin}\n")
    return 0


# ──────────────────────────────────────────────────────────────────
# Migrar
#
# HOY SOLO EXISTE v1, y este comando lo dice en vez de fingir.
#
# Existe igual, y no como un TODO, porque el `--a` obligatorio y el
# rechazo explícito son lo que impide la alternativa mala: que alguien
# suba `version: 2` a mano en un contrato y el generador lo renderice
# con las reglas de v1 sin decir nada. `validar` ya rechaza una versión
# desconocida; esto le da al operador el lugar correcto donde preguntar.
#
# MIGRACIONES es el registro de traductores. Cuando exista v2, se agrega
# una entrada (1, 2) -> función, y el resto de este código no cambia.
# ──────────────────────────────────────────────────────────────────

MIGRACIONES = {}  # (desde, hasta) -> callable(contrato_dict) -> dict


def migrar(rutas, destino):
    conocidas = sorted({VERSION_CONTRATO} | {v for _, v in MIGRACIONES})
    if destino not in conocidas:
        print(f"{rojo}✗{fin} no existe la versión {destino} del contrato.\n"
              f"  Versiones que este generador sabe renderizar: "
              f"{', '.join(str(v) for v in conocidas)}.\n"
              f"\n"
              f"  Una versión nueva se justifica SOLO si cambia el contrato (§8).\n"
              f"  Cambiar los números de un plan, agregar una capacidad al ruteo o\n"
              f"  cambiar con qué se implementa un tipo NO son versión nueva: por\n"
              f"  eso viven fuera del contrato, en plans.yaml, ai/routes.yaml y\n"
              f"  services.yaml.", file=sys.stderr)
        return 1

    rc = 0
    for ruta in rutas:
        try:
            c = yaml.safe_load(open(ruta, encoding="utf-8"))
        except FileNotFoundError:
            print(f"{rojo}✗{fin} no existe: {ruta}", file=sys.stderr)
            rc = 1
            continue
        actual = (c or {}).get("version")
        if actual == destino:
            print(f"{gris}={fin} {ruta}  {gris}ya está en v{destino}{fin}")
            continue
        paso = MIGRACIONES.get((actual, destino))
        if paso is None:
            print(f"{rojo}✗{fin} {ruta}: no hay traductor de v{actual} a v{destino}",
                  file=sys.stderr)
            rc = 1
            continue
        # Cuando exista: aplicar el traductor, MOSTRAR EL DIFF y escribir
        # solo si el operador lo confirma. Nunca automático al aplicar.
        raise Invalido("traductor registrado pero no implementado")
    return rc


# ──────────────────────────────────────────────────────────────────
# El RUTEO que consume el gateway
# ──────────────────────────────────────────────────────────────────
#
# Tres fuentes, un archivo:
#
#   ai/routes.yaml   -> capacidades (con qué se sirve cada promesa)
#   plans.yaml     -> planes (los techos, con nombre)
#   orgs/*.yaml     -> tenants (qué plan tiene cada organización)
#
# El mapa tenant->plan se DERIVA de los contratos y no se escribe a
# mano en ningún lado. Escribirlo dos veces es garantizar que un día
# digan cosas distintas, y el síntoma sería una organización con el
# presupuesto de otra sin que nadie haya decidido eso.


def ruteo_json():
    ruteo = yaml.safe_load(open(RUTEO, encoding="utf-8")) or {}
    planes = yaml.safe_load(open(PLANES, encoding="utf-8"))

    caps = ruteo.get("capacidades") or {}
    if not caps:
        raise Invalido(f"{RUTEO}: sin capacidades — ninguna tarea podría servirse")

    tenants = {}
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        ai = c.get("ai")
        if not ai:
            continue  # una organización sin AI no aparece en el ruteo
        # La clave es el NAMESPACE, no el nombre corto del contrato: el
        # gateway identifica al tenant por lo que trae la API key, y eso
        # es `org-<nombre>`. Usar el nombre corto acá dejaría a toda
        # organización sin plan reconocido — y sin plan reconocido se
        # cae al más chico, en silencio.
        tenants[f"org-{c['organizacion']}"] = ai["plan"]

    doc = {
        "version": 1,
        # sort_keys en json.dumps no alcanza: los dicts anidados se
        # arman acá y el orden de inserción sería el del filesystem.
        "capacidades": {k: caps[k] for k in sorted(caps)},
        "planes": {k: planes["ai"][k] for k in sorted(planes["ai"])},
        "tenants": {k: tenants[k] for k in sorted(tenants)},
    }
    return json.dumps(doc, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def registro_ai_json():
    """El registro de tareas de AI, derivado de los contratos.

    QUÉ SALE DE DÓNDE, que es la división que importa:

      del contrato   el nombre de la tarea, su capacidad, su prompt y
                     —lo que de verdad había que derivar— el TENANT
      de ai/tasks.yaml   la clase y los topes numéricos

    El tenant era el acoplamiento peligroso. Hasta #60 había que
    acordarse de escribirlo a mano en registro.yaml, y si faltaba el
    gateway respondía 403 `tarea_prohibida` con la organización teniendo
    clave, red y plan en orden: nada del lado del contrato se ponía rojo.
    Es la misma forma que la IngressRoute de #54, un nivel más arriba.

    Los números NO se derivan y es deliberado: son ajuste fino por tarea
    y el contrato no tiene forma honesta de expresarlos sin volverse un
    archivo de configuración. Mismo criterio que plans.yaml.
    """
    cfg = yaml.safe_load(open(TAREAS_AI, encoding="utf-8"))
    clases = cfg.get("clases") or {}
    ajustes = cfg.get("tareas") or {}
    rut = yaml.safe_load(open(RUTEO, encoding="utf-8"))
    caps = rut.get("capacidades") or {}

    tareas = {}
    for nombre_arch in sorted(os.listdir(DIR_ORGS)):
        if not nombre_arch.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre_arch),
                                encoding="utf-8")) or {}
        ai = c.get("ai")
        if not ai:
            continue
        org = c["organizacion"]
        for tarea in (ai.get("tareas") or []):
            clave = f"{org}.{tarea['nombre']}"
            ajuste = ajustes.get(clave) or {}
            clase = ajuste.get("clase", "interactive")
            if clase not in clases:
                raise Invalido(
                    f"la tarea {clave!r} usa la clase {clase!r}, que no está en\n"
                    f"  ai/tasks.yaml. Las que hay: {', '.join(sorted(clases))}")
            cap = tarea["capacidad"]
            if cap not in caps:
                raise Invalido(
                    f"la tarea {clave!r} pide la capacidad {cap!r}, que no está en\n"
                    f"  ai/routes.yaml. Las que hay: {', '.join(sorted(caps))}")
            # Una tarea del carril CPU (clase `cpu`, #26) NO lleva
            # prompt: no genera texto. Se exige la coherencia en los dos
            # sentidos — un prompt en una tarea de embeddings es alguien
            # confundido, y una tarea de texto sin prompt es un registro
            # que el gateway va a rechazar al cargar. Mejor acá, donde
            # el que se entera es quien edita el contrato.
            if clase == "cpu":
                if tarea.get("prompt"):
                    raise Invalido(
                        f"la tarea {clave!r} es de clase cpu y declara un prompt.\n"
                        f"  Las tareas del carril CPU no generan texto: sin prompt.")
            elif not tarea.get("prompt"):
                raise Invalido(
                    f"la tarea {clave!r} no declara prompt, y su clase ({clase})\n"
                    f"  genera texto: el prompt es obligatorio.")
            e = dict(clases[clase])
            e.update({k: v for k, v in ajuste.items() if k != "clase"})
            tareas[clave] = {
                "clase": clase,
                "capacidad": cap,
                "engine": caps[cap]["engine"],
                # DERIVADO: una tarea la puede invocar SOLO la
                # organización cuyo contrato la declara. Antes era una
                # lista escrita a mano.
                "tenants": [f"org-{org}"],
                "prompt": tarea.get("prompt", ""),
                "max_output_tokens": e["max_output_tokens"],
                "max_context_tokens": e["max_context_tokens"],
                "max_input_chars": e["max_input_chars"],
                "temperature": e["temperature"],
                "stop": e.get("stop", []),
                "peso": e["peso"],
            }
    return json.dumps({"version": 1, "tareas": tareas},
                      indent=2, ensure_ascii=False) + "\n"


def render_registro_ai():
    cuerpo = registro_ai_json()
    h = hashlib.sha256(cuerpo.encode()).hexdigest()[:16]
    sangrado = "\n".join("    " + l if l.strip() else ""
                         for l in cuerpo.rstrip("\n").split("\n"))
    return f"""# GENERADO por {CMD_ORG} — no editar a mano.
# hash: {h}
#
# Sale de `ai.tareas` de cada contrato en orgs/ (nombre, capacidad,
# prompt y el TENANT autorizado) + ai/tasks.yaml (clase y topes) +
# ai/routes.yaml (qué engine sirve cada capacidad).
#
# LOS PROMPTS NO ESTÁN ACÁ: son contenido escrito a mano y viven en
# prompts.yaml, al lado. Mezclarlos garantizaba que el generador
# terminara pisando lo escrito.
#
# Para cambiarlo se edita la FUENTE y se corre `{CMD_ORG_APPLY}`.
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-registro
  namespace: ai-system
  labels:
    aegis.dev/component: ai
data:
  registro.json: |
{sangrado}
"""


def aplicar_registro_ai(escribir):
    rc = _sin_subsistema_ai("registro de AI")
    if rc is not None:
        return rc
    nuevo = render_registro_ai()
    print(f"\nregistro de AI  {gris}(k8s/base/ai-system/registro.yaml){fin}")
    try:
        viejo = open(REGISTRO_AI, encoding="utf-8").read()
    except FileNotFoundError:
        viejo = None
    if viejo == nuevo:
        print(f"  {gris}={fin} tareas de AI")
        return 0
    print(f"  {ama}~{fin} tareas de AI" if viejo else f"  {verde}+{fin} tareas de AI")
    if escribir:
        open(REGISTRO_AI, "w", encoding="utf-8").write(nuevo)
    return 0


def render_ruteo_k8s():
    cuerpo = ruteo_json()
    h = hashlib.sha256(cuerpo.encode()).hexdigest()[:16]
    sangrado = "\n".join("    " + l if l.strip() else "" for l in cuerpo.rstrip("\n").split("\n"))
    return f"""# GENERADO por {CMD_ORG} — no editar a mano.
# hash: {h}
#
# Sale de ai/routes.yaml (capacidades) + plans.yaml (planes) + el
# `ai.plan` de cada contrato en orgs/ (tenants).
#
# Para cambiarlo se edita la FUENTE y se corre `{CMD_ORG_APPLY}`.
# Editar esto a mano funciona hasta la próxima corrida, que lo pisa.
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-ruteo
  namespace: ai-system
  labels:
    aegis.dev/part-of: aegis-platform
    aegis.dev/component: ai-ruteo
data:
  ruteo.json: |
{sangrado}
"""


def render_tenants():
    """La Application que despliega la INFRAESTRUCTURA de cada
    organización, derivada de los contratos.

    Antes era un archivo a mano, y por eso dar de alta una organización
    seguía teniendo un paso manual: escribir el contrato, correr el
    generador... y acordarse de agregar veinte líneas acá. El síntoma de
    olvidarlo es el peor posible: todo generado, todo commiteado, y
    NADA desplegado, sin un solo error.

    Ojo con qué despliega esta Application y qué no. Acá va la
    infraestructura (namespace, cuota, netpols, secretos), con el
    proyecto `aegis-platform`. Las APPS de la organización vienen de sus
    propios repos y usan su `aegis-tenant-*`, que solo puede escribir en
    su namespace: esa separación es la frontera de permisos y no se
    mezcla.
    """
    orgs = []
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        orgs.append(c["organizacion"])

    partes = [markers.BANNER + f"""
# Una Application por CONTRATO en orgs/. Se rederiva en cada
# `{CMD_ORG_APPLY}`, así que agregar una organización es escribir
# su contrato y nada más.
#
# Lo heredado —organizaciones anteriores al generador— vive en
# tenants-heredados.yaml, a mano y a propósito: mezclarlo acá haría que
# la próxima corrida lo borrara en silencio.
#
# CreateNamespace=true: el Namespace está en el bundle, pero ArgoCD
# necesita que exista para aplicarle el resto; sin esta opción hay una
# carrera en el primer sync.
#
# RECORDATORIO: root NO tiene automated (ADR-0012). Agregar una App acá
# no la crea sola — hay que sincronizar root:  {CMD_SYNC_ROOT}"""]

    for org in orgs:
        partes.append(f"""\
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: org-{org}
  namespace: argocd
  labels: {{aegis.dev/part-of: aegis-platform}}
spec:
  # NO es `aegis-platform`. Esta App despliega el SUSTRATO de una
  # organización —namespace, cuota, red, secretos— y eso es un tercer
  # tipo: ni plataforma ni tenant. Su proyecto acota el cluster-scoped a
  # `Namespace` (en aegis-platform heredaba '*') y le busca huérfanos,
  # que en aegis-platform no pasaba (#47).
  project: aegis-organizaciones
  source:
    repoURL: {_repo_ops()}
    targetRevision: main
    path: k8s/organizations/org-{org}
  destination: {{server: https://kubernetes.default.svc, namespace: org-{org}}}
  syncPolicy:
    automated: {{selfHeal: true}}
    syncOptions: [ServerSideApply=true, CreateNamespace=true]
  ignoreDifferences:
    # El apiserver agrega un bloque `status` DENTRO de cada
    # volumeClaimTemplate de un StatefulSet. Es estado observado, no
    # configuración: no hay forma de declararlo, y sin esto una
    # organización con base de datos queda OutOfSync para siempre.
    #
    # El alcance es lo más angosto posible: SOLO .status de esas
    # entradas. NO todo /spec/volumeClaimTemplates, que es el atajo
    # habitual y taparía un cambio de tamaño o de accessMode.
    #
    # Y NO se ignora la imagen. Ese es el otro atajo, y APAGA el
    # auto-sync (#36): si la única diferencia es la imagen y la imagen
    # está ignorada, ArgoCD no ve nada que hacer. Acá no hace falta
    # porque todo lo generado va por digest.
    - group: apps
      kind: StatefulSet
      jqPathExpressions:
        - '.spec.volumeClaimTemplates[]?.status'""")
    return "\n".join(partes) + "\n"


# ── los AppProjects de tenant, derivados ──────────────────────────────
#
# El AppProject ES la frontera de permisos de una organización: dice de
# qué repo puede leer, en qué namespace puede escribir, y que no puede
# tocar nada cluster-scoped. Estaba escrito a mano, y el modo de fallo
# es de los feos: si falta, la Application arranca y ArgoCD dice
# "project not found" — ruidoso, sí, pero recién al desplegar, cuando ya
# se hicieron el contrato, el repo, el pipeline y el push.
#
# Y hay un modo peor, que es el que motiva esto de verdad: repetir el
# bloque a mano DERIVA. Se comprobó el 2026-08-05 en el cluster —
# `aegis-tenant-canary` era el único de los cuatro sin
# `orphanedResources`, así que la app del canary nunca se evaluaba y
# `{CMD_CHECK}` la contaba como "nada huérfano". Un bloque copiado
# tres veces se actualiza dos.
#
# Derivarlo cierra las dos cosas de una: el proyecto existe cuando
# existe el contrato, y los cuatro bloques son idénticos por
# construcción y no por disciplina.
#
# QUÉ NO SE DERIVA, y por qué se queda a mano:
#   aegis-bootstrap, aegis-platform  — son del sustrato, no de ninguna
#     organización. No salen de ningún contrato porque no hay contrato
#     del que salgan.
#   aegis-tenant-canary              — el canary es de la PLATAFORMA.
#     Vive en org-canary pero no tiene contrato: es la prueba de que el
#     camino del tenant funciona, así que no puede depender de él.
#   aegis-tenant-ecommerce           — heredado, anterior al generador.
#     Mismo criterio que tenants-heredados.yaml: mezclarlo acá haría que
#     la próxima corrida lo borrara en silencio.

def render_appprojects():
    """Un AppProject por organización QUE TIENE REPO.

    La condición no es "por cada contrato": es por cada contrato cuyas
    apps vengan de un repo propio. Una organización de pura
    infraestructura —una base y un bucket, como org-ejemplo en su etapa
    1— no tiene ninguna Application externa, y un proyecto sin
    `sourceRepos` no acota nada: es un objeto que no se usa, que es
    exactamente lo que I4 manda barrer.

    El día que esa organización declare `repo:`, el proyecto aparece en
    la misma corrida que su Application. Ese acoplamiento es el punto.
    """
    proyectos = []
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        repos = sorted(repos_de(c))
        if repos:
            proyectos.append((c["organizacion"], repos))

    partes = [markers.BANNER + f"""
# Un AppProject por CONTRATO que declara repo. Se rederiva en cada
# `{CMD_ORG_APPLY}`.
#
# Los proyectos del sustrato (aegis-bootstrap, aegis-platform) y los que
# no salen de un contrato (aegis-tenant-canary, aegis-tenant-ecommerce)
# viven a mano en appprojects.yaml, al lado. Mezclarlos acá haría que la
# próxima corrida los borrara en silencio.
#
# UN AppProject POR ORGANIZACIÓN, no uno compartido con varios destinos.
# La diferencia importa: con un solo proyecto que liste los tres
# namespaces, una app del ecommerce podría desplegarse en el namespace
# del portafolio con solo cambiar una línea de su propio repo. El
# proyecto ES la frontera, y una frontera con tres puertas abiertas no
# es una frontera.
#
# ESTOS NO LOS GESTIONA NINGUNA App, a propósito (W-06 / R1 camino B).
# Se aplican por kubectl antes que root: (a) evita la carrera
# AppProject-vs-Application dentro de un mismo sync, y (b) cierra el
# vector de escalar privilegios por una App que edite proyectos. Por eso
# viven fuera de k8s/argocd-apps/, que es el path del App-of-Apps."""]

    if not proyectos:
        partes.append("#\n# (ningún contrato declara repo todavía)")
        return "\n".join(partes) + "\n"

    for org, repos in proyectos:
        lista = "\n".join(f"    - {r}" for r in repos)
        partes.append(f"""\
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: aegis-tenant-{org}
  namespace: argocd
  labels: {{aegis.dev/part-of: aegis-platform}}
spec:
  description: apps de la organización {org} — SOLO su repo, SOLO org-{org}, CERO cluster-scoped
  # Los repos que declara el contrato: el de la organización y los que
  # cada servicio haya declarado por su cuenta. Enumerados, nunca '*'.
  sourceRepos:
{lista}
  destinations:
    - {{server: https://kubernetes.default.svc, namespace: org-{org}}}
  # EL fix de R1-B: deny-all cluster-scoped. Escribir en el repo de una
  # app ya no da acceso al cluster entero.
  clusterResourceWhitelist: []
  # Y dentro de su namespace, que no se auto-escale ni cambie sus
  # propios límites: esos los pone la plataforma (App org-{org}).
  namespaceResourceBlacklist:
    - {{group: "", kind: ResourceQuota}}
    - {{group: "", kind: LimitRange}}
    - {{group: rbac.authorization.k8s.io, kind: Role}}
    - {{group: rbac.authorization.k8s.io, kind: RoleBinding}}
    # Y NO puede escribir su propio ruteo (#54). Este es el que no es
    # obvio: los cuatro de arriba protegen a la organización de sí
    # misma, éste protege a LAS DEMÁS de ella.
    #
    # Un AppProject filtra por *kind*, jamás por el valor de un campo,
    # así que no hay forma de decir "IngressRoutes sí, pero solo con TU
    # Host". Mientras el inquilino pudiera crear una, podía reclamar el
    # hostname del vecino. MEDIDO el 2026-08-06: org-blog reclamó un
    # host, org-ejemplo reclamó EL MISMO, los dos admitidos sin una
    # queja, y traefik terminó sirviendo el del segundo. El dueño
    # legítimo no tenía defensa ni aviso.
    #
    # La única forma de acotarlo por kind es que el kind no le
    # pertenezca: el ruteo lo deriva la plataforma del contrato
    # (routes.yaml, App org-{org}) y acá se le quita la lapicera.
    - {{group: traefik.io, kind: IngressRoute}}
    # Y el Middleware por el MISMO motivo, agregado con #81/#90
    # (2026-08-13). El ruteo derivado engancha tres middlewares por
    # ruta —cabeceras, ritmo, cuerpo— que viven en el namespace del
    # inquilino. Sin esta línea, el inquilino podía declarar un
    # Middleware con el mismo nombre y contenido vacío: mismo nombre,
    # misma referencia desde la IngressRoute que él no controla, y el
    # rate-limit desaparecía sin que la ruta cambiara.
    #
    # Es exactamente la forma del robo de Host de arriba: no se roba el
    # recurso propio, se pisa el que otro referencia por nombre.
    - {{group: traefik.io, kind: Middleware}}
  # AVISAR de lo que sobra, sin borrarlo (A19 / #31).
  #
  # `prune` está omitido en toda la plataforma a propósito: quitar algo
  # de git NO lo quita del cluster. La decisión es correcta —un prune
  # mal disparado se lleva datos— pero deja un punto ciego: nadie se
  # entera de lo que quedó vivo. Ya pasó con NetworkPolicies borradas de
  # git que siguieron aplicándose durante días.
  #
  # `warn: true` cierra ese hueco sin agregar riesgo: ArgoCD marca los
  # huérfanos como condición de la app, y el operador decide. Detección,
  # no prevención, y se acepta como tal.
  orphanedResources:
    warn: true
    ignore:
      # Lo crea el kube-controller-manager en CADA namespace, no sale de
      # ningún git y nunca va a salir. Sin esta excepción el aviso
      # aparecería en toda organización para siempre, y un aviso
      # permanente apaga la señal igual que una ausencia — que es la
      # Enfermedad E y la razón de que este mecanismo exista.
      - group: ""
        kind: ConfigMap
        name: kube-root-ca.crt""")
    return "\n".join(partes) + "\n"


def aplicar_appprojects(escribir):
    nuevo = render_appprojects()
    print(f"\nproyectos  {gris}(k8s/bootstrap/appprojects-tenants.yaml){fin}")
    try:
        viejo = open(APPPROJECTS_K8S, encoding="utf-8").read()
    except FileNotFoundError:
        viejo = None
    if viejo == nuevo:
        print(f"  {gris}={fin} AppProjects de organización")
        return 0
    print(f"  {ama}~{fin} AppProjects de organización" if viejo
          else f"  {verde}+{fin} AppProjects de organización")
    if escribir:
        os.makedirs(os.path.dirname(APPPROJECTS_K8S), exist_ok=True)
        open(APPPROJECTS_K8S, "w", encoding="utf-8").write(nuevo)
        # No los gestiona ArgoCD (ver el encabezado del archivo), así que
        # nadie los va a aplicar solo. Decirlo acá y no en la
        # documentación: el paso que hay que acordarse es el paso que se
        # olvida, y el borde ya se pagó dos veces por eso.
        print(f"  {ama}!{fin} el proyecto no existe en el cluster hasta que corras esto:")
        print(f"    {gris}kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml{fin}")
        print(f"    {gris}(va ANTES de {CMD_SYNC_ROOT}: una Application cuyo{fin}")
        print(f"    {gris} proyecto no existe queda en 'project not found'){fin}")
    return 0


# ── el generator de argocd-secrets, derivado ──────────────────────────
#
# Mismo problema que garage-system, y descubierto igual: un archivo
# COMPARTIDO en el que había que acordarse de agregar una línea por
# organización. Las dos que estaban —portafolio y blog— se habían
# escrito a mano, y el modo de fallo fue peor que el de garage: no solo
# nadie las listaba automáticamente, sino que NADIE LAS CREABA. En una
# instancia nueva la age key es otra, todo lo que el init produce se
# recifra, y estas dos quedaban cifradas con una llave que ya no
# existe (#48).
#
# La credencial de repositorio es de la ORGANIZACIÓN aunque viva en el
# namespace de ArgoCD: sale de su `repo:` y desaparece con ella. Que
# estuviera en un archivo de plataforma es lo que hacía que `borrar`
# no la alcanzara.

def render_argocd_secretgen():
    # Los de PLATAFORMA, que no salen de ningún contrato. El comentario
    # de cada uno dice qué fase lo produce, porque esa es la información
    # que hace falta cuando algo no aparece.
    fijos = [
        ("secret-ops-stack-repo.enc.yaml",
         "fase 15 (tmb aplicado por pipe en fase 30 — KSOPS lo ADOPTA después)"),
        ("secret-github-webhook.enc.yaml", "fase 15 (HMAC — A27)"),
        # La deploy key del canario. Era la ÚLTIMA con permiso de
        # ESCRITURA, y lo tenía sólo para que el Image Updater pudiera
        # empujar su write-back. Retirado el componente (#59), pasa a
        # SOLO LECTURA, igual que las del blog y el portafolio (#49).
        ("secret-hello-aegis-repo.enc.yaml", "fase 15 (deploy key de LECTURA)"),
    ]
    # ACÁ ESTABA secret-regcred-image-updater.enc.yaml, retirado en #59
    # junto con el componente. Era la credencial con la que el updater
    # leía el registry para descubrir tags nuevos; sin updater, no hay
    # quién la use, y un secreto que nadie consume es superficie sin
    # contrapartida (I4).
    lineas = [
        *markers.MARCO,
        "# REGLA TEMPORAL (corrida #4, bug que frenó la fase 35): esta App",
        "# sincroniza en fase 35 — un entry cuyo .enc.yaml se genera en una fase",
        "# POSTERIOR rompe el build ENTERO de kustomize (es atómico) y NINGÚN",
        "# secret de la App se crea, ni los que sí existen en el repo.",
        "apiVersion: viaduct.ai/v1",
        "kind: ksops",
        "metadata:",
        "  name: argocd-secrets",
        "  annotations:",
        "    config.kubernetes.io/function: |",
        "      exec: {path: ksops}",
        "# LISTA EXPLÍCITA (A7): nada de globs. La diferencia con antes es que",
        "# esta lista la deriva el generador, no una persona.",
        "files:",
    ]
    for archivo, porque in fijos:
        lineas.append(f"  # {porque}")
        lineas.append(f"  - {archivo}")

    # Y una credencial de repositorio por cada repo de cada contrato.
    repos = []
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        repos += [f"secret-{n}-repo.enc.yaml" for n in repos_de(c).values()]
    if repos:
        lineas.append(
            "  # La deploy key con la que ArgoCD LEE el repo de cada organización.\n"
            f"  # Sale de su `repo:` y se crea con `{CMD_SECRET}`, que\n"
            "  # además imprime la mitad pública para registrarla en GitHub. Sin\n"
            "  # registrarla, la App queda en 'repository not accessible'.")
        lineas += [f"  - {r}" for r in sorted(repos)]
    return "\n".join(lineas) + "\n"


def aplicar_argocd(escribir):
    nuevo = render_argocd_secretgen()
    print(f"\ncredenciales  {gris}(k8s/base/platform/argocd-secrets/secret-generator.yaml){fin}")
    try:
        viejo = open(ARGOCD_SECRETGEN, encoding="utf-8").read()
    except FileNotFoundError:
        viejo = None
    if viejo == nuevo:
        print(f"  {gris}={fin} deploy keys de repositorio")
        return 0
    print(f"  {ama}~{fin} deploy keys de repositorio" if viejo
          else f"  {verde}+{fin} deploy keys de repositorio")
    if escribir:
        open(ARGOCD_SECRETGEN, "w", encoding="utf-8").write(nuevo)

    # I4: la credencial de una organización que ya no está SOBRA. No se
    # borra sola y se dice por qué: quitarla del repo NO revoca la deploy
    # key en GitHub, que es donde de verdad da acceso.
    esperados = set()
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        esperados |= {f"secret-{n}-repo.enc.yaml" for n in repos_de(c).values()}
    fijos_repo = {"secret-ops-stack-repo.enc.yaml", "secret-hello-aegis-repo.enc.yaml"}
    d = os.path.dirname(ARGOCD_SECRETGEN)
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if not (f.startswith("secret-") and f.endswith("-repo.enc.yaml")):
            continue
        if f in fijos_repo or f in esperados:
            continue
        print(f"  {rojo}-{fin} {f}  {ama}(credencial de una organización que ya no está){fin}")
        print(f"    {gris}Borrarla del repo NO revoca la deploy key: eso es\n"
              f"    `gh repo deploy-key delete` contra GitHub.{fin}")
        if escribir:
            os.remove(os.path.join(d, f))
    return 0


def orgs_con_bucket():
    """Las organizaciones que declararon `almacenamiento.bucket`, ordenadas.

    Una sola fuente para las TRES cosas que dependen de esa lista: los
    Jobs de aprovisionamiento, los espejos de credencial que el
    secret-generator tiene que listar, y si el kustomization incorpora
    o no aprovisionar.yaml. Calcularla tres veces es cómo se
    desincronizan.
    """
    orgs = []
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        if (c.get("almacenamiento") or {}).get("bucket"):
            orgs.append(c["organizacion"])
    return sorted(orgs)


# ── el CABLEADO de garage-system, derivado ────────────────────────────
#
# kustomization.yaml y secret-generator.yaml de garage-system estaban
# escritos a mano, y el generador escribía archivos DENTRO de ese
# directorio que ninguno de los dos referenciaba:
#
#   aprovisionar.yaml              -> no estaba en `resources`
#   secret-garage-<org>.enc.yaml   -> no estaba en `files`
#
# El síntoma de las dos era el peor posible: `aegis org aplicar` decía
# que todo salió bien, los archivos quedaban en git, y en el cluster no
# pasaba nada. Ningún error, en ningún lado. Es la Enfermedad E — una
# señal que no distingue "funcionó" de "no se evaluó".
#
# La cura no es acordarse de editar dos archivos más: es que el
# cableado SALGA de los contratos, como el borde y el ruteo. Un archivo
# generado que nadie lista es un archivo que no existe.
#
# Se mantiene la LISTA EXPLÍCITA (A7): sigue sin haber globs, solo que
# ahora la lista la escribe el generador en vez de una persona.

def render_garage_kustomization():
    hay_buckets = bool(orgs_con_bucket())
    recursos = ["bundle.yaml", "netpol.yaml"]
    if hay_buckets:
        # Condicional a propósito: kustomize FALLA si un `resources`
        # apunta a un archivo que no existe, y aprovisionar.yaml solo
        # existe cuando alguna organización pidió bucket.
        recursos.append("aprovisionar.yaml")
    lineas = [
        *markers.MARCO,
        "# Sale del conjunto de contratos: `aprovisionar.yaml` se lista solo",
        "# cuando alguna organización declaró `almacenamiento.bucket`, porque",
        "# kustomize falla si un recurso listado no existe.",
        "apiVersion: kustomize.config.k8s.io/v1beta1",
        "kind: Kustomization",
        "resources:",
    ]
    lineas += [f"  - {r}" for r in recursos]
    lineas += ["generators:", "  - secret-generator.yaml"]
    return "\n".join(lineas) + "\n"


def render_garage_secretgen():
    fijos = [
        ("secret-garage-credentials.enc.yaml",
         "rpc_secret y admin_token del Garage compartido. Los crea\n"
         f"  # `{CMD_SECRET}` si faltan, y NUNCA los regenera: rotarlos con\n"
         "  # el cluster arriba deja al nodo sin poder hablarse a sí mismo."),
        ("secret-regcred-internal.enc.yaml",
         "Credencial de lectura del registry interno, para pullear la imagen."),
    ]
    lineas = [
        *markers.MARCO,
        "apiVersion: viaduct.ai/v1",
        "kind: ksops",
        "metadata:",
        "  name: garage-system-secrets",
        "  annotations:",
        "    config.kubernetes.io/function: |",
        "      exec: {path: ksops}",
        "# LISTA EXPLÍCITA (A7): nada de globs. Un glob incorpora en silencio",
        "# cualquier .enc.yaml que caiga en el directorio. La diferencia con",
        "# antes es que esta lista la deriva el generador, no una persona.",
        "files:",
    ]
    for archivo, porque in fijos:
        lineas.append(f"  # {porque}")
        lineas.append(f"  - {archivo}")
    orgs = orgs_con_bucket()
    if orgs:
        lineas.append(
            "  # Espejo de la clave S3 de cada organización. El MISMO material\n"
            "  # que en su namespace: la app la consume allá, y el Job de\n"
            "  # aprovisionamiento la IMPORTA desde acá. Al revés —que el Job\n"
            "  # la generara— cada corrida daría una credencial distinta.")
        for org in orgs:
            lineas.append(f"  - secret-garage-{org}.enc.yaml")
    return "\n".join(lineas) + "\n"


def aplicar_garage(escribir):
    """El cableado de garage-system, derivado del conjunto de contratos."""
    rc = 0
    print(f"\ngarage   {gris}(k8s/base/garage-system/){fin}")
    for ruta, nuevo, que in (
            (GARAGE_KUSTOMIZATION, render_garage_kustomization(), "kustomization.yaml"),
            (GARAGE_SECRETGEN, render_garage_secretgen(), "secret-generator.yaml")):
        try:
            viejo = open(ruta, encoding="utf-8").read()
        except FileNotFoundError:
            viejo = None
        if viejo == nuevo:
            print(f"  {gris}={fin} {que}")
            continue
        print(f"  {ama}~{fin} {que}" if viejo else f"  {verde}+{fin} {que}")
        if escribir:
            os.makedirs(DIR_GARAGE, exist_ok=True)
            open(ruta, "w", encoding="utf-8").write(nuevo)

    # I4: el espejo de una organización que ya no existe SOBRA. Sin esto
    # queda una credencial S3 viva en git para una organización borrada
    # — pasó con `conbucket`, un contrato de prueba del 2026-08-04 cuyo
    # espejo sobrevivió al borrado y terminó commiteado.
    esperados = {f"secret-garage-{o}.enc.yaml" for o in orgs_con_bucket()}
    if os.path.isdir(DIR_GARAGE):
        for f in sorted(os.listdir(DIR_GARAGE)):
            if not (f.startswith("secret-garage-") and f.endswith(".enc.yaml")):
                continue
            if f == "secret-garage-credentials.enc.yaml" or f in esperados:
                continue
            print(f"  {rojo}-{fin} {f}  {ama}(espejo de una organización que ya no está){fin}")
            print(f"    {gris}Borrarlo del repo NO revoca la clave en Garage: eso es\n"
                  f"    `garage key delete` contra el almacén.{fin}")
            if escribir:
                os.remove(os.path.join(DIR_GARAGE, f))
    return rc


def render_aprovisionar():
    """Los Jobs que le dan a cada organización su bucket y su permiso.

    Corren en garage-system y no en el namespace de la organización
    porque necesitan el ADMIN TOKEN del almacenamiento: quien lo tenga
    puede darse acceso al bucket de cualquiera, así que no baja a un
    namespace de tenant. La clave de la organización sí está en los dos
    lados —la escribe `aegis-secret` con el mismo material— porque su
    app la consume y este Job la importa.
    """
    cat = yaml.safe_load(open(SERVICIOS, encoding="utf-8"))
    b = cat["bucket"]
    imagen = f"{cat['registro']}/{b['aprovisionador']['imagen']}@{b['aprovisionador']['digest']}"

    conBucket = orgs_con_bucket()
    if not conBucket:
        return None

    script = open(APROVISIONAR_JS, encoding="utf-8").read()
    sangrado = "\n".join("    " + l if l.strip() else "" for l in script.rstrip("\n").split("\n"))

    partes = [markers.BANNER + f"""
# Un Job por organización que declaró `almacenamiento.bucket`.
#
# El script es ai/aprovisionar-bucket.mjs, que vive como ARCHIVO y no
# embebido en el generador: así se puede correr a mano contra un Garage
# de prueba, que es como se lo verificó antes de escribir esto.
#
# CORRE COMO HOOK DE SYNC, no como recurso suelto. Un Job es inmutable:
# reaplicarlo con cualquier cambio falla. Con `hook-delete-policy:
# BeforeHookCreation` cada sync borra el anterior y crea el nuevo, y
# como el script es idempotente eso además REPARA — si alguien borra un
# bucket, el próximo sync lo recrea.
apiVersion: v1
kind: ConfigMap
metadata:
  name: aprovisionar-bucket
  namespace: garage-system
  labels: {{aegis.dev/component: garage}}
data:
  aprovisionar.mjs: |
{sangrado}"""]

    for org in conBucket:
        partes.append(f"""\
---
apiVersion: batch/v1
kind: Job
metadata:
  name: aprovisionar-bucket-{org}
  namespace: garage-system
  labels: {{aegis.dev/component: garage}}
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  # Tres intentos y se rinde. Un Job que reintenta para siempre convierte
  # un error de configuración en ruido de fondo.
  backoffLimit: 3
  template:
    metadata:
      labels:
        aegis.dev/component: garage
        # La etiqueta que le abre la NetworkPolicy hacia el puerto de
        # ADMIN. Se concede por POD y no por namespace justamente para
        # que la tenga este Job y no todo lo que corra al lado.
        aegis.dev/rol: aprovisionar-bucket
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile: {{type: RuntimeDefault}}
      containers:
        - name: aprovisionar
          # nodejs-distroless, ya espejada y firmada. Node hace HTTP sin
          # una sola dependencia: traer y firmar una imagen nueva solo
          # para hablar con una API sería un eslabón más en la cadena de
          # suministro a cambio de nada. Y sin shell, que es exactamente
          # lo que se quiere en un pod que maneja el admin token.
          image: {imagen}
          args: ["/app/aprovisionar.mjs"]
          env:
            - {{name: GARAGE_ADMIN, value: "{b['admin']}"}}
            - {{name: ORG, value: "{org}"}}
            - {{name: BUCKET, value: "{org}"}}
            - name: GARAGE_ADMIN_TOKEN
              valueFrom:
                secretKeyRef: {{name: garage-credentials, key: admin_token}}
            # El MISMO material que tiene la organización en su
            # namespace. Se importa, no se pide: si Garage generara la
            # clave, cada corrida daría una distinta y habría que
            # escribirla de vuelta a algún lado.
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef: {{name: garage-{org}, key: AWS_ACCESS_KEY_ID}}
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef: {{name: garage-{org}, key: AWS_SECRET_ACCESS_KEY}}
          volumeMounts:
            - {{name: script, mountPath: /app, readOnly: true}}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {{drop: [ALL]}}
            readOnlyRootFilesystem: true
          resources:
            requests: {{cpu: 20m, memory: 32Mi}}
            limits: {{cpu: 200m, memory: 128Mi}}
      volumes:
        - name: script
          configMap: {{name: aprovisionar-bucket}}""")
    return "\n".join(partes) + "\n"


def aplicar_aprovisionar(escribir):
    nuevo = render_aprovisionar()
    print(f"\nbuckets  {gris}(k8s/base/garage-system/aprovisionar.yaml){fin}")
    try:
        viejo = open(APROVISIONAR_K8S, encoding="utf-8").read()
    except FileNotFoundError:
        viejo = None
    if nuevo is None:
        if viejo is None:
            print(f"  {gris}={fin} ninguna organización pidió bucket")
            return 0
        # I4: lo que el conjunto de contratos ya no produce, sobra.
        print(f"  {rojo}-{fin} aprovisionar.yaml  {gris}(ya nadie pide bucket){fin}")
        if escribir:
            os.remove(APROVISIONAR_K8S)
        return 0
    if viejo == nuevo:
        print(f"  {gris}={fin} Jobs de aprovisionamiento")
        return 0
    print(f"  {ama}~{fin} Jobs de aprovisionamiento" if viejo
          else f"  {verde}+{fin} Jobs de aprovisionamiento")
    if escribir:
        os.makedirs(os.path.dirname(APROVISIONAR_K8S), exist_ok=True)
        open(APROVISIONAR_K8S, "w", encoding="utf-8").write(nuevo)
    return 0


# ── los jobs de Jenkins, derivados ────────────────────────────────────
#
# El hueco #2 del mapa de onboarding (caminos/design.md §2a): cada app
# nueva pedía copiar ~20 líneas de job-dsl a mano en el values de JCasC.
# El modo de fallo del olvido es el de siempre: el contrato está, el
# repo está, y ningún build corre jamás — sin nada rojo, porque un job
# que no existe no puede fallar.
#
# El bloque va DENTRO de values.yaml, entre marcas, y no en un
# configScript propio: JCasC corre con ErrorOnConflict (A30) y dos
# sources que declaren la key `jobs:` abortan el boot entero. Fuera de
# las marcas lo escrito a mano sobrevive: hello-aegis-mb es del canary
# (org-canary NO tiene contrato — es la prueba de que el camino del
# tenant funciona, así que no puede depender de él) y ai-gateway-mb es
# de la PLATAFORMA. Migran al bloque el día que su org tenga contrato,
# no antes (deuda anotada en el diseño §2a). Los tres que SÍ tenían
# contrato —portafolio, blog, ejemplo— migraron acá el 2026-08-19,
# verificando primero que el texto derivado reproducía el manual
# carácter por carácter.

MARCA_JOBS_INI = markers.MARCA_JOBS_INI
MARCA_JOBS_FIN = markers.MARCA_JOBS_FIN
# Sin re.S: `(?:.*\n)*?` come líneas enteras y no puede pasarse de la
# marca de cierre aunque el bloque esté vacío.
PATRON_BLOQUE_JOBS = markers.PATRON_BLOQUE_JOBS
# El plugin multibranch no habla URLs: habla owner/repository. Se
# aceptan las dos formas que puede traer un `repo:` (ssh y https) y se
# rechaza lo demás — un repo fuera de GitHub necesita otro branchSource,
# que es otra decisión, no una entrada más.
PATRON_REPO_GITHUB = re.compile(
    r"^(?:git@github\.com:|https://github\.com/)([^/]+)/([^/]+?)(?:\.git)?$")


def trabajos_de_jenkins():
    """(nombre, owner, repositorio) por cada repo de cada contrato.

    El nombre del job es el de su Application (repos_de): un repo, un
    job, una App — la MISMA clave en Jenkins y en ArgoCD, para que el
    log de un build y el estado de un despliegue se encuentren sin
    tabla de traducción. Orden alfabético estable: el diff de
    values.yaml no depende del filesystem (I1).
    """
    trabajos = []
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        for repo, nombre_app in repos_de(c).items():
            m = PATRON_REPO_GITHUB.match(repo)
            if not m:
                raise Invalido(
                    f"{nombre}: repo {repo!r} no es de GitHub.\n"
                    f"  El job multibranch se declara con owner/repository del plugin\n"
                    f"  github-branch-source; un repo de otro host necesita otro\n"
                    f"  branchSource — es otra decisión, no una entrada más acá.")
            trabajos.append((nombre_app, m.group(1), m.group(2)))
    return sorted(trabajos)


def render_bloque_jobs():
    lineas = [MARCA_JOBS_INI]
    lineas.append(f"""\
          # Un job multibranch por repo declarado en un contrato de
          # orgs/. El nombre del job es el de su Application: un repo,
          # un job, una App — la misma clave en Jenkins y en ArgoCD.
          # Este bloque se rederiva ENTERO en cada corrida de
          # {CMD_ORG}: lo que se edite entre las marcas no
          # sobrevive a la próxima.""")
    for n, owner, repo in trabajos_de_jenkins():
        lineas.append(f"""\
          - script: >
              multibranchPipelineJob('{n}-mb') {{
                displayName('{n} (multibranch)')
                branchSources {{
                  github {{
                    id('{n}-gh')
                    repoOwner('{owner}')
                    repository('{repo}')
                    scanCredentialsId('github-token')
                  }}
                }}
                orphanedItemStrategy {{
                  discardOldItems {{ numToKeep(10) }}
                }}
                configure {{ node ->
                  def traits = node / sources / data / 'jenkins.branch.BranchSource' / source / traits
                  traits << 'org.jenkinsci.plugins.github__branch__source.BranchDiscoveryTrait' {{
                    strategyId(1)
                  }}
                }}
              }}""")
    lineas.append(MARCA_JOBS_FIN)
    return "\n".join(lineas)


# ── la vigilancia de cada organización, derivada ──────────────────────
#
# Hasta el 2026-08-22 una organización nacía AISLADA y CIEGA: el
# contrato derivaba namespace, cuota, ruteo, netpols, secretos, jobs y
# firma — y ni un solo objetivo de vigilancia. Medido ese día: shop
# llevaba un día vivo y si su API hubiera empezado a devolver 500 a cada
# cliente, no se habría disparado nada. Ninguna alerta de la plataforma
# nombraba a una aplicación de inquilino.
#
# La causa es de fondo y está anotada en RUTA: TODO el vocabulario de
# los protocolos habla de TRANSICIONES (hecho/ya-estaba/no-evaluable, la
# frontera, plan/apply, los gates de cada fase). Nada hablaba de estado
# permanente. Se verificaba que algo se hubiera montado bien, jamás que
# siguiera funcionando.
#
# Esto deriva el objetivo; las REGLAS que lo consumen son genéricas y
# viven en rules/vmalert-rules.yaml (una regla para todos los
# inquilinos, no N copias). Por eso agregar una organización no agrega
# alertas: agrega un target, y las alertas que ya existen lo cubren.
#
# Se sondea el `dominio:` y NO los hostnames de plataforma: esos van
# detrás de Cloudflare Access y su 302 al login contaría como éxito —
# el error que el check 90 del init existe para prohibir.
MARCA_SONDAS_INI = markers.MARCA_SONDAS_INI
MARCA_SONDAS_FIN = markers.MARCA_SONDAS_FIN
PATRON_BLOQUE_SONDAS = markers.PATRON_BLOQUE_SONDAS


def sondas_de_inquilinos():
    """Un (organizacion, dominio) por contrato que declare algo público.

    Sin `dominio:` no hay nada que sondear desde afuera. Orden
    alfabético estable: el diff del values no depende del filesystem.
    """
    sondas = []
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        dom, org = c.get("dominio"), c.get("organizacion")
        if not dom or not org:
            continue
        # Sin ningún servicio `publico:` no hay camino que un cliente
        # pueda recorrer, y sondearlo daría 404 para siempre.
        if not any(s.get("publico") for s in (c.get("servicios") or [])):
            continue
        sondas.append((org, dom))
    return sorted(sondas)


def render_bloque_sondas():
    lineas = [MARCA_SONDAS_INI]
    lineas.append(f"""\
    # Un probe por organización con dominio y ruta pública. Mide el
    # camino COMPLETO que recorre un cliente: DNS, borde, túnel,
    # traefik, middlewares y la app. Todo lo demás mide piezas.
    # Este bloque se rederiva ENTERO en cada {CMD_ORG_APPLY}.""")
    sondas = sondas_de_inquilinos()
    if not sondas:
        lineas.append("    # (ninguna organización declara dominio con ruta pública)")
    for org, dom in sondas:
        lineas.append(f"""\
    - job_name: sitio-{org}
      metrics_path: /probe
      params: {{module: [sitio_publico]}}
      static_configs:
        - targets: ["https://{dom}/"]
          labels: {{organizacion: {org}}}
      relabel_configs:
        - source_labels: [__address__]
          target_label: __param_target
        - source_labels: [__param_target]
          regex: "https?://([^/]+).*"
          target_label: instance
          replacement: "$1"
        - target_label: __address__
          replacement: blackbox.observability.svc:9115""")
    lineas.append(MARCA_SONDAS_FIN)
    return "\n".join(lineas)


def aplicar_sondas(escribir):
    texto = open(VMAGENT_VALUES, encoding="utf-8").read()
    if not PATRON_BLOQUE_SONDAS.search(texto):
        raise Invalido(
            f"no encontré las marcas del bloque derivado en {VMAGENT_VALUES}.\n"
            f"  Tienen que existir estas dos líneas (con su sangría de 4\n"
            f"  espacios, dentro de scrape_configs):\n"
            f"{MARCA_SONDAS_INI}\n"
            f"{MARCA_SONDAS_FIN}\n"
            f"  Sin ellas no hay forma de saber qué es derivado y qué es de una\n"
            f"  persona, y pisar a ciegas es peor que no generar.")
    sondas = sondas_de_inquilinos()
    nuevo = PATRON_BLOQUE_SONDAS.sub(lambda _: render_bloque_sondas(), texto, count=1)
    print(f"\nsondas  {gris}(k8s/base/observability/vmagent/values.yaml){fin}")
    if nuevo == texto:
        print(f"  {gris}={fin} sondas de tenant  {gris}{len(sondas)} sonda(s){fin}")
        return 0
    print(f"  {ama}~{fin} sondas de tenant -> "
          f"{', '.join(o for o, _ in sondas) or '(ninguna)'}")
    if escribir:
        open(VMAGENT_VALUES, "w", encoding="utf-8").write(nuevo)
        # El mismo aviso que el borde y que jenkins, por la misma razón:
        # el paso que hay que acordarse es el que se olvida.
        print(f"  {gris}la sonda no existe hasta commitear + sincronizar:\n"
              f"  vmagent recarga su config cuando el values llega al cluster{fin}")
    return 0


def aplicar_jenkins(escribir):
    texto = open(JENKINS_VALUES, encoding="utf-8").read()
    if not PATRON_BLOQUE_JOBS.search(texto):
        raise Invalido(
            f"no encontré las marcas del bloque derivado en {JENKINS_VALUES}.\n"
            f"  Tienen que existir estas dos líneas (con su sangría de 10\n"
            f"  espacios, dentro del configScript aegis-jobs):\n"
            f"{MARCA_JOBS_INI}\n"
            f"{MARCA_JOBS_FIN}\n"
            f"  Sin ellas no hay forma de saber qué es derivado y qué es de una\n"
            f"  persona, y pisar a ciegas es peor que no generar.")
    nombres = [n for n, _, _ in trabajos_de_jenkins()]
    nuevo = PATRON_BLOQUE_JOBS.sub(lambda _: render_bloque_jobs(), texto, count=1)
    print(f"\njenkins  {gris}(k8s/base/platform/jenkins/values.yaml){fin}")
    if nuevo == texto:
        print(f"  {gris}={fin} jobs de tenant  {gris}{len(nombres)} job(s){fin}")
        return 0
    print(f"  {ama}~{fin} jobs de tenant -> {', '.join(f'{n}-mb' for n in nombres) or '(ninguno)'}")
    if escribir:
        open(JENKINS_VALUES, "w", encoding="utf-8").write(nuevo)
        # El values es un artefacto GitOps: el job no existe en Jenkins
        # hasta que este cambio llegue al cluster y el sidecar de JCasC
        # recargue el seed. Decirlo acá y no en la documentación, por la
        # misma razón que el borde: el paso que hay que acordarse es el
        # que se olvida.
        print(f"  {gris}el job no existe en Jenkins hasta commitear + sincronizar:\n"
              f"  JCasC recarga el seed solo cuando el values llega al cluster{fin}")
    return 0


# ── el Jenkinsfile de cada servicio, instanciado ──────────────────────
#
# El template canónico (docs/protocols/templates/Jenkinsfile.app) tiene
# UN solo CHANGEME en 452 líneas: el nombre de la imagen. Hacer que una
# persona copie el archivo entero para editar esa línea invita al error
# contrario — editar lo que NO es suyo: los pins, los limits y los
# secretos son contrato con la plataforma (lo dice su propia cabecera).
#
# Se instancia al staging .aegis-app/<org>/<svc>/ y NO a un directorio
# versionado: el destino de este archivo es el repo DE LA APP (caminos
# §3 — `aegis-app aplicar` lo empuja solo a un repo vacío), y versionar
# acá una copia de lo que vive allá sería repetir el error histórico de
# platform/: dos copias, y la que nadie mira se pudre. Por eso
# .aegis-app/ está en el .gitignore.
#
# SIN guard I3 acá, a propósito: una vez pusheado, la verdad del
# Jenkinsfile vive en el repo de la app; el staging es material
# regenerable y rederivar lo pisa sin preguntar.

def servicios_a_instanciar():
    """(org, servicio) por cada servicio que se CONSTRUYE desde un repo.

    Un `postgres` no aparece: lo provee la plataforma y no tiene
    pipeline. La condición es tener imagen que compilar Y un repo de
    dónde sacarla — el propio o el de la organización.
    """
    out = []
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        for s in c.get("servicios") or []:
            if s.get("tipo") in TIPOS_CON_IMAGEN and (s.get("repo") or c.get("repo")):
                out.append((c["organizacion"], s["nombre"]))
    return sorted(out)


def aplicar_jenkinsfiles(escribir):
    tpl = open(JENKINSFILE_TPL, encoding="utf-8").read()
    # Si el template pierde su CHANGEME —o le crece otro— este replace
    # dejaría de instanciar lo que se cree que instancia. Mejor gritar
    # acá que descubrirlo en el primer build con la imagen equivocada.
    marcadores = tpl.count("'CHANGEME-app'")
    if marcadores != 1:
        raise Invalido(
            f"{JENKINSFILE_TPL}: esperaba exactamente UN 'CHANGEME-app' y hay "
            f"{marcadores}.\n"
            f"  Esta derivación instancia ese único marcador; si el template\n"
            f"  cambió de forma, hay que actualizar las dos cosas juntas.")
    print(f"\njenkinsfiles  {gris}(.aegis-app/ — staging, gitignorado){fin}")

    esperados = {}
    for org, svc in servicios_a_instanciar():
        # IMAGE = '<org>-<svc>' (caminos §2b): la convención de la
        # referencia viva (ejemplo-front, ejemplo-api). El blog y el
        # portafolio son anteriores y publican 'blog'/'portafolio' para
        # su front; sus repos no se tocan desde acá — el staging jamás
        # se empuja sobre historia ajena.
        esperados[os.path.join(org, svc, "Jenkinsfile")] = \
            tpl.replace("'CHANGEME-app'", f"'{org}-{svc}'")

    for rel in sorted(esperados):
        camino = os.path.join(DIR_STAGING, rel)
        nuevo = esperados[rel]
        try:
            viejo = open(camino, encoding="utf-8").read()
        except FileNotFoundError:
            viejo = None
        if viejo == nuevo:
            print(f"  {gris}={fin} {rel}")
            continue
        print(f"  {ama}~{fin} {rel}" if viejo is not None else f"  {verde}+{fin} {rel}")
        if escribir:
            os.makedirs(os.path.dirname(camino), exist_ok=True)
            open(camino, "w", encoding="utf-8").write(nuevo)

    # I4: el staging de un servicio que ya no deriva de ningún contrato
    # SOBRA. Se quita SOLO el Jenkinsfile —que es lo que esta derivación
    # produce— y los directorios que queden vacíos: el día que el
    # staging tenga también esqueletos de `aegis-app nueva`, esos no son
    # nuestros para borrar.
    if os.path.isdir(DIR_STAGING):
        for org in sorted(os.listdir(DIR_STAGING)):
            d_org = os.path.join(DIR_STAGING, org)
            if not os.path.isdir(d_org):
                continue
            for svc in sorted(os.listdir(d_org)):
                jf = os.path.join(d_org, svc, "Jenkinsfile")
                rel = os.path.join(org, svc, "Jenkinsfile")
                if not os.path.exists(jf) or rel in esperados:
                    continue
                print(f"  {rojo}-{fin} {rel}  {gris}(ya no lo produce ningún contrato){fin}")
                if escribir:
                    os.remove(jf)
                    for d in (os.path.join(d_org, svc), d_org):
                        if os.path.isdir(d) and not os.listdir(d):
                            os.rmdir(d)
    return 0


def aplicar_tenants(escribir):
    nuevo = render_tenants()
    print(f"\ntenants  {gris}(k8s/argocd-apps/tenants.yaml){fin}")
    try:
        viejo = open(TENANTS_K8S, encoding="utf-8").read()
    except FileNotFoundError:
        viejo = None
    if viejo == nuevo:
        print(f"  {gris}={fin} Applications de organización")
        return 0
    print(f"  {ama}~{fin} Applications de organización" if viejo
          else f"  {verde}+{fin} Applications de organización")
    if escribir:
        open(TENANTS_K8S, "w", encoding="utf-8").write(nuevo)
        print(f"  {gris}root no tiene automated: para que exista, "
              f"{CMD_SYNC_ROOT}{fin}")
    return 0


def orgs_con_ai():
    """Las organizaciones cuyo contrato declara `ai:`, ordenadas.

    Se le pregunta al CONTRATO y no al árbol: el contrato es el que
    PROMETE, y una promesa que la instancia no puede cumplir es
    justamente lo que hay que ver.
    """
    orgs = []
    for nombre in sorted(os.listdir(DIR_ORGS)):
        if not nombre.endswith((".yaml", ".yml")):
            continue
        c = yaml.safe_load(open(os.path.join(DIR_ORGS, nombre), encoding="utf-8")) or {}
        if c.get("ai"):
            orgs.append(c["organizacion"])
    return sorted(orgs)


def _sin_subsistema_ai(que):
    """Los TRES desenlaces del subsistema AI, dichos en voz alta.

    Reproducido el 2026-08-24 sobre la semilla de v3: un contrato
    perfectamente válido SIN bloque `ai:` hacía morir a `aegis org
    apply` con un traceback —

        FileNotFoundError: .../k8s/base/ai-system/routes.yaml

    — y no al principio, sino DESPUÉS de haber escrito los seis
    manifiestos de la organización. O sea que dejaba el árbol a medias
    y la culpa parecía del contrato.

    La causa era que las dos etapas de AI corrían SIEMPRE, sin
    preguntar si el subsistema estaba. Con la decisión de que AI no
    viaja en la semilla (solo sus documentos y su protocolo), «no
    está» dejó de ser una anomalía y pasó a ser la forma NORMAL de un
    árbol recién clonado.

    Pero no se puede saltar en silencio, y acá está la única línea que
    importa: una ausencia no es un caso legítimo hasta que se
    distingue de un error (regla 3 del diseño de la CLI).

      · sin subsistema y sin contratos que lo pidan  -> NO APLICA (0)
      · sin subsistema y CON contratos que lo piden  -> FALLA (1)
      · con subsistema                               -> seguir (None)

    El segundo caso es el que vale el helper: un contrato que declara
    `ai:` en una instancia sin AI no es un detalle de generación, es
    una promesa que nadie va a poder cumplir, y el momento de verla es
    ahora y no cuando el front pida una traducción.
    """
    if os.path.isdir(DIR_AI):
        return None
    print(f"\n{que}  {gris}(k8s/base/ai-system/){fin}")
    piden = orgs_con_ai()
    if piden:
        print(f"  {rojo}\u2717{fin} {len(piden)} contrato(s) declaran `ai:` "
              f"({', '.join(piden)}) y este \u00e1rbol no tiene el subsistema AI")
        print(f"  {gris}el contrato promete algo que la instancia no puede dar: "
              f"o se trae el subsistema, o sale `ai:` del contrato{fin}")
        return 1
    print(f"  {gris}\u25cb NO APLICA: el subsistema AI no est\u00e1 en este "
          f"\u00e1rbol y ning\u00fan contrato lo pide{fin}")
    return 0


def aplicar_ruteo(escribir):
    rc = _sin_subsistema_ai("ruteo")
    if rc is not None:
        return rc
    nuevo = render_ruteo_k8s()
    print(f"\nruteo  {gris}(k8s/base/ai-system/routes.yaml){fin}")
    try:
        viejo = open(RUTEO_K8S, encoding="utf-8").read()
    except FileNotFoundError:
        viejo = None
    if viejo == nuevo:
        print(f"  {gris}={fin} ai-ruteo")
        return 0
    print(f"  {ama}~{fin} ai-ruteo" if viejo else f"  {verde}+{fin} ai-ruteo")
    if escribir:
        open(RUTEO_K8S, "w", encoding="utf-8").write(nuevo)
    return 0


def main():
    p = argparse.ArgumentParser(prog=cli.cmd("org"), description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    for nombre, ayuda in (("plan", "muestra qué cambiaría, sin escribir"),
                          ("apply", "escribe los manifiestos"),
                          ("validate", "solo valida el contrato")):
        s = sub.add_parser(nombre, help=ayuda)
        s.add_argument("contratos", nargs="+")
    sub.add_parser("edge", help="deriva public_hostnames de todos los contratos")
    sub.add_parser("routes", help="deriva el ConfigMap ai-ruteo de todos los contratos")
    # `plan-borrar` primero, y con ese nombre: el orden del help importa
    # cuando el comando de al lado destruye cosas.
    for nombre, ayuda in (("plan-delete", "muestra qué borraría, sin tocar nada"),
                          ("delete", "quita de git y DICE qué retirar del cluster")):
        s = sub.add_parser(nombre, help=ayuda)
        s.add_argument("organizaciones", nargs="+", metavar="ORGANIZACION")
    m = sub.add_parser("migrate", help="lleva un contrato a una versión nueva")
    m.add_argument("contratos", nargs="+")
    # `--to` y no `--a`: la fricción 2 de A5 en su forma más chica —
    # una preposición suelta no dice a qué se refiere.
    m.add_argument("--to", type=int, required=True, metavar="VERSION",
                   dest="version_destino")
    a = p.parse_args()

    if a.cmd == "edge":
        try:
            return aplicar_borde(escribir=True)
        except Invalido as e:
            print(f"{rojo}✗{fin} {e}", file=sys.stderr)
            return 1

    if a.cmd == "routes":
        try:
            return aplicar_ruteo(escribir=True)
        except Invalido as e:
            print(f"{rojo}✗{fin} {e}", file=sys.stderr)
            return 1

    if a.cmd == "migrate":
        return migrar(a.contratos, a.version_destino)

    if a.cmd in ("delete", "plan-delete"):
        rc = 0
        for nombre in a.organizaciones:
            try:
                rc |= borrar(nombre, escribir=(a.cmd == "delete"))
            except Invalido as e:
                print(f"{rojo}✗ {nombre}{fin}\n  {e}", file=sys.stderr)
                rc = 1
        # Rederivar SIEMPRE, también al borrar: el hostname y el plan de
        # la organización que se fue tienen que desaparecer en la misma
        # corrida. Si quedaran, el borde seguiría creando su CNAME y el
        # gateway seguiría conociendo un tenant que ya no existe.
        if rc == 0:
            for etapa, fn in (("borde", aplicar_borde), ("ruteo", aplicar_ruteo),
         ("registro-ai", aplicar_registro_ai),
                              ("proyectos", aplicar_appprojects),
                              ("credenciales", aplicar_argocd),
                              ("tenants", aplicar_tenants),
                              ("buckets", aplicar_aprovisionar),
                              ("garage", aplicar_garage),
                              ("jenkins", aplicar_jenkins),
                              ("sondas", aplicar_sondas),
                              ("jenkinsfiles", aplicar_jenkinsfiles)):
                try:
                    rc |= fn(escribir=(a.cmd == "delete"))
                except Invalido as e:
                    print(f"{rojo}✗ {etapa}{fin}\n  {e}", file=sys.stderr)
                    rc = 1
        return rc

    rc = 0
    for ruta in a.contratos:
        try:
            if a.cmd == "validate":
                planes = yaml.safe_load(open(PLANES, encoding="utf-8"))
                validar(yaml.safe_load(open(ruta, encoding="utf-8")), planes)
                print(f"{verde}✓{fin} {ruta}")
            else:
                rc |= aplicar(ruta, escribir=(a.cmd == "apply"))
        except Invalido as e:
            print(f"{rojo}✗ {ruta}{fin}\n  {e}", file=sys.stderr)
            rc = 1
        except FileNotFoundError as e:
            print(f"{rojo}✗{fin} no existe: {e.filename}", file=sys.stderr)
            rc = 1

    # El borde y el ruteo SIEMPRE, después de las organizaciones. Van acá
    # y no como comandos aparte que hay que acordarse de correr:
    # acordarse es exactamente lo que falló las dos veces anteriores.
    #
    # Los dos derivan de TODOS los contratos, no del que se acaba de
    # tocar: dar de alta una organización cambia el mapa tenant->plan
    # entero, y ese archivo tiene que quedar consistente en la misma
    # corrida o el gateway arranca con una organización que no conoce.
    if a.cmd in ("plan", "apply") and rc == 0:
        for etapa, fn in (("borde", aplicar_borde), ("ruteo", aplicar_ruteo),
         ("registro-ai", aplicar_registro_ai),
                          ("proyectos", aplicar_appprojects),
                          ("credenciales", aplicar_argocd),
                          ("tenants", aplicar_tenants),
                          ("buckets", aplicar_aprovisionar),
                          ("garage", aplicar_garage),
                          ("jenkins", aplicar_jenkins),
                          ("sondas", aplicar_sondas),
                          ("jenkinsfiles", aplicar_jenkinsfiles)):
            try:
                rc |= fn(escribir=(a.cmd == "apply"))
            except Invalido as e:
                print(f"{rojo}✗ {etapa}{fin}\n  {e}", file=sys.stderr)
                rc = 1
    return rc

