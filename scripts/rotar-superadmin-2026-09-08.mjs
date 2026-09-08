#!/usr/bin/env node
// ============================================================================================
// ROTACION DE LA CUENTA super_admin — 8-sep-2026. SCRIPT DE UN SOLO USO.
// ============================================================================================
// QUE HACE
//   admin.qa@ezpayconnect.com  →  superadmin@ezpayconnect.com, con contrasena nueva,
//   sobre el id 41904e2c-5ef3-4fee-bd48-9ea58e0c8c37, y cerrando sus sesiones abiertas.
//
// POR QUE ES DE UN SOLO USO: el id y los dos emails estan escritos como literales. No es una
// herramienta reutilizable y no debe convertirse en una — una funcion generica de "rotar cualquier
// super_admin" es una superficie que no queremos tener en el repo.
//
// DRY-RUN POR DEFECTO. Sin `--execute` no escribe nada: verifica el estado, dice exactamente que
// haria y termina. El flag es explicito a proposito.
//
// CREDENCIALES: SOLO del entorno, nunca de un archivo.
//   SUPABASE_URL                → la URL del proyecto
//   SUPABASE_SERVICE_ROLE_KEY   → la clave de servicio
// A diferencia de `seed-demo.mjs`, aca NI SIQUIERA la URL se lee de `.env.local`: este script
// cambia la credencial del rol mas alto del sistema, y las dos variables tienen que ser un acto
// deliberado de quien lo corre. No hay ningun archivo del que las tome "por si acaso".
//
// DOS CAMINOS DE ACCESO, Y POR QUE
//   * `@supabase/supabase-js` con service_role → Auth admin API (leer/actualizar el usuario) y
//     `public.perfiles` (PostgREST expone `public`).
//   * el CLI de Supabase (`supabase db query --linked`) → TODO lo que vive en el schema `auth`.
//     Medido: PostgREST responde `PGRST106 Invalid schema: auth`, asi que `auth.sessions` y
//     `auth.refresh_tokens` NO son alcanzables con la service key por HTTP, y `pg` no esta
//     instalado en este repo. El CLI es la unica via.
//     OJO: el CLI usa SU PROPIA credencial (el token de `supabase login`, en ~/.supabase), no la
//     service key. Son dos credenciales distintas y quien corra esto tiene que tener las dos.
//
// Uso:
//   node scripts/rotar-superadmin-2026-09-08.mjs             # DRY-RUN
//   node scripts/rotar-superadmin-2026-09-08.mjs --execute   # rota de verdad
// ============================================================================================
import { createClient } from '@supabase/supabase-js'
import { randomBytes } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { writeFileSync, unlinkSync, mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

// ---------------------------------------------------------------------------- constantes
const ID = '41904e2c-5ef3-4fee-bd48-9ea58e0c8c37'
const EMAIL_VIEJO = 'admin.qa@ezpayconnect.com'
const EMAIL_NUEVO = 'superadmin@ezpayconnect.com'

const EJECUTAR = process.argv.includes('--execute')
const URL = process.env.SUPABASE_URL
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY

const log = (...a) => console.log(...a)
const paso = (t) => log(`\n─── ${t}`)

function abortar(msg) {
  console.error(`\n✗ ABORTADO: ${msg}\n`)
  process.exit(1)
}

// ---------------------------------------------------------------------------- SQL por el CLI
const TMP = mkdtempSync(join(tmpdir(), 'rot-'))

/**
 * Corre SQL contra la base por el CLI y devuelve las filas.
 *
 * `--output json` va EXPLICITO: el CLI decide el formato por deteccion de agente y en una shell
 * limpia devuelve una TABLA con bordes, que no se puede parsear. Una corrida que devolvio tabla no
 * midio nada. Y las dos variables de telemetria van en el env del SUBPROCESO: sin ellas el CLI
 * escribe ~/.supabase/telemetry.json antes de hacer nada y muere con EPERM en sandboxes.
 */
function sql(texto) {
  const f = join(TMP, `q${Date.now()}${Math.random().toString(36).slice(2)}.sql`)
  writeFileSync(f, texto, 'utf8')
  try {
    const out = execFileSync(
      'supabase',
      ['db', 'query', '--linked', '--output', 'json', '-f', f],
      { encoding: 'utf8', shell: true, stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, SUPABASE_TELEMETRY_DISABLED: '1', DO_NOT_TRACK: '1' } },
    )
    const i = out.indexOf('{')
    if (i < 0) throw new Error(`el CLI no devolvio JSON:\n${out.slice(0, 400)}`)
    const d = JSON.parse(out.slice(i))
    if (!Array.isArray(d.rows)) throw new Error(`respuesta sin \`rows\`: ${out.slice(0, 300)}`)
    return d.rows
  } catch (e) {
    const detalle = e.stderr ? String(e.stderr).slice(-500) : (e.message ?? String(e))
    throw new Error(`SQL fallo: ${detalle}`)
  } finally {
    try { unlinkSync(f) } catch { /* da igual */ }
  }
}

