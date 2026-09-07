#!/usr/bin/env node
// ============================================================================================
// SEED DEL PAÍS DEMO (D10)
// ============================================================================================
// ESTE SCRIPT ESCRIBE EN PRODUCCIÓN. No hay otra base. Todo lo de abajo está subordinado a dos
// cosas: que no pueda sembrar en un país que no sea el DEMO, y que correrlo dos veces no duplique.
//
// GATE DE SEGURIDAD (fase 0, antes de cualquier escritura):
//   1. El país se resuelve POR CÓDIGO ('ZZ'), nunca por un uuid hardcodeado. Un uuid pegado a mano
//      con un dígito cambiado puede ser Guatemala, y el error no se vería hasta tener 9 prospectos
//      falsos en un país real.
//   2. Se ABORTA si el nombre del país resuelto no contiene "DEMO". Ese es el cinturón sobre los
//      tirantes: si alguien renombra ZZ, o reusa el código para un país de verdad, el script se
//      planta en vez de sembrar.
//   3. DRY-RUN POR DEFECTO. Sin `--ejecutar-en-produccion` no se escribe nada: se imprime el plan.
//      El flag es largo y feo a propósito — no se teclea sin querer.
//
// IDEMPOTENCIA: antes de crear cada cosa se pregunta si ya está. Las cuentas por email, las fichas
// por asesor, los prospectos por nombre, las jornadas por (asesor, fecha) y las visitas por
// (prospecto, fecha). Correrlo dos veces no duplica nada.
//
// TODO POR EL CAMINO CANÓNICO: `crear-empleado` para las cuentas y las RPCs del módulo para el
// resto. Ni un INSERT directo. Sembrar a mano dejaría datos que ninguna regla de negocio revisó —
// que es exactamente lo que un seed de demo no debe tener, porque después se muestra como si fuera
// el producto funcionando.
//
// CREDENCIALES: sólo por variables de entorno. Nunca en el repo, ni acá, ni en un .env commiteado.
//   SEED_ADMIN_EMAIL / SEED_ADMIN_PASSWORD  → un super_admin real (crea las cuentas)
//   SEED_DEMO_PASSWORD                      → la clave común de las tres cuentas demo
//   VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY (o SUPABASE_URL / SUPABASE_ANON_KEY)
//
// Uso:
//   node scripts/seed-demo.mjs                            # DRY-RUN: dice qué haría
//   node scripts/seed-demo.mjs --ejecutar-en-produccion   # escribe
// ============================================================================================
import { createClient } from '@supabase/supabase-js'
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..')

// ---------------------------------------------------------------------------- configuración
const PAIS_CODIGO = 'ZZ'
const ESCRIBIR = process.argv.includes('--ejecutar-en-produccion')

const URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL
const ANON = process.env.VITE_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY
const ADMIN_EMAIL = process.env.SEED_ADMIN_EMAIL
const ADMIN_PASS = process.env.SEED_ADMIN_PASSWORD
const DEMO_PASS = process.env.SEED_DEMO_PASSWORD

// Roles, medidos contra la tabla `roles` (no adivinados): `crear-empleado` pide `rol_id`, no el
// nombre del rol.
const ROL_ID = {
  supervisor_comercial: '82874384-c078-4403-aa4e-0f738412b61c',
  asesor_comercial: 'ccc8abcd-ac62-4dcc-a90d-ea9728af768c',
}

// Punto base de las coordenadas. Todo el DEMO vive alrededor de acá.
const BASE = { lat: 14.5991, lng: -90.5069 }
// Medido para ZZ (que no tiene fila en config_visitas_pais y cae en los defaults):
// radio de check-in 150 m, precisión máxima 100 m.
const RADIO_M = 150
const PRECISION_OK = 25

// ~0.0008° de latitud ≈ 89 m: DENTRO del radio. ~0.0100° ≈ 1.1 km: FUERA.
const CERCA = 0.0008
const LEJOS = 0.0100

const SUF = '.demo@ezpayconnect.com'

