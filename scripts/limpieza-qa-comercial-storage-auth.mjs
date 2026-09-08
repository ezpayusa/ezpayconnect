#!/usr/bin/env node
// ============================================================================================
// LIMPIEZA QA DEL MODULO COMERCIAL — storage y Auth (pendiente #7, 8-sep-2026)
// ============================================================================================
// SEGUNDA MITAD de la limpieza. La primera es
// `scripts/sql/limpieza-qa-comercial-2026-09-08.sql`, que borra las filas de `public`.
//
// EL ORDEN IMPORTA Y NO ES REVERSIBLE: **primero el SQL, despues este script**. Si se corriera al
// reves, `visita_adjuntos` quedaria apuntando a un binario que ya no existe y `perfiles` a cuentas
// de Auth borradas — y el SQL, ademas, fallaria: sus verificaciones previas exigen encontrar las
// filas que este script ya habria dejado sin respaldo.
//
// POR QUE ESTAS TRES COSAS NO SE HACEN DESDE SQL:
//   * `storage.objects` tiene un trigger `protect_objects_delete`, y borrar el registro sin borrar
//     el binario deja el archivo vivo en el bucket: ocupa espacio y sigue siendo descargable con
//     una URL firmada. La API de storage borra las dos cosas.
//   * `auth.users` no se toca con DELETE. Se borra con `auth.admin.deleteUser`, que es la unica
//     via que limpia tambien identidades, sesiones y refresh tokens. Un DELETE directo deja
//     residuos que despues nadie encuentra.
//
// ES IDEMPOTENTE. Si un objeto o un usuario ya no existe, lo REPORTA y sigue. Correrlo dos veces no
// falla: la segunda corrida dice "ya no estaba" en todo. Y cada paso es independiente de los otros
// — un error en el bucket no impide borrar las cuentas, y se informa al final sin abortar el resto.
//
// CREDENCIALES: solo del entorno.
//   SUPABASE_SERVICE_ROLE_KEY   → obligatoria para borrar (storage privado + admin de Auth)
//   VITE_SUPABASE_URL / SUPABASE_URL (o desde .env.local, ver abajo)
//
// Uso:
//   node scripts/limpieza-qa-comercial-storage-auth.mjs                            # DRY-RUN
//   node scripts/limpieza-qa-comercial-storage-auth.mjs --ejecutar-en-produccion   # borra
// ============================================================================================
import { createClient } from '@supabase/supabase-js'
import { readFileSync, existsSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..')

// ============================================================================================
// .env.local — SOLO la URL. Mismo criterio que `seed-demo.mjs`, y por la misma razon.
// ============================================================================================
// La URL del proyecto es publica por diseno: viaja en cada request del navegador y esta en el
// bundle que sirve Vercel, asi que leerla de un archivo local no expone nada nuevo.
//
// `SUPABASE_SERVICE_ROLE_KEY` **NO SE LEE DE NINGUN ARCHIVO**, aunque este ahi. Es la clave que
// saltea toda la RLS del sistema, y este script la usa para BORRAR cuentas y archivos. Si se
// pudiera tomar del `.env.local`, el camino comodo seria dejarla escrita — y ese archivo esta
// ignorado HOY por una linea (`*.local`) que alguien puede cambiar, en una maquina que se respalda
// y se clona. Tener que exportarla a mano ES la medida: no hay ningun archivo del que el script la
// saque "por si acaso", y exportarla es un acto deliberado antes de una operacion irreversible.
// Quien venga a "simplificar" esto cargando el `.env.local` entero esta borrando esa distincion.
const DEL_ARCHIVO = ['VITE_SUPABASE_URL', 'SUPABASE_URL']

function cargarEnvLocal() {
  const archivo = resolve(RAIZ, '.env.local')
  if (!existsSync(archivo)) return { archivo, cargadas: [] }
  const cargadas = []
  for (const linea of readFileSync(archivo, 'utf8').split(/\r?\n/)) {
    const t = linea.trim()
    if (!t || t.startsWith('#')) continue
    const i = t.indexOf('=')
    if (i <= 0) continue
    const clave = t.slice(0, i).trim()
    if (!DEL_ARCHIVO.includes(clave)) continue          // todo lo demas se ignora a proposito
    if (process.env[clave]) continue                    // el entorno gana
    let valor = t.slice(i + 1).trim()
    const c = valor[0]
    if ((c === '"' || c === "'") && valor.length > 1 && valor[valor.length - 1] === c) {
      valor = valor.slice(1, -1)
    }
    process.env[clave] = valor
    cargadas.push(clave)
  }
  return { archivo, cargadas }
}

const ENV_LOCAL = cargarEnvLocal()

// ---------------------------------------------------------------------------- configuracion
const BORRAR = process.argv.includes('--ejecutar-en-produccion')

const URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY

// Los ids y los paths, escritos uno por uno. Salen de dos recon de solo lectura del 8-sep; este
// script no descubre nada ni busca por patron.
const OBJETOS = [
  {
    bucket: 'visitas-comerciales',
    path: 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909/4fa6abe9-0fa6-46e3-91dc-6fc7b57d48db/2db14499-2464-4965-92f9-d2b613356ba5.jpg',
    que: 'adjunto de la visita 4fa6abe9 (evidencia QA)',
  },
  {
    bucket: 'tarjetas-asesor',
    path: '97c5d673-bd6c-416b-8970-921a78c92887/b1a005b5-ebd9-4782-9d5d-cfcf1f5e6384.png',
    que: 'foto de la tarjeta publica de QA-ASE-01',
  },
]

const CUENTAS = [
  { id: '97c5d673-bd6c-416b-8970-921a78c92887', que: 'QA-ASE-01' },
  { id: '97896ac3-1bd4-4e24-a9e0-e6c97ce07893', que: 'QA-ASE-02' },
  { id: '3d843fd1-695a-4958-9b57-b840b23994b3', que: 'QA-SUP-01' },
]

// ---------------------------------------------------------------------------- utilidades
const log = (...a) => console.log(...a)
const paso = (t) => log(`\n─── ${t}`)
const resultados = []   // { paso, que, estado, detalle }

function abortar(msg) {
  console.error(`\n✗ ABORTADO: ${msg}\n`)
  process.exit(1)
}

// ============================================================================================
async function main() {
  log('='.repeat(92))
  log(BORRAR
    ? '  LIMPIEZA QA — MODO BORRADO. Esto borra archivos y cuentas de PRODUCCION, sin vuelta atras.'
    : '  LIMPIEZA QA — DRY-RUN. No se borra nada. Usá --ejecutar-en-produccion para hacerlo de verdad.')
  log('='.repeat(92))
  log('\n  Este script corre DESPUES de scripts/sql/limpieza-qa-comercial-2026-09-08.sql.')
  log('  Si todavía no corriste ese SQL, cortá acá: el orden inverso deja datos inconsistentes.')

  if (ENV_LOCAL.cargadas.length) log(`\n  .env.local: se tomó ${ENV_LOCAL.cargadas.join(', ')}`)

  if (!URL) {
    abortar('falta VITE_SUPABASE_URL (o SUPABASE_URL).\n'
      + `  Puede salir del entorno o de ${ENV_LOCAL.archivo},\n`
      + `  que ${existsSync(ENV_LOCAL.archivo) ? 'existe pero no la trae' : 'no existe en esta máquina'}.`)
  }
  // En dry-run la clave es opcional: se puede ver el plan sin tenerla a mano. Sin ella no se
  // consulta nada, y el script lo DICE en vez de dar a entender que verificó.
  if (BORRAR && !SERVICE) {
    abortar('falta SUPABASE_SERVICE_ROLE_KEY (obligatoria para borrar).\n'
      + '  Esta SÓLO sale del entorno: no se lee de ningún archivo, para que no quede escrita\n'
      + '  en disco. Exportala en la sesión y volvé a correr.')
  }

  const admin = SERVICE
    ? createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } })
    : null
  if (!admin) {
    log('\n  [!] sin SUPABASE_SERVICE_ROLE_KEY: no se puede comprobar qué existe todavía.')
    log('      El plan de abajo asume que sigue todo en pie.')
  }

  // ------------------------------------------------------------------ a) y b) los dos objetos
  paso('PASO 1 · Objetos de storage')
  for (const o of OBJETOS) {
    const etiqueta = `${o.bucket}/${o.path.split('/').pop()} — ${o.que}`

    if (!BORRAR) {
      // En dry-run se MIRA si el objeto está, para que el plan diga la verdad sobre qué queda.
      let estado = 'se borraría (no verificado: sin clave de servicio)'
      if (admin) {
        const carpeta = o.path.slice(0, o.path.lastIndexOf('/'))
        const archivo = o.path.slice(o.path.lastIndexOf('/') + 1)
        const { data, error } = await admin.storage.from(o.bucket).list(carpeta, { search: archivo })
        estado = error ? `no se pudo comprobar: ${error.message}`
          : (data ?? []).some((f) => f.name === archivo) ? 'EXISTE → se borraría'
          : 'ya no existe → nada que hacer'
      }
      log(`   [dry-run] ${etiqueta}\n             ${estado}`)
      resultados.push({ paso: 'storage', que: etiqueta, estado })
      continue
    }

    const { data, error } = await admin.storage.from(o.bucket).remove([o.path])
    if (error) {
      // Un error de bucket NO corta el script: los pasos son independientes y las cuentas se
      // pueden borrar igual. Se informa al final.
      log(`   ✗ ${etiqueta}\n     error: ${error.message}`)
      resultados.push({ paso: 'storage', que: etiqueta, estado: `ERROR: ${error.message}` })
      continue
    }
    // `remove()` devuelve los objetos que efectivamente borró. Un array vacío significa que no
    // había nada — que es éxito para un script idempotente, no un fallo.
    const borro = Array.isArray(data) && data.length > 0
    log(`   ${borro ? '✓' : '='} ${etiqueta}\n     ${borro ? 'borrado' : 'ya no existía (idempotente)'}`)
    resultados.push({ paso: 'storage', que: etiqueta, estado: borro ? 'borrado' : 'ya no existía' })
  }

  // ------------------------------------------------------------------ c) las tres cuentas
  paso('PASO 2 · Cuentas de Auth (auth.admin.deleteUser)')
  log('   Nunca por DELETE de SQL: sólo esta vía limpia identidades, sesiones y refresh tokens.')
  for (const c of CUENTAS) {
    const etiqueta = `${c.que} · ${c.id}`

    if (!BORRAR) {
      let estado = 'se borraría (no verificado: sin clave de servicio)'
      if (admin) {
        const { data, error } = await admin.auth.admin.getUserById(c.id)
        estado = error ? (String(error.message).toLowerCase().includes('not found')
                            ? 'ya no existe → nada que hacer'
                            : `no se pudo comprobar: ${error.message}`)
          : data?.user ? `EXISTE (${data.user.email}) → se borraría`
          : 'ya no existe → nada que hacer'
      }
      log(`   [dry-run] ${etiqueta}\n             ${estado}`)
      resultados.push({ paso: 'auth', que: etiqueta, estado })
      continue
    }

    const { error } = await admin.auth.admin.deleteUser(c.id)
    if (error) {
      // "User not found" es idempotencia, no un fallo: la cuenta ya no está y eso es el objetivo.
      const yaNo = String(error.message ?? '').toLowerCase().includes('not found')
        || error.status === 404
      log(`   ${yaNo ? '=' : '✗'} ${etiqueta}\n     ${yaNo ? 'ya no existía (idempotente)' : 'error: ' + error.message}`)
      resultados.push({ paso: 'auth', que: etiqueta,
                        estado: yaNo ? 'ya no existía' : `ERROR: ${error.message}` })
      continue
    }
    log(`   ✓ ${etiqueta}\n     borrada`)
    resultados.push({ paso: 'auth', que: etiqueta, estado: 'borrada' })
  }

  // ------------------------------------------------------------------ resumen
  paso('RESUMEN')
  const anchoQue = Math.max(...resultados.map((r) => r.que.length))
  for (const r of resultados) {
    log(`   ${r.paso.padEnd(8)} ${r.que.padEnd(anchoQue)}  ${r.estado}`)
  }

  const errores = resultados.filter((r) => r.estado.startsWith('ERROR') || r.estado.startsWith('no se pudo'))
  const borrados = resultados.filter((r) => r.estado === 'borrado' || r.estado === 'borrada')
  const yaNoEstaban = resultados.filter((r) => r.estado === 'ya no existía')

  log(`\n   borrados: ${borrados.length} · ya no estaban: ${yaNoEstaban.length} · con error: ${errores.length}`)
  if (errores.length) {
    log('\n   ✗ QUEDARON ERRORES. Los pasos independientes SÍ se ejecutaron; revisá estos y volvé')
    log('     a correr el script: es idempotente, no va a duplicar ni romper lo que ya salió bien.')
    for (const e of errores) log(`     - ${e.que}: ${e.estado}`)
  }
  log(BORRAR
    ? '\n✓ Limpieza de storage y Auth terminada.\n'
    : '\n✓ Dry-run terminado. NO se borró nada.\n')

  // Un error de storage o de Auth no debe pasar desapercibido en CI ni en un pipe.
  if (BORRAR && errores.length) process.exit(1)
}

main().catch((e) => abortar(e?.stack ?? String(e)))
