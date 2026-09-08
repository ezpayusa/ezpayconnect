#!/usr/bin/env node
// ============================================================================================
// RECREAR LOS FIXTURES PERMANENTES DEL HARNESS COMERCIAL — 8-sep-2026
// ============================================================================================
// QUE ES Y POR QUE EXISTE
// ------------------------
// El harness (`tests/rls/probes_escritura.sql`) tiene un fixture PERMANENTE en produccion: tres
// cuentas comerciales de Guatemala con una jerarquia exacta, sobre las que se apoyan ~12 fixtures
// y decenas de probes. La limpieza de datos QA del 8-sep las borro y 23 probes se pusieron rojas.
//
// La correccion tiene dos mitades:
//   1. El harness dejo de clavar los uuid y ahora resuelve los tres sujetos POR EMAIL
//      (CO_FX_fixture_comercial). Un uuid lo asigna Auth y cambia en cada alta; el email es estable.
//   2. Este script recrea las tres cuentas POR EL CAMINO REAL, con esos mismos emails.
// Con las dos, borrar y recrear el fixture deja de romper el harness: los ids nuevos se resuelven
// solos.
//
// PAIS: GUATEMALA, REAL. No es el pais DEMO (ZZ) y no se le parece. Estas cuentas no son datos de
// demostracion: son el ANDAMIO del harness, y viven en GT porque las probes miden aislamiento entre
// GT y HN con datos de GT. El gate de abajo lo hace explicito y ABORTA si el pais resuelto fuera
// el DEMO — el error simetrico al de `seed-demo.mjs`, que aborta si NO lo es.
//
// EMAILS @ezpayconnect.com, NO @demo.invalid. Es deliberado y va contra la decision que tomamos
// para el seed DEMO: el harness los busca por estos strings exactos, asi que cambiarlos romperia lo
// mismo que este script viene a arreglar. Son cuentas de andamiaje que no reciben correo porque
// nada les manda nada; si algun dia se les mandara, hay que revisar esto.
//
// LO QUE NO HACE: ni jornadas, ni visitas, ni prospectos, ni tarjeta publica. Estas tres cuentas son
// fixtures y no tienen actividad propia — todo lo que el harness necesita lo siembra el, dentro de
// su BEGIN...ROLLBACK. Sembrarles actividad aca dejaria datos reales en GT que nadie pidio.
//
// IDEMPOTENTE: si una cuenta ya existe se saltea y se recupera su id; `guardar_asesor_perfil` hace
// UPSERT; `asignar_supervisor` se llama siempre para dejar la jerarquia en la forma exacta. Correrlo
// dos veces no duplica ni cambia nada.
//
// CREDENCIALES: solo del entorno, nunca de un archivo.
//   FIXTURES_ADMIN_EMAIL / FIXTURES_ADMIN_PASSWORD  → un super_admin real (crea las cuentas)
//   FIXTURES_QA_PASSWORD                            → la clave de las tres cuentas QA
// Son PROPIAS y no se comparten con `seed-demo.mjs`: cuentas distintas, en un pais distinto, con
// un proposito distinto. Reusar la del seed ataria dos cosas que no tienen por que moverse juntas.
//
// Uso:
//   node scripts/recrear-fixtures-harness-comercial.mjs                            # DRY-RUN
//   node scripts/recrear-fixtures-harness-comercial.mjs --ejecutar-en-produccion   # crea
// ============================================================================================
import { createClient } from '@supabase/supabase-js'
import { readFileSync, existsSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..')

// ============================================================================================
// .env.local — SOLO la URL y la anon key. Mismo criterio que `seed-demo.mjs`.
// ============================================================================================
// Las dos son publicas por diseno: viajan en cada request del navegador y estan en el bundle que
// sirve Vercel, asi que leerlas de un archivo local no expone nada nuevo.
//
// LAS DOS CREDENCIALES DE ESTE SCRIPT NO SE LEEN DE NINGUN ARCHIVO. Si se pudieran, el camino
// comodo seria escribirlas en `.env.local`, que esta ignorado HOY por una linea (`*.local`) que
// alguien puede cambiar, en una maquina que se respalda y se clona. Tener que exportarlas a mano ES
// la medida. Quien venga a "simplificar" esto cargando el archivo entero esta borrando la
// distincion.
const DEL_ARCHIVO = ['VITE_SUPABASE_URL', 'SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY', 'SUPABASE_ANON_KEY']

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
const PAIS_CODIGO = 'GT'
const ESCRIBIR = process.argv.includes('--ejecutar-en-produccion')

const URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL
const ANON = process.env.VITE_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY
const ADMIN_EMAIL = process.env.FIXTURES_ADMIN_EMAIL
const ADMIN_PASS = process.env.FIXTURES_ADMIN_PASSWORD
const QA_PASS = process.env.FIXTURES_QA_PASSWORD

// `crear-empleado` pide `rol_id`, no el nombre. Medidos contra la tabla `roles` el 7-sep-2026.
// Se VERIFICAN al arrancar contra el catalogo, cuando es legible: un id de rol equivocado crearia
// tres cuentas con el rol que no es, y el CHECK `comercial_requiere_pais` no lo atajaria.
const ROL_ID = {
  supervisor_comercial: '82874384-c078-4403-aa4e-0f738412b61c',
  asesor_comercial: 'ccc8abcd-ac62-4dcc-a90d-ea9728af768c',
}

// LOS TRES EMAILS SON EL CONTRATO CON EL HARNESS. `CO_FX_fixture_comercial` los busca literalmente;
// cambiar uno rompe el fixture y ~12 fixtures mas que cuelgan de el.
const CUENTAS = [
  { k: 'sup', email: 'supervisor.qa@ezpayconnect.com', nombre: 'QA Supervisor Comercial', rol: 'supervisor_comercial' },
  { k: 'ase1', email: 'asesor1.qa@ezpayconnect.com', nombre: 'QA Asesor Comercial 1', rol: 'asesor_comercial' },
  { k: 'ase2', email: 'asesor2.qa@ezpayconnect.com', nombre: 'QA Asesor Comercial 2', rol: 'asesor_comercial' },
]

// Los mismos codigos que antes: aparecen en los textos de veredicto de varias probes (P644, P646...).
const FICHAS = {
  sup: { codigo: 'QA-SUP-01', cargo: 'Supervisor Comercial QA', territorio: 'GT' },
  ase1: { codigo: 'QA-ASE-01', cargo: 'Asesor Comercial QA', territorio: 'GT' },
  ase2: { codigo: 'QA-ASE-02', cargo: 'Asesor Comercial QA', territorio: 'GT' },
}

// LA JERARQUIA EXACTA QUE EXIGE EL FIXTURE, y la razon de que sea asi:
//   ase1 CUELGA del supervisor  -> es el sujeto "dentro de la cartera"
//   ase2 SIN supervisor         -> es el sujeto "fuera de la cartera"
// Esas dos condiciones son literalmente las lineas 11385-11386 de probes_escritura.sql. Si ase2
// tuviera supervisor, el fixture entero se declara ausente aunque las tres cuentas existan.
const SUPERVISOR_DE = { ase1: 'sup', ase2: null }

// ---------------------------------------------------------------------------- utilidades
const log = (...a) => console.log(...a)
const paso = (t) => log(`\n─── ${t}`)
const hecho = []

function abortar(msg) {
  console.error(`\n✗ ABORTADO: ${msg}\n`)
  process.exit(1)
}

/** Envuelve toda escritura. En dry-run imprime y no toca nada. */
async function escribir(descripcion, fn, simulado = '(id-que-se-crearia)') {
  if (!ESCRIBIR) { log(`   [dry-run] ${descripcion}`); return simulado }
  const r = await fn()
  log(`   ✓ ${descripcion}`)
  return r
}

function clienteAnon() {
  return createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } })
}