// Nombres inequívocamente ficticios y con "(DEMO)" pegado: si alguna vez aparecen en una pantalla
// que no es la demo, se ve al instante que son datos sembrados.
const CUENTAS = [
  { k: 'sup', email: `valentina.rios${SUF}`, nombre: 'Valentina Ríos (DEMO)', rol: 'supervisor_comercial' },
  { k: 'a1', email: `mateo.alcazar${SUF}`, nombre: 'Mateo Alcázar (DEMO)', rol: 'asesor_comercial' },
  { k: 'a2', email: `camila.ferreyra${SUF}`, nombre: 'Camila Ferreyra (DEMO)', rol: 'asesor_comercial' },
]

const FICHAS = {
  sup: { codigo: 'ZZ-SUP-01', cargo: 'Supervisora Comercial', territorio: 'Región DEMO',
         telefono: '2200-0100', celular: '+502 5500-0100', ingreso: '2025-03-03' },
  a1: { codigo: 'ZZ-ASE-01', cargo: 'Asesor Comercial', territorio: 'Zona Norte DEMO',
        telefono: '2200-0101', celular: '+502 5500-0101', ingreso: '2025-06-16' },
  a2: { codigo: 'ZZ-ASE-02', cargo: 'Asesora Comercial', territorio: 'Zona Sur DEMO',
        telefono: '2200-0102', celular: '+502 5500-0102', ingreso: '2026-01-12' },
}

// Nueve prospectos, tipos variados del catálogo medido, repartidos entre los dos asesores.
// `dlat`/`dlng` son offsets sobre BASE: así las coordenadas quedan agrupadas y la ruta del día se
// ve como una ruta y no como puntos al azar en el mapa.
const PROSPECTOS = [
  { k: 'p1', de: 'a1', nombre: 'Farmacia Aurora DEMO', tipo: 'farmacia', dir: '5a Avenida 3-21, Zona Norte DEMO', dlat: 0.0008, dlng: 0.0002, estado: 'ganado' },
  { k: 'p2', de: 'a1', nombre: 'Cadena Salud Andina DEMO', tipo: 'cadena_farmacias', dir: 'Boulevard Central 44, DEMO', dlat: 0.0100, dlng: 0.0030, estado: 'negociacion' },
  { k: 'p3', de: 'a1', nombre: 'Laboratorio Vértice DEMO', tipo: 'laboratorio_clinico', dir: 'Calzada Poniente 12, DEMO', dlat: 0.0015, dlng: -0.0011, estado: 'demo' },
  { k: 'p4', de: 'a1', nombre: 'Clínica Los Cipreses DEMO', tipo: 'clinica', dir: '7a Calle 18-40, DEMO', dlat: -0.0021, dlng: 0.0018, estado: 'contactado' },
  { k: 'p5', de: 'a1', nombre: 'Distribuidora Meridiano DEMO', tipo: 'empresa_afin', dir: 'Km 9.5 Ruta DEMO', dlat: 0.0042, dlng: 0.0037, estado: 'perdido' },
  { k: 'p6', de: 'a2', nombre: 'Farmacia El Sauce DEMO', tipo: 'farmacia', dir: '2a Avenida Sur 8-11, DEMO', dlat: -0.0006, dlng: -0.0004, estado: 'ganado' },
  { k: 'p7', de: 'a2', nombre: 'Laboratorios Peñalba DEMO', tipo: 'laboratorio_farmaceutico', dir: 'Zona Industrial DEMO, bodega 7', dlat: -0.0033, dlng: -0.0029, estado: 'negociacion' },
  { k: 'p8', de: 'a2', nombre: 'Clínica San Telmo DEMO', tipo: 'clinica', dir: '14 Calle 2-55, Zona Sur DEMO', dlat: -0.0014, dlng: 0.0009, estado: 'contactado' },
  { k: 'p9', de: 'a2', nombre: 'Farmacia Del Puerto DEMO', tipo: 'farmacia', dir: 'Avenida del Puerto 301, DEMO', dlat: -0.0048, dlng: 0.0026, estado: 'nuevo' },
]