// ============================================================================================
async function main() {
  log('='.repeat(92))
  log(EJECUTAR
    ? '  ROTACION DE super_admin — MODO ESCRITURA. Cambia email y contrasena en PRODUCCION.'
    : '  ROTACION DE super_admin — DRY-RUN. No se escribe nada. Usá --execute para hacerlo.')
  log('='.repeat(92))
  log(`\n  id     : ${ID}`)
  log(`  de     : ${EMAIL_VIEJO}`)
  log(`  a      : ${EMAIL_NUEVO}`)

  if (!URL) abortar('falta SUPABASE_URL. Esta script NO la lee de ningun archivo: exportala.')
  if (!SERVICE) abortar('falta SUPABASE_SERVICE_ROLE_KEY. Solo del entorno: exportala.')
  const admin = createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } })

  // ------------------------------------------------------------------ 1) verificacion previa
  paso('PASO 1 · Verificacion previa (SELECT, siempre — tambien en dry-run)')
  log('   No se opera a ciegas sobre un estado distinto al del recon: si algo no calza, aborta.')

  const { data: u0, error: eU } = await admin.auth.admin.getUserById(ID)
  if (eU) abortar(`no se pudo leer auth.users para ${ID}: ${eU.message}`)
  if (!u0?.user) abortar(`el id ${ID} no existe en auth.users`)
  const emailActual = String(u0.user.email ?? '')
  log(`   auth.users.email        = ${emailActual}`)
  if (emailActual !== EMAIL_VIEJO) {
    abortar(`auth.users.email es "${emailActual}" y se esperaba EXACTO "${EMAIL_VIEJO}". `
      + 'El estado cambio desde el recon.')
  }

  const { data: perf, error: eP } = await admin
    .from('perfiles').select('id,email,rol,pais_id,activo,nombre_completo').eq('id', ID).maybeSingle()
  if (eP) abortar(`no se pudo leer public.perfiles: ${eP.message}`)
  if (!perf) abortar(`el id ${ID} no tiene fila en public.perfiles`)
  log(`   perfiles.email          = ${perf.email}`)
  log(`   perfiles.rol            = ${perf.rol}`)
  log(`   perfiles.activo         = ${perf.activo}`)
  log(`   perfiles.pais_id        = ${perf.pais_id ?? '(NULL)'}`)
  log(`   perfiles.nombre_completo= ${perf.nombre_completo ?? '(NULL)'}`)
  if (perf.rol !== 'super_admin') abortar(`perfiles.rol es "${perf.rol}" y se esperaba "super_admin"`)
  if (perf.activo !== true) abortar(`perfiles.activo es ${perf.activo} y se esperaba true`)

  // Se guardan para el control posterior: rol, pais_id y activo NO pueden cambiar.
  const invariantes = { rol: perf.rol, pais_id: perf.pais_id, activo: perf.activo }

  // ------------------------------------------------------------------ 2) el destino esta libre
  paso('PASO 2 · El email nuevo NO existe todavia')
  const libres = sql(`
SELECT 'auth.users' AS tabla, count(*) AS n FROM auth.users     WHERE lower(email) = '${EMAIL_NUEVO}'
UNION ALL
SELECT 'perfiles',            count(*)      FROM public.perfiles WHERE lower(email) = '${EMAIL_NUEVO}'
ORDER BY 1;`)
  for (const r of libres) log(`   ${String(r.tabla).padEnd(12)} ${r.n}`)
  const ocupado = libres.filter((r) => Number(r.n) !== 0)
  if (ocupado.length) {
    abortar(`${EMAIL_NUEVO} YA EXISTE en: ${ocupado.map((r) => `${r.tabla}(${r.n})`).join(', ')}. `
      + 'Rotar hacia un email ocupado dejaria dos cuentas peleando por el mismo login.')
  }

  // ------------------------------------------------------------------ sesiones ANTES
  paso('PASO 3 · Sesiones abiertas (antes)')
  const antes = sql(`
SELECT s.id::text AS id, s.created_at::text AS creada
  FROM auth.sessions s WHERE s.user_id = '${ID}' ORDER BY s.created_at;`)
  const tokAntes = sql(`SELECT count(*) AS n FROM auth.refresh_tokens WHERE user_id = '${ID}';`)
  for (const s of antes) log(`   sesion ${s.id}  creada ${s.creada}`)
  log(`   auth.sessions        : ${antes.length}`)
  log(`   auth.refresh_tokens  : ${tokAntes[0]?.n ?? '?'}`)

  // ------------------------------------------------------------------ dry-run: hasta aca
  if (!EJECUTAR) {
    paso('LO QUE HARIA CON --execute')
    log('   1. generar una contrasena random (32 bytes, base64url) — no se genera en dry-run')
    log(`   2. auth.admin.updateUserById(${ID}, { email, password, email_confirm: true })`)
    log(`   3. UPDATE public.perfiles SET email='${EMAIL_NUEVO}' WHERE id='${ID}'`)
    log(`   4. cerrar las ${antes.length} sesiones:`)
    log('      a. intentar POST /auth/v1/admin/users/<id>/logout (si GoTrue lo expone)')
    log('      b. si no responde 2xx, DELETE acotado por user_id en auth.refresh_tokens y')
    log('         auth.sessions, en UNA transaccion, con conteo antes y despues')
    log('   5. releer las dos tablas y verificar email nuevo, invariantes intactas, 0 sesiones')
    log('   6. imprimir la contrasena UNA sola vez')
    log('\n✓ Dry-run terminado. NO se escribio nada.\n')
    return
  }

  // ------------------------------------------------------------------ 4) contrasena + Auth
  paso('PASO 4 · Contrasena nueva y actualizacion en Auth')
  // 32 bytes de crypto.randomBytes → 43 caracteres base64url. Nunca hardcodeada, nunca a archivo,
  // nunca a git: vive en memoria y se imprime una vez al final.
  const clave = randomBytes(32).toString('base64url')
  log('   contrasena generada (32 bytes aleatorios); se imprime al final, una sola vez')

  const { data: upd, error: eUpd } = await admin.auth.admin.updateUserById(ID, {
    email: EMAIL_NUEVO, password: clave, email_confirm: true,
  })
  if (eUpd) abortar(`updateUserById fallo: ${eUpd.message}`)
  log(`   ✓ auth.users actualizado → ${upd.user.email}`)

  // ------------------------------------------------------------------ 5) perfiles
  paso('PASO 5 · public.perfiles')
  log('   No hay trigger que sincronice auth.users → perfiles (confirmado en el recon).')
  const { error: eUp2 } = await admin.from('perfiles').update({ email: EMAIL_NUEVO }).eq('id', ID)
  if (eUp2) abortar(`UPDATE perfiles fallo: ${eUp2.message}. `
    + 'OJO: auth.users YA quedo cambiado — las dos tablas estan desincronizadas.')
  log(`   ✓ perfiles.email actualizado`)

  // ------------------------------------------------------------------ 6) sesiones
  paso('PASO 6 · Cerrar las sesiones abiertas')
  let via = null
  try {
    const r = await fetch(`${URL}/auth/v1/admin/users/${ID}/logout`, {
      method: 'POST', headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` },
    })
    if (r.ok || r.status === 204) { via = `endpoint admin de logout (HTTP ${r.status})` }
    else { log(`   el endpoint admin de logout respondio HTTP ${r.status}; se usa el DELETE`) }
  } catch (e) {
    log(`   el endpoint admin de logout no se pudo llamar (${e.message}); se usa el DELETE`)
  }

  if (!via) {
    // DELETE acotado por user_id, en UNA transaccion, con conteo antes y despues. Nada de borrar
    // por fecha ni por rango: solo las filas de ESTE id.
    const res = sql(`
BEGIN;
DO $$
DECLARE v_s0 int; v_t0 int; v_s1 int; v_t1 int;
BEGIN
  SELECT count(*) INTO v_s0 FROM auth.sessions        WHERE user_id = '${ID}';
  SELECT count(*) INTO v_t0 FROM auth.refresh_tokens  WHERE user_id = '${ID}';
  DELETE FROM auth.refresh_tokens WHERE user_id = '${ID}';
  DELETE FROM auth.sessions       WHERE user_id = '${ID}';
  SELECT count(*) INTO v_s1 FROM auth.sessions        WHERE user_id = '${ID}';
  SELECT count(*) INTO v_t1 FROM auth.refresh_tokens  WHERE user_id = '${ID}';
  IF v_s1 <> 0 OR v_t1 <> 0 THEN
    RAISE EXCEPTION 'quedaron filas: sessions=% refresh_tokens=%', v_s1, v_t1;
  END IF;
  PERFORM set_config('rot.detalle',
    format('sessions %s->%s, refresh_tokens %s->%s', v_s0, v_s1, v_t0, v_t1), false);
END $$;
SELECT current_setting('rot.detalle', true) AS detalle;
COMMIT;`)
    via = `DELETE transaccional (${res[0]?.detalle ?? 'sin detalle'})`
  }
  log(`   ✓ ${via}`)

  // ------------------------------------------------------------------ 7) verificacion posterior
  paso('PASO 7 · Verificacion posterior')
  const { data: uF } = await admin.auth.admin.getUserById(ID)
  const { data: pF } = await admin
    .from('perfiles').select('email,rol,pais_id,activo').eq('id', ID).maybeSingle()
  const sesF = sql(`SELECT count(*) AS n FROM auth.sessions WHERE user_id = '${ID}';`)
  const tokF = sql(`SELECT count(*) AS n FROM auth.refresh_tokens WHERE user_id = '${ID}';`)

  const checks = [
    ['auth.users.email es el nuevo', uF?.user?.email === EMAIL_NUEVO, uF?.user?.email],
    ['perfiles.email es el nuevo', pF?.email === EMAIL_NUEVO, pF?.email],
    ['rol SIN cambios', pF?.rol === invariantes.rol, pF?.rol],
    ['pais_id SIN cambios', (pF?.pais_id ?? null) === (invariantes.pais_id ?? null), pF?.pais_id ?? '(NULL)'],
    ['activo SIN cambios', pF?.activo === invariantes.activo, pF?.activo],
    ['0 sesiones', Number(sesF[0]?.n) === 0, sesF[0]?.n],
    ['0 refresh_tokens', Number(tokF[0]?.n) === 0, tokF[0]?.n],
  ]
  let ok = true
  for (const [que, vale, visto] of checks) {
    log(`   ${vale ? '✓' : '✗'} ${que.padEnd(30)} ${visto}`)
    if (!vale) ok = false
  }

  // ------------------------------------------------------------------ 8) la contrasena
  log('\n' + '█'.repeat(92))
  log('  GUARDAR AHORA — no se vuelve a mostrar. No queda en ningun archivo ni en git.')
  log('█'.repeat(92))
  log(`\n  usuario     : ${EMAIL_NUEVO}`)
  log(`  contrasena  : ${clave}\n`)
  log('█'.repeat(92))

  log(ok ? '\n✓ Rotacion completa y verificada.\n'
        : '\n✗ La rotacion se hizo pero la verificacion NO cuadra: revisar arriba.\n')
  if (!ok) process.exit(1)
}

main().catch((e) => abortar(e?.stack ?? String(e)))