async function comoUsuario(email, password) {
  const c = clienteAnon()
  const { data, error } = await c.auth.signInWithPassword({ email, password })
  if (error) abortar(`no se pudo iniciar sesión como ${email}: ${error.message}`)
  return { cliente: c, userId: data.user.id, token: data.session.access_token }
}

/**
 * Lanza si la RPC falla, y RECHAZA cualquier argumento `undefined` antes de llamar.
 *
 * Lo segundo no es paranoia: es lo que rompio el seed DEMO el 7-sep. `JSON.stringify` BORRA las
 * claves con valor `undefined`, asi que un id que no se resolvio no viaja como null — la clave
 * desaparece del cuerpo, PostgREST recibe menos parametros y contesta "no existe la funcion",
 * que apunta al lado equivocado. Acá el riesgo es el mismo: los ids salen de `crear-empleado`.
 */
async function rpc(cliente, nombre, args) {
  const sinValor = Object.entries(args ?? {}).filter(([, v]) => v === undefined).map(([k]) => k)
  if (sinValor.length) {
    throw new Error(`${nombre}: ${sinValor.join(', ')} llegó como undefined. JSON.stringify borraría `
      + 'esas claves y PostgREST respondería PGRST202 como si faltara la función.')
  }
  const { data, error } = await cliente.rpc(nombre, args)
  if (error) throw new Error(`${nombre}: ${error.code ?? ''} ${error.message}`)
  return data
}