// El día. LAS DOS CLASES DE CHECK-IN están a propósito: uno DENTRO del radio (queda
// `checkin_verificado = true`) y uno FUERA (queda en false, con el motivo que arma la RPC). Se ven
// distinto en la UI, y sembrar sólo el caso feliz escondería la mitad del producto — justo la
// mitad que el supervisor necesita mirar.
const VISITAS_HOY = [
  { de: 'a1', p: 'p1', cerca: true, resultado: 'cerro_acuerdo', resumen: 'Cerró acuerdo para el plan Pro. Firma la semana próxima.', compromisos: 'Enviar contrato el lunes.' },
  { de: 'a1', p: 'p2', cerca: false, resultado: 'requiere_seguimiento', resumen: 'Reunión en la casa matriz, lejos del punto registrado del prospecto.', compromisos: 'Agendar demo con el comité.' },
  { de: 'a2', p: 'p6', cerca: true, resultado: 'interesado', resumen: 'Interesada en el módulo de recetas. Pide propuesta escrita.', compromisos: 'Mandar propuesta.' },
]

// Visitas FUTURAS, sólo planificadas: la agenda tiene que verse con algo por delante.
const VISITAS_FUTURAS = [
  { de: 'a1', p: 'p3', enDias: 1, hora: '09:30' },
  { de: 'a1', p: 'p4', enDias: 2, hora: '11:00' },
  { de: 'a2', p: 'p7', enDias: 1, hora: '15:00' },
  { de: 'a2', p: 'p8', enDias: 3, hora: null },
]

// Uno deja la jornada ABIERTA y el otro la cierra: los dos estados se ven en la pantalla del
// supervisor, y "en curso" es el que más se mira en la vida real.
const CIERRA_JORNADA = { a1: false, a2: true }

// ---------------------------------------------------------------------------- utilidades
const log = (...a) => console.log(...a)
const paso = (t) => log(`\n─── ${t}`)
const hecho = [] // para el reporte final

function fechaISO(offsetDias = 0) {
  const d = new Date()
  d.setDate(d.getDate() + offsetDias)
  return d.toISOString().slice(0, 10)
}

function abortar(msg) {
  console.error(`\n✗ ABORTADO: ${msg}\n`)
  process.exit(1)
}

