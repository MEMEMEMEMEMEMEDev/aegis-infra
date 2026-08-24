// write-digest.mjs — fija las imágenes del overlay POR DIGEST.
//
// Uso:  node ci/write-digest.mjs <imagen>=<digest> [<imagen>=<digest> ...]
//
// POR QUÉ POR DIGEST Y NO POR TAG. Kyverno reescribe la imagen
// agregándole el digest verificado al admitir el pod. Con un TAG en git,
// lo desplegado y lo deseado difieren SIEMPRE, y para que ArgoCD no
// quede OutOfSync eterno había que ignorar el campo `image` — lo que
// APAGABA el auto-sync: si la única diferencia es la imagen y la imagen
// está ignorada, ArgoCD no ve nada que hacer y nada se despliega.
// Medido el 2026-08-03: 4 syncs en 8 días, todos por cambios
// estructurales, ninguno por una imagen nueva.
//
// Con el digest en git la mutación de Kyverno es un no-op (verificado
// por admisión: entrada idéntica a salida), no hay deriva, no hace falta
// ignorar nada, y el auto-sync vuelve.
//
// Es un archivo y no un heredoc dentro del Jenkinsfile a propósito: un
// heredoc indentado no termina, y el `sh '''...'''` de Groovy pelea con
// las comillas del script. Acá además se puede probar sin CI.
import { readFileSync, writeFileSync } from 'node:fs'

const ARCHIVO = process.env.OVERLAY ?? 'k8s/overlays/dev/kustomization.yaml'

const porImagen = new Map()
for (const arg of process.argv.slice(2)) {
  const i = arg.indexOf('=')
  if (i < 0) {
    console.error(`argumento sin '=': ${arg}`)
    process.exit(2)
  }
  const nombre = arg.slice(0, i)
  const digest = arg.slice(i + 1)
  // Un digest vacío o mal formado escribiría basura en git y el pod
  // quedaría en ImagePullBackOff. Se corta acá.
  if (!/^sha256:[0-9a-f]{64}$/.test(digest)) {
    console.error(`digest inválido para ${nombre}: ${JSON.stringify(digest)}`)
    process.exit(2)
  }
  porImagen.set(nombre, digest)
}
if (porImagen.size === 0) {
  console.error('nada que escribir')
  process.exit(2)
}

const lineas = readFileSync(ARCHIVO, 'utf8').split('\n')
const escritas = new Set()
let esperando = null

const salida = lineas.map((linea) => {
  const m = linea.match(/^(\s*)-\s*name:\s*(\S+)\s*$/)
  if (m) {
    esperando = porImagen.has(m[2]) ? m[2] : null
    return linea
  }
  // Se reemplaza la línea que SIGUE al `name:` que matcheó. Sirve tanto
  // para `newTag:` (primer despliegue) como para `digest:` (los
  // siguientes), así que correrlo dos veces no cambia nada.
  if (esperando && /^\s*(newTag|digest):/.test(linea)) {
    const sangria = linea.match(/^\s*/)[0]
    const nueva = `${sangria}digest: ${porImagen.get(esperando)}`
    escritas.add(esperando)
    esperando = null
    return nueva
  }
  return linea
})

// Si una imagen no aparece en el overlay, el despliegue quedaría con la
// versión vieja SIN QUE NADIE AVISE. Es exactamente la clase de fallo
// silencioso que este cambio existe para eliminar, así que se corta.
const faltan = [...porImagen.keys()].filter((n) => !escritas.has(n))
if (faltan.length) {
  console.error(`no encontré estas imágenes en ${ARCHIVO}:`)
  for (const n of faltan) console.error(`  - ${n}`)
  process.exit(1)
}

writeFileSync(ARCHIVO, salida.join('\n'))
for (const [n, d] of porImagen) console.log(`  ${n} -> ${d}`)