// ============================================================================================
// FASE 0 — gate
// ============================================================================================
async function fase0() {
  paso('FASE 0 · Gate')

  for (const [k, v] of Object.entries({
    'VITE_SUPABASE_URL (o SUPABASE_URL)': URL,
    'VITE_SUPABASE_ANON_KEY (o SUPABASE_ANON_KEY)': ANON,
  })) {
    if (v) continue
    abortar(`falta ${k}.\n`
      + `  Puede salir del entorno o de ${ENV_LOCAL.archivo},\n`
      + `  que ${existsSync(ENV_LOCAL.archivo) ? 'existe pero no la trae' : 'no existe en esta máquina'}.`)
  }
  if (ENV_LOCAL.cargadas.length) log(`   .env.local: se tomaron ${ENV_LOCAL.cargadas.join(', ')}`)

  // Las credenciales SOLO son obligatorias para escribir. En dry-run son opcionales y el script
  // DICE lo que no pudo verificar, en vez de dar a entender que verifico.
  if (ESCRIBIR) {
    for (const [k, v] of Object.entries({
      FIXTURES_ADMIN_EMAIL: ADMIN_EMAIL, FIXTURES_ADMIN_PASSWORD: ADMIN_PASS,
      FIXTURES_QA_PASSWORD: QA_PASS,
    })) {
      if (v) continue
      abortar(`falta ${k} (obligatoria para escribir).\n`
        + '  Esta SÓLO sale del entorno: no se lee de ningún archivo, para que no quede escrita\n'
        + '  en disco. Exportala en la sesión y volvé a correr.')
    }
  }

  let admin = null
  if (ADMIN_EMAIL && ADMIN_PASS) {
    admin = await comoUsuario(ADMIN_EMAIL, ADMIN_PASS)
    log(`   sesión de super_admin: ${ADMIN_EMAIL}`)
  } else {
    log('   [!] sin FIXTURES_ADMIN_EMAIL/PASSWORD: no se puede verificar qué existe ya.')
    log('       El plan de abajo asume que no existe nada todavía.')
    admin = { cliente: clienteAnon(), userId: null, token: null, sinSesion: true }
  }

  // EL PAIS SE RESUELVE POR CODIGO, nunca por un uuid a mano.
  const { data: pais, error } = await admin.cliente
    .from('configuracion_pais').select('id,codigo,nombre,activo').eq('codigo', PAIS_CODIGO).maybeSingle()
  if (error) abortar(`no se pudo leer configuracion_pais: ${error.message}`)
  if (!pais) abortar(`no existe ningún país con código ${PAIS_CODIGO}`)

  // GATE SIMETRICO AL DEL SEED: aquel aborta si el país NO es el DEMO; este aborta si LO ES.
  // Los fixtures del harness viven en un país real y sembrarlos en ZZ los dejaría invisibles para
  // las probes, que miden aislamiento GT/HN.
  if (/DEMO/i.test(pais.nombre)) {
    abortar(`el país ${PAIS_CODIGO} se llama "${pais.nombre}" y contiene "DEMO". `
      + 'Estos son fixtures del harness y van en un país real, no en el de demostración.')
  }
  log(`   país destino: ${pais.codigo} · "${pais.nombre}" · ${pais.id}`)

  // Los rol_id están escritos como literales (medidos 7-sep). Se contrastan contra el catálogo
  // cuando es legible: un id equivocado crearía las tres cuentas con el rol que no es, y eso el
  // harness lo vería como "el fixture existe pero no sirve".
  const { data: roles } = await admin.cliente
    .from('roles').select('id,nombre').in('nombre', Object.keys(ROL_ID))
  if (Array.isArray(roles) && roles.length) {
    const malos = roles.filter((r) => ROL_ID[r.nombre] && ROL_ID[r.nombre] !== r.id)
    if (malos.length) {
      abortar('los rol_id escritos en este script NO coinciden con el catálogo: '
        + malos.map((r) => `${r.nombre} catálogo=${r.id} script=${ROL_ID[r.nombre]}`).join(' · '))
    }
    log(`   rol_id verificados contra el catálogo (${roles.length}/2)`)
  } else {
    log('   [!] la tabla `roles` no se pudo leer: los rol_id quedan sin verificar (medidos 7-sep).')
  }

  return { admin, pais }
}