/** Envuelve toda escritura. En dry-run imprime y devuelve un id simulado; nunca toca la base. */
async function escribir(descripcion, fn, idSimulado = '(id-que-se-crearia)') {
  if (!ESCRIBIR) { log(`   [dry-run] ${descripcion}`); return idSimulado }
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

/** Lanza si la RPC falla: un seed que sigue después de un error deja datos a medias. */
async function rpc(cliente, nombre, args) {
  const { data, error } = await cliente.rpc(nombre, args)
  if (error) throw new Error(`${nombre}: ${error.code ?? ''} ${error.message}`)
  return data
}

// ============================================================================================
// FASE 0 — el gate
// ============================================================================================
async function fase0() {
  paso('FASE 0 · Gate de seguridad')

  // La URL y la anon key hacen falta SIEMPRE: sin ellas ni el gate se puede evaluar.
  for (const [k, v] of Object.entries({
    'VITE_SUPABASE_URL (o SUPABASE_URL)': URL,
    'VITE_SUPABASE_ANON_KEY (o SUPABASE_ANON_KEY)': ANON,
  })) if (!v) abortar(`falta la variable de entorno ${k}`)

  // Las credenciales SÓLO son obligatorias para escribir. En dry-run son opcionales: el gate se
  // puede evaluar con `anon` —`configuracion_pais` es legible sin sesión— y sin ellas igual se
  // imprime el plan completo. Lo único que se pierde son las consultas de IDEMPOTENCIA, que sí
  // necesitan sesión; cuando falten, el dry-run lo DICE en vez de dar a entender que verificó.
  if (ESCRIBIR) {
    for (const [k, v] of Object.entries({
      SEED_ADMIN_EMAIL: ADMIN_EMAIL, SEED_ADMIN_PASSWORD: ADMIN_PASS, SEED_DEMO_PASSWORD: DEMO_PASS,
    })) if (!v) abortar(`falta la variable de entorno ${k} (obligatoria para escribir)`)
  }

  let admin = null
  if (ADMIN_EMAIL && ADMIN_PASS) {
    admin = await comoUsuario(ADMIN_EMAIL, ADMIN_PASS)
    log(`   sesión de super_admin: ${ADMIN_EMAIL}`)
  } else {
    log('   [!] sin SEED_ADMIN_EMAIL/SEED_ADMIN_PASSWORD: el gate se evalúa como anon y las')
    log('       verificaciones de idempotencia NO se corren. El plan de abajo asume que no existe')
    log('       nada todavía; correlo con credenciales para saber qué está ya sembrado.')
    admin = { cliente: clienteAnon(), userId: null, token: null, sinSesion: true }
  }

  // EL PAÍS SE RESUELVE POR CÓDIGO. Un uuid a mano puede ser otro país.
  const { data: pais, error } = await admin.cliente
    .from('configuracion_pais').select('id,codigo,nombre,activo').eq('codigo', PAIS_CODIGO).maybeSingle()
  if (error) abortar(`no se pudo leer configuracion_pais: ${error.message}`)
  if (!pais) abortar(`no existe ningún país con código ${PAIS_CODIGO}`)

  // EL CINTURÓN. Si el nombre no dice DEMO, este script no tiene nada que hacer acá.
  if (!/DEMO/i.test(pais.nombre)) {
    abortar(`el país ${PAIS_CODIGO} se llama "${pais.nombre}" y NO contiene "DEMO". `
      + 'Este script sólo siembra en el país de demostración.')
  }
  log(`   país destino: ${pais.codigo} · "${pais.nombre}" · ${pais.id}`)
  log(`   activo: ${pais.activo}`)
  return { admin, pais }
}

// ============================================================================================
// FASE 1 — cuentas
// ============================================================================================
async function fase1(admin, pais) {
  paso('FASE 1 · Cuentas (edge crear-empleado, como super_admin)')

  // Idempotencia: `listar-empleados` es la única lectura de perfiles ajenos que tiene el
  // super_admin — la RLS de `perfiles` sólo deja ver el propio (auth.uid() = id).
  if (admin.sinSesion) {
    log('   [!] sin sesión: no se puede verificar qué cuentas existen ya (listar-empleados exige')
    log('       super_admin, y la RLS de `perfiles` sólo deja ver el propio perfil).')
    const idsSim = {}
    for (const c of CUENTAS) {
      log(`   [dry-run] crear ${c.rol} ${c.email} ("${c.nombre}") en ${pais.codigo}`)
      idsSim[c.k] = `(id-de-${c.k})`
      hecho.push({ fase: 'F1', que: `cuenta ${c.email}`, id: idsSim[c.k], nuevo: true })
    }
    return idsSim
  }

  const r = await fetch(`${URL}/functions/v1/listar-empleados`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${admin.token}`, apikey: ANON, 'Content-Type': 'application/json' },
    body: '{}',
  })
  const cuerpo = await r.json().catch(() => ({}))
  const existentes = new Map(
    (cuerpo?.empleados ?? cuerpo?.data ?? []).map((e) => [String(e.email).toLowerCase(), e.id]),
  )
  log(`   empleados existentes leídos: ${existentes.size}`)

  const ids = {}
  for (const c of CUENTAS) {
    const ya = existentes.get(c.email.toLowerCase())
    if (ya) { ids[c.k] = ya; log(`   = ya existe ${c.email} → ${ya}`); hecho.push({ fase: 'F1', que: `cuenta ${c.email}`, id: ya, nuevo: false }); continue }

    ids[c.k] = await escribir(
      `crear ${c.rol} ${c.email} ("${c.nombre}") en ${pais.codigo}`,
      async () => {
        const res = await fetch(`${URL}/functions/v1/crear-empleado`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${admin.token}`, apikey: ANON, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: c.email, password: DEMO_PASS, nombre_completo: c.nombre,
            rol_id: ROL_ID[c.rol], pais_id: pais.id, asignado_por: admin.userId,
          }),
        })
        const j = await res.json()
        if (!j?.success) throw new Error(`crear-empleado(${c.email}): ${j?.error ?? res.status}`)
        return j.user_id ?? j.id ?? j.user?.id
      },
      `(id-de-${c.k})`,
    )
    hecho.push({ fase: 'F1', que: `cuenta ${c.email}`, id: ids[c.k], nuevo: true })
  }
  return ids
}

