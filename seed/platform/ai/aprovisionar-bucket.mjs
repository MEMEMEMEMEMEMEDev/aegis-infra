// aprovisionar.mjs — le da a una organización su bucket y su permiso en
// el Garage compartido.
//
// IDEMPOTENTE Y SIN DEPENDENCIAS. Sin dependencias porque corre sobre
// nodejs-distroless, que ya está espejada y firmada: traer y firmar una
// imagen nueva solo para hablar HTTP sería un eslabón más en la cadena
// de suministro a cambio de nada.
//
// La CLAVE la genera aegis y este script la IMPORTA. Al revés —dejar
// que Garage la genere— reaplicar produciría una credencial distinta
// cada vez y habría que escribirla de vuelta a algún lado. Con el
// material en git (cifrado), correr esto dos veces no cambia nada, que
// es la regla I2 del protocolo.
const ADMIN  = process.env.GARAGE_ADMIN;
const TOKEN  = process.env.GARAGE_ADMIN_TOKEN;
const ORG    = process.env.ORG;
const BUCKET = process.env.BUCKET;
const KEY_ID = process.env.AWS_ACCESS_KEY_ID;
const KEY_SEC= process.env.AWS_SECRET_ACCESS_KEY;

for (const [k, v] of Object.entries({ADMIN, TOKEN, ORG, BUCKET, KEY_ID, KEY_SEC})) {
  if (!v) { console.error(`falta ${k}`); process.exit(2); }
}

// ── ESPERAR A QUE LA RED ESTÉ LISTA ───────────────────────────────
//
// Este Job corre como hook de sync y arranca a los pocos segundos de
// existir. Las NetworkPolicies que lo autorizan a hablarle al Garage
// las programa el CNI REACCIONANDO al pod, y esa programación no es
// instantánea: hay una ventana en la que el pod ya corre y su tráfico
// todavía se rechaza.
//
// MEDIDO el 2026-08-04, el primer aprovisionamiento real (org-ejemplo):
// los tres intentos del Job fallaron con ECONNREFUSED en 33 segundos, y
// una sonda idéntica lanzada después conectó al primer intento, en t+0s.
// La política estaba bien desde el principio; lo que faltaba era tiempo.
//
// Y el síntoma engaña: en k3s el CNI RECHAZA en vez de descartar, así
// que da ECONNREFUSED y no un timeout. "Connection refused" se lee como
// "el servicio está caído", que manda a mirar el Garage —donde no hay
// nada roto— en lugar de la red.
//
// Por eso el reintento vive ACÁ y no en el backoffLimit del Job:
// reintentar el pod entero vuelve a pagar el arranque cada vez y quema
// los tres intentos dentro de la misma ventana. El backoffLimit queda
// para lo que sí es un error.
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

async function conReintento(que, fn) {
  const LIMITE_MS = 180_000;
  const t0 = Date.now();
  let espera = 2000, intento = 0;
  for (;;) {
    intento++;
    try {
      return await fn();
    } catch (e) {
      // SOLO se reintentan los fallos de RED. Un 400 de Garage no es un
      // problema de conectividad y reintentarlo tres minutos solo
      // retrasa el error real; esos ni siquiera llegan acá, porque
      // fetch resuelve y el código de estado lo mira quien llama.
      const codigo = e.cause?.code || e.name || "";
      const transitorio = /ECONNREFUSED|ECONNRESET|EHOSTUNREACH|ENETUNREACH|ETIMEDOUT|EAI_AGAIN|TimeoutError|AbortError/.test(codigo);
      const transcurrido = Date.now() - t0;
      if (!transitorio || transcurrido > LIMITE_MS) {
        console.error(`${que}: ${codigo || e.message} tras ${Math.round(transcurrido / 1000)}s` +
                      (transitorio ? " — la red nunca se habilitó" : ""));
        throw e;
      }
      console.log(`${que}: ${codigo}, reintento ${intento} en ${espera / 1000}s ` +
                  `(t+${Math.round(transcurrido / 1000)}s)`);
      await dormir(espera);
      espera = Math.min(espera * 2, 15_000);
    }
  }
}

async function api(op, body) {
  const r = await conReintento(`POST ${op}`, () =>
    fetch(`${ADMIN}/v2/${op}`, {
      method: "POST",
      headers: {Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json"},
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    }));
  const txt = await r.text();
  return {ok: r.ok, status: r.status, txt};
}

// Los errores se distinguen por CONTENIDO y no solo por código: Garage
// responde 400 tanto para "ya existe" como para "pediste cualquier
// cosa", y tratarlos igual convertiría un error real en un éxito
// silencioso. Es exactamente la clase de guard que este proyecto ya
// tuvo que arreglar cuatro veces.
const yaExiste = (t) => /already exist|already in use|Key name conflict/i.test(t);

let r = await api("CreateBucket", {globalAlias: BUCKET});
if (r.ok)                console.log(`bucket ${BUCKET}: creado`);
else if (yaExiste(r.txt)) console.log(`bucket ${BUCKET}: ya existía`);
else { console.error(`CreateBucket ${r.status}: ${r.txt}`); process.exit(1); }

r = await api("ImportKey", {accessKeyId: KEY_ID, secretAccessKey: KEY_SEC, name: `org-${ORG}`});
if (r.ok)                 console.log(`clave de org-${ORG}: importada`);
else if (yaExiste(r.txt)) console.log(`clave de org-${ORG}: ya existía`);
else { console.error(`ImportKey ${r.status}: ${r.txt}`); process.exit(1); }

// El PERMISO se pide por ID de bucket, no por alias. El alias es un
// nombre legible que puede haber varios y cambiar; el id es el bucket.
// (Medido: AllowBucketKey con el alias responde 400 "Invalid bucket id:
// Invalid character 'p' at position 0", que es un mensaje honesto pero
// no obvio hasta que uno lo lee.)
const info = await conReintento("GET GetBucketInfo", () =>
  fetch(`${ADMIN}/v2/GetBucketInfo?globalAlias=${encodeURIComponent(BUCKET)}`,
    {headers: {Authorization: `Bearer ${TOKEN}`}, signal: AbortSignal.timeout(10_000)}));
if (!info.ok) { console.error(`GetBucketInfo ${info.status}: ${await info.text()}`); process.exit(1); }
const bucketId = (await info.json()).id;
if (!bucketId) { console.error("GetBucketInfo no devolvió id"); process.exit(1); }

// Permiso SOLO sobre su bucket. Sin owner: no puede borrar el bucket ni
// tocar los alias, que es lo que impide que una organización se lleve
// puesto su propio almacenamiento por accidente.
r = await api("AllowBucketKey", {
  bucketId, accessKeyId: KEY_ID,
  permissions: {read: true, write: true, owner: false},
});
if (!r.ok) { console.error(`AllowBucketKey ${r.status}: ${r.txt}`); process.exit(1); }
console.log(`permiso read+write de org-${ORG} sobre ${BUCKET}: ok`);