// ============================================================================================
// FASE 1 — cuentas
// ============================================================================================
async function fase1(admin, pais) {
  paso('FASE 1 · Cuentas (edge crear-empleado, como super_admin)')

  const ids = {}

  if (admin.sinSesion) {
    log('   [!] sin sesión: no se puede verificar qué cuentas existen ya.')
    for (const c of CUENTAS) {
      log(`   [dry-run] crear ${c.rol} ${c.email} ("${c.nombre}") en ${pais.codigo}`)
      ids[c.k] = `(id-de-${c.k})`
      hecho.push({ fase: 'F1', que: c.email, id: ids[c.k], estado: 'se crearía' })
    }
    return ids
  }

  // Idempotencia. `listar-empleados` es la única lectura de perfiles ajenos que tiene el
  // super_admin: la RLS de `perfiles` sólo deja ver el propio (auth.uid() = id).
  const r = await fetch(`${URL}/functions/v1/listar-empleados`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${admin.token}`, apikey: ANON, 'Content-Type': 'application/json' },
    body: '{}',
  })
  const cuerpo = await r.json().catch(() => ({}))
  // Se verifica la forma en vez de caer a `[]`: un array vacío por un cambio de forma se ve
  // idéntico a "no hay nadie", y el script intentaría crear cuentas que ya existen.
  if (!r.ok || cuerpo?.success !== true || !Array.isArray(cuerpo?.data)) {
    throw new Error(`listar-empleados devolvió algo inesperado (HTTP ${r.status}): `
      + `${JSON.stringify(cuerpo).slice(0, 300)}`)
  }
  const existentes = new Map(
    cuerpo.data.filter((e) => e?.email && e?.id).map((e) => [String(e.email).toLowerCase(), e.id]),
  )
  log(`   empleados existentes leídos: ${existentes.size}`)

  for (const c of CUENTAS) {
    const ya = existentes.get(c.email.toLowerCase())
    if (ya) {
      ids[c.k] = ya
      log(`   = ya existe ${c.email} → ${ya}`)
      hecho.push({ fase: 'F1', que: c.email, id: ya, estado: 'ya existía' })
      continue
    }
    ids[c.k] = await escribir(
      `crear ${c.rol} ${c.email} ("${c.nombre}") en ${pais.codigo}`,
      async () => {
        const res = await fetch(`${URL}/functions/v1/crear-empleado`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${admin.token}`, apikey: ANON, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: c.email, password: QA_PASS, nombre_completo: c.nombre,
            rol_id: ROL_ID[c.rol], pais_id: pais.id, asignado_por: admin.userId,
          }),
        })
        const j = await res.json()
        if (!j?.success) throw new Error(`crear-empleado(${c.email}): ${j?.error ?? res.status}`)
        // La forma real es { success: true, data: { id, ... } }. Se verifica que sea un uuid: si
        // cambia, se corta ACÁ y no en la fase 2 con un error que apunta a otro lado.
        const id = j?.data?.id
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(id ?? ''))) {
          throw new Error(`crear-empleado(${c.email}): no devolvió un id usable. `
            + `Se esperaba data.id (uuid) y vino: ${JSON.stringify(j).slice(0, 300)}`)
        }
        return id
      },
      `(id-de-${c.k})`,
    )
    hecho.push({ fase: 'F1', que: c.email, id: ids[c.k], estado: 'creada' })
  }

  // Puerta entre fases: la 2 reparte estos ids a dos RPCs, y un undefined acá se convierte allá en
  // un parámetro que desaparece del cuerpo.
  const faltantes = CUENTAS.filter((c) => !ids[c.k]).map((c) => c.email)
  if (ESCRIBIR && faltantes.length) {
    throw new Error(`la fase 1 terminó sin id para: ${faltantes.join(', ')}`)
  }
  return ids
}