// ============================================================================================
// FASE 2 — fichas
// ============================================================================================
async function fase2(admin, pais, ids) {
  paso('FASE 2 · Fichas de asesor (guardar_asesor_perfil + asignar_supervisor)')

  // `guardar_asesor_perfil` hace UPSERT, así que re-correrlo no duplica: reescribe la misma ficha
  // con los mismos valores. Igual se informa si ya estaba, para que el reporte sea honesto.
  let conFicha = new Set()
  if (admin.sinSesion) {
    log('   [!] sin sesión: no se verifica qué fichas existen ya.')
  } else {
    const { data: yaFichas } = await admin.cliente
      .from('asesores_perfil').select('id,codigo_asesor').eq('pais_id', pais.id)
    conFicha = new Set((yaFichas ?? []).map((f) => f.id))
  }

  for (const [k, f] of Object.entries(FICHAS)) {
    const nuevo = !conFicha.has(ids[k])
    await escribir(
      `${nuevo ? 'crear' : 'actualizar'} ficha ${f.codigo} (${f.cargo}, ${f.territorio}) para ${ids[k]}`,
      () => rpc(admin.cliente, 'guardar_asesor_perfil', {
        p_asesor_id: ids[k], p_codigo_asesor: f.codigo, p_pais_id: pais.id,
        p_cargo: f.cargo, p_territorio: f.territorio, p_telefono: f.telefono,
        p_celular: f.celular, p_fecha_ingreso: f.ingreso, p_bio: null, p_activo: true,
      }),
    )
    hecho.push({ fase: 'F2', que: `ficha ${f.codigo}`, id: ids[k], nuevo })
  }

  for (const k of ['a1', 'a2']) {
    await escribir(
      `colgar ${FICHAS[k].codigo} del supervisor ${FICHAS.sup.codigo}`,
      () => rpc(admin.cliente, 'asignar_supervisor', { p_asesor_id: ids[k], p_supervisor_id: ids.sup }),
    )
  }
}

// ============================================================================================
// FASE 3 — prospectos
// ============================================================================================
async function fase3(admin, pais, ids) {
  paso('FASE 3 · Prospectos (crear_prospecto, con coordenadas)')

  let porNombre = new Map()
  if (admin.sinSesion) {
    log('   [!] sin sesión: no se verifica qué prospectos existen ya.')
  } else {
    const { data: ya } = await admin.cliente
      .from('prospectos').select('id,nombre').eq('pais_id', pais.id)
    porNombre = new Map((ya ?? []).map((p) => [p.nombre, p.id]))
  }

  const pids = {}
  for (const p of PROSPECTOS) {
    if (porNombre.has(p.nombre)) {
      pids[p.k] = porNombre.get(p.nombre)
      log(`   = ya existe "${p.nombre}" → ${pids[p.k]}`)
      hecho.push({ fase: 'F3', que: `prospecto ${p.nombre}`, id: pids[p.k], nuevo: false })
      continue
    }
    const lat = (BASE.lat + p.dlat).toFixed(6)
    const lng = (BASE.lng + p.dlng).toFixed(6)
    pids[p.k] = await escribir(
      `crear prospecto "${p.nombre}" [${p.tipo}] de ${FICHAS[p.de].codigo} en ${lat},${lng}`,
      () => rpc(admin.cliente, 'crear_prospecto', {
        p_nombre: p.nombre, p_tipo: p.tipo, p_asesor_id: ids[p.de],
        p_direccion: p.dir, p_lat: Number(lat), p_lng: Number(lng),
        p_notas: 'Prospecto de demostración. No es un cliente real.',
      }),
      `(id-de-${p.k})`,
    )
    hecho.push({ fase: 'F3', que: `prospecto ${p.nombre}`, id: pids[p.k], nuevo: true })
  }
  return pids
}