// ============================================================================================
// FASE 2 — fichas y jerarquía
// ============================================================================================
async function fase2(admin, pais, ids) {
  paso('FASE 2 · Fichas y jerarquía (guardar_asesor_perfil + asignar_supervisor)')

  for (const [k, f] of Object.entries(FICHAS)) {
    await escribir(
      `ficha ${f.codigo} (${f.cargo}) para ${ids[k]}`,
      () => rpc(admin.cliente, 'guardar_asesor_perfil', {
        p_asesor_id: ids[k], p_codigo_asesor: f.codigo, p_pais_id: pais.id,
        p_cargo: f.cargo, p_territorio: f.territorio, p_telefono: null,
        p_celular: null, p_fecha_ingreso: null, p_bio: null, p_activo: true,
      }),
    )
    hecho.push({ fase: 'F2', que: `ficha ${f.codigo}`, id: ids[k], estado: 'guardada (upsert)' })
  }

  // LA JERARQUÍA, EXPLÍCITA EN LOS DOS SENTIDOS. A ase2 se le asigna NULL a propósito y no se lo
  // deja "como venga": si la ficha ya existía con supervisor, el fixture se declararía ausente por
  // la línea 11386 aunque las tres cuentas estuvieran. Dejarlo implícito sería confiar en el estado
  // anterior, que es justo lo que rompió esto.
  for (const [k, sup] of Object.entries(SUPERVISOR_DE)) {
    const destino = sup ? ids[sup] : null
    await escribir(
      sup ? `${FICHAS[k].codigo} cuelga de ${FICHAS[sup].codigo}`
          : `${FICHAS[k].codigo} SIN supervisor (explícito, lo exige el fixture)`,
      () => rpc(admin.cliente, 'asignar_supervisor', { p_asesor_id: ids[k], p_supervisor_id: destino }),
    )
    hecho.push({ fase: 'F2', que: `supervisor de ${FICHAS[k].codigo}`,
                 id: destino ?? '(ninguno)', estado: 'asignado' })
  }
}

// ============================================================================================
// FASE 3 — control positivo: ¿el fixture quedó como el harness lo pide?
// ============================================================================================
async function fase3(admin, pais) {
  paso('FASE 3 · Control: la forma exacta que exige CO_FX_fixture_comercial')
  log('   Sin esto el script diría "listo" y el harness podría seguir rojo. Se comprueba lo mismo')
  log('   que comprueban las líneas 11385-11390 de probes_escritura.sql.')

  if (admin.sinSesion) {
    log('   [!] sin sesión: no se puede comprobar. Correlo con credenciales para verificarlo.')
    return true
  }

  // Se resuelve POR EMAIL, igual que ahora hace el harness: si esto encuentra las filas, el
  // fixture también las encuentra.
  const { data: perfiles, error: e1 } = await admin.cliente
    .from('perfiles').select('id,email,rol,pais_id')
    .in('email', CUENTAS.map((c) => c.email))
  if (e1) { log(`   [!] no se pudo leer perfiles: ${e1.message}`); return false }

  const porEmail = new Map((perfiles ?? []).map((p) => [p.email.toLowerCase(), p]))
  const { data: fichas, error: e2 } = await admin.cliente
    .from('asesores_perfil').select('id,codigo_asesor,supervisor_id,activo,pais_id')
    .in('id', (perfiles ?? []).map((p) => p.id))
  if (e2) { log(`   [!] no se pudo leer asesores_perfil: ${e2.message}`); return false }
  const porId = new Map((fichas ?? []).map((f) => [f.id, f]))

  const pSup = porEmail.get('supervisor.qa@ezpayconnect.com')
  const pA1 = porEmail.get('asesor1.qa@ezpayconnect.com')
  const pA2 = porEmail.get('asesor2.qa@ezpayconnect.com')

  const checks = [
    ['los 3 perfiles existen (por email)', !!(pSup && pA1 && pA2)],
    ['los 3 tienen ficha en asesores_perfil', !!(pSup && pA1 && pA2
       && porId.has(pSup.id) && porId.has(pA1.id) && porId.has(pA2.id))],
    ['QA-ASE-01 cuelga de QA-SUP-01', !!(pA1 && pSup && porId.get(pA1.id)?.supervisor_id === pSup.id)],
    ['QA-ASE-02 SIN supervisor', !!(pA2 && porId.get(pA2.id) && porId.get(pA2.id).supervisor_id === null)],
    [`los 3 están en ${pais.codigo}`, !!(pSup && pA1 && pA2
       && [pSup, pA1, pA2].every((p) => p.pais_id === pais.id))],
  ]

  let ok = true
  for (const [que, vale] of checks) {
    log(`   ${vale ? '✓' : '✗'} ${que}`)
    if (!vale) ok = false
  }
  if (pSup) log(`     supervisor.qa → ${pSup.id}`)
  if (pA1) log(`     asesor1.qa    → ${pA1.id}`)
  if (pA2) log(`     asesor2.qa    → ${pA2.id}`)
  return ok
}

// ============================================================================================
async function main() {
  log('='.repeat(92))
  log(ESCRIBIR
    ? '  FIXTURES DEL HARNESS — MODO ESCRITURA. Crea cuentas reales en Guatemala.'
    : '  FIXTURES DEL HARNESS — DRY-RUN. No se escribe nada. Usá --ejecutar-en-produccion.')
  log('='.repeat(92))

  const { admin, pais } = await fase0()
  const ids = await fase1(admin, pais)
  await fase2(admin, pais, ids)
  const ok = await fase3(admin, pais)

  paso('RESUMEN')
  for (const h of hecho) log(`   ${h.fase}  ${String(h.que).padEnd(34)} ${String(h.id).padEnd(38)} ${h.estado}`)

  if (ESCRIBIR) {
    log('\n   Los tres emails y sus ids (el harness los resuelve por email, no por id):')
    for (const c of CUENTAS) {
      const h = hecho.find((x) => x.fase === 'F1' && x.que === c.email)
      log(`     ${c.email.padEnd(34)} ${h?.id ?? '(sin id)'}`)
    }
    log(`\n   Contraseña de las tres: la de FIXTURES_QA_PASSWORD.`)
  }

  log(ok
    ? '\n✓ El fixture tiene la forma que CO_FX_fixture_comercial exige.'
    : '\n✗ El fixture NO tiene la forma esperada: el harness seguiría declarándolo ausente.')
  log(ESCRIBIR
    ? '  Siguiente paso: correr `npm run harness` y confirmar que las rojas del módulo comercial se van.\n'
    : '  Dry-run terminado. NO se escribió nada.\n')

  if (ESCRIBIR && !ok) process.exit(1)
}

main().catch((e) => abortar(e?.stack ?? String(e)))