// ============================================================================================
// FASE 4 — el día, cada asesor con SU credencial
// ============================================================================================
async function fase4(pais, ids, pids) {
  paso('FASE 4 · La jornada (autenticándose como CADA asesor)')
  log('   Las visitas las hace el ASESOR, no el super_admin: `checkin_visita_comercial` exige')
  log('   `v.asesor_id = auth.uid()`, así que sembrarlas de otro modo sería imposible o falso.')

  const hoy = fechaISO(0)

  for (const k of ['a1', 'a2']) {
    const cuenta = CUENTAS.find((c) => c.k === k)
    log(`\n   ${FICHAS[k].codigo} · ${cuenta.email}`)

    let ases = null
    if (ESCRIBIR) ases = await comoUsuario(cuenta.email, DEMO_PASS)

    // --- jornada ---
    await escribir(
      `abrir jornada de ${hoy} en ${BASE.lat},${BASE.lng}`,
      () => rpc(ases.cliente, 'abrir_jornada', { p_lat: BASE.lat, p_lng: BASE.lng, p_precision_m: PRECISION_OK }),
      `(jornada-${k})`,
    )

    // --- visitas de hoy: planificar → check-in → checkout → informe ---
    for (const v of VISITAS_HOY.filter((x) => x.de === k)) {
      const pros = PROSPECTOS.find((p) => p.k === v.p)
      const dlat = v.cerca ? CERCA : LEJOS
      // El asesor se para CERCA o LEJOS del punto del prospecto. La distancia la calcula la RPC.
      const lat = Number((BASE.lat + pros.dlat + (v.cerca ? 0 : LEJOS)).toFixed(6))
      const lng = Number((BASE.lng + pros.dlng).toFixed(6))
      const etiqueta = v.cerca
        ? `DENTRO del radio (~${Math.round(CERCA * 111000)} m, radio ${RADIO_M} m) → verificado=true`
        : `FUERA del radio (~${Math.round(LEJOS * 111000)} m, radio ${RADIO_M} m) → verificado=false + motivo`

      const vid = await escribir(
        `planificar visita de hoy a "${pros.nombre}"`,
        () => rpc(ases.cliente, 'planificar_visita', { p_prospecto_id: pids[v.p], p_fecha: hoy, p_hora: null }),
        `(visita-${v.p})`,
      )
      await escribir(
        `check-in en ${lat},${lng} — ${etiqueta}`,
        () => rpc(ases.cliente, 'checkin_visita_comercial', {
          p_visita_id: vid, p_lat: lat, p_lng: lng, p_precision_m: PRECISION_OK,
        }),
      )
      await escribir(`checkout de "${pros.nombre}"`,
        () => rpc(ases.cliente, 'checkout_visita_comercial', { p_visita_id: vid, p_lat: lat, p_lng: lng }))
      await escribir(
        `informe [${v.resultado}] "${v.resumen}"`,
        () => rpc(ases.cliente, 'guardar_reporte_visita', {
          p_visita_id: vid, p_resultado: v.resultado, p_resumen: v.resumen,
          p_compromisos: v.compromisos, p_proxima_accion_fecha: fechaISO(7),
        }),
      )
      hecho.push({ fase: 'F4', que: `visita HOY a ${pros.nombre} (${v.cerca ? 'verificada' : 'NO verificada'})`, id: vid, nuevo: true })
      void dlat
    }

    // --- agenda futura ---
    for (const v of VISITAS_FUTURAS.filter((x) => x.de === k)) {
      const pros = PROSPECTOS.find((p) => p.k === v.p)
      const f = fechaISO(v.enDias)
      const vid = await escribir(
        `planificar visita a "${pros.nombre}" para ${f}${v.hora ? ` ${v.hora}` : ' (sin hora)'}`,
        () => rpc(ases.cliente, 'planificar_visita', { p_prospecto_id: pids[v.p], p_fecha: f, p_hora: v.hora }),
        `(visita-futura-${v.p})`,
      )
      hecho.push({ fase: 'F4', que: `visita futura a ${pros.nombre} (${f})`, id: vid, nuevo: true })
    }

    // --- cierre o no ---
    if (CIERRA_JORNADA[k]) {
      await escribir('CERRAR la jornada',
        () => rpc(ases.cliente, 'cerrar_jornada', {
          p_lat: BASE.lat, p_lng: BASE.lng, p_precision_m: PRECISION_OK,
          p_notas: 'Jornada de demostración cerrada.',
        }))
    } else {
      log('   [.] la jornada queda ABIERTA a propósito: "en curso" es el estado que más se mira')
    }
  }
}

// ============================================================================================
// FASE 5 — pipeline
// ============================================================================================
async function fase5(admin, pids) {
  paso('FASE 5 · Pipeline (cambiar_estado_prospecto)')
  for (const p of PROSPECTOS) {
    if (p.estado === 'nuevo') { log(`   . "${p.nombre}" queda en nuevo`); continue }
    const motivo = p.estado === 'perdido' ? 'Eligió a un competidor. Revisar en el próximo ciclo.' : null
    await escribir(
      `"${p.nombre}" → ${p.estado}${motivo ? ` (motivo: ${motivo})` : ''}`,
      () => rpc(admin.cliente, 'cambiar_estado_prospecto', {
        p_prospecto_id: pids[p.k], p_estado: p.estado, p_motivo_perdida: motivo,
      }),
    )
    hecho.push({ fase: 'F5', que: `${p.nombre} → ${p.estado}`, id: pids[p.k], nuevo: true })
  }
}

// ============================================================================================
// Reporte
// ============================================================================================
function reporte(pais) {
  const destino = resolve(RAIZ, '.claude', 'QA_CUENTAS_PILOTO.md')
  const lineas = [
    '# Cuentas y datos del país DEMO (D10)',
    '',
    '> **Este archivo tiene contraseñas y NO va al repo.** `.claude/` está en `.gitignore`.',
    '> Generado por `scripts/seed-demo.mjs`.',
    '',
    `Generado: ${new Date().toISOString()}`,
    `País: **${pais.codigo}** · "${pais.nombre}" · \`${pais.id}\``,
    `Modo: **${ESCRIBIR ? 'ESCRITURA' : 'DRY-RUN (no se escribió nada)'}**`,
    '',
    '## Cuentas',
    '',
    '| rol | nombre | email | contraseña |',
    '|---|---|---|---|',
    ...CUENTAS.map((c) => `| ${c.rol} | ${c.nombre} | \`${c.email}\` | ${DEMO_PASS ? '`' + DEMO_PASS + '`' : '_(SEED_DEMO_PASSWORD no estaba seteada)_'} |`),
    '',
    'Las tres comparten la contraseña de `SEED_DEMO_PASSWORD`. Entran por `/login` y caen en',
    '`/comercial`. La supervisora ve además la tab **Equipo**.',
    '',
    '## Qué quedó sembrado',
    '',
    '| fase | qué | id | nuevo |',
    '|---|---|---|---|',
    ...hecho.map((h) => `| ${h.fase} | ${h.que} | \`${h.id}\` | ${h.nuevo ? 'sí' : 'ya estaba'} |`),
    '',
    '## Qué mirar en la demo',
    '',
    `- **Los dos tipos de check-in.** Uno dentro del radio de ${RADIO_M} m (queda verificado) y uno`,
    '  lejos (queda sin verificar, con el motivo que arma la RPC). Se ven distinto en la ficha de la',
    '  visita y en la vista del supervisor.',
    '- **Las dos jornadas.** Una queda ABIERTA ("en curso") y la otra cerrada.',
    '- **El pipeline** tiene prospectos en `nuevo`, `contactado`, `demo`, `negociacion`, `ganado` y',
    '  `perdido` — el perdido con su motivo.',
    '',
  ]
  mkdirSync(dirname(destino), { recursive: true })
  writeFileSync(destino, lineas.join('\n'), 'utf8')
  return destino
}

// ============================================================================================
async function main() {
  log('='.repeat(92))
  log(ESCRIBIR
    ? '  SEED DEMO — MODO ESCRITURA. Esto escribe en PRODUCCIÓN.'
    : '  SEED DEMO — DRY-RUN. No se escribe nada. Usá --ejecutar-en-produccion para hacerlo de verdad.')
  log('='.repeat(92))

  const { admin, pais } = await fase0()
  const ids = await fase1(admin, pais)
  await fase2(admin, pais, ids)
  const pids = await fase3(admin, pais, ids)
  await fase4(pais, ids, pids)
  await fase5(admin, pids)

  const destino = reporte(pais)
  log(`\n─── Reporte escrito en ${destino}`)
  log(ESCRIBIR ? '\n✓ Seed aplicado.\n' : '\n✓ Dry-run terminado. NO se escribió nada en la base.\n')
}

main().catch((e) => abortar(e?.stack ?? String(e)))
