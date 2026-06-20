// Test REAL del borde de enviar-push-notificacion. deno test --allow-net --allow-env --no-check test.ts
// (a) secreto inválido → 401; (b) tabla fuera de allowlist → 400; (c) CLAIM atómico: idempotencia +
// doble-invocación → un solo envío; (d) 404 si no existe; (e) contenido/target de la FILA, no del body.
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { handle, type Deps } from './index.ts'

// Fake admin: claimRows = cola de resultados del UPDATE...RETURNING (claim atómico); exists = existencia.
function fakeAdmin(cfg: { claimRows: any[]; exists?: boolean; pacAuth?: string | null; subs?: any[] }) {
  const calls: any[] = []
  let claimIdx = 0
  const from = (table: string) => {
    const ctx: any = { table, isUpdate: false }
    const b: any = {
      update: (patch: any) => { calls.push({ op: 'update', table, patch }); ctx.isUpdate = true; return b },
      select: (..._a: any[]) => b,
      eq: (c: string, v: any) => { calls.push({ op: 'eq', table, c, v }); return b },
      is: (c: string, v: any) => { calls.push({ op: 'is', table, c, v }); return b },
      delete: () => ({ eq: () => Promise.resolve({ data: null, error: null }) }),
      maybeSingle: () => {
        if (table === 'pacientes') return Promise.resolve({ data: { auth_user_id: cfg.pacAuth ?? null }, error: null })
        if (ctx.isUpdate) return Promise.resolve({ data: cfg.claimRows[claimIdx++] ?? null, error: null })  // claim
        return Promise.resolve({ data: cfg.exists === false ? null : { id: 1 }, error: null })               // existencia
      },
      then: (res: any) => res({ data: cfg.subs ?? [], error: null }),   // push_subscriptions await
    }
    return b
  }
  return { from, _calls: calls }
}
const req = (h: Record<string, string>, body: unknown) => new Request('http://x', { method: 'POST', headers: h, body: JSON.stringify(body) })
const S = 's3cr3t'
const okRow = (over: any = {}) => ({ id: 7, titulo: 'Cita confirmada', mensaje: 'real', accion_url: '/paciente/citas', paciente_id: 23, ...over })

Deno.test('secreto faltante/incorrecto → 401', async () => {
  const admin = fakeAdmin({ claimRows: [okRow()] })
  assertEquals((await handle(req({}, { notification_id: 7, tabla: 'notificaciones_pacientes' }), { admin, appKeys: null, secret: S })).status, 401)
  assertEquals((await handle(req({ 'x-push-secret': 'mal' }, { notification_id: 7, tabla: 'notificaciones_pacientes' }), { admin, appKeys: null, secret: S })).status, 401)
})

Deno.test('tabla fuera de allowlist → 400 (antes de cualquier acceso)', async () => {
  const admin = fakeAdmin({ claimRows: [] })
  assertEquals((await handle(req({ 'x-push-secret': S }, { notification_id: 7, tabla: 'pg_catalog.pg_user' }), { admin, appKeys: null, secret: S })).status, 400)
  assertEquals((admin as any)._calls.length, 0)  // no tocó la DB
})

Deno.test('idempotencia: claim 0 filas + existe → idempotente', async () => {
  const admin = fakeAdmin({ claimRows: [null], exists: true })
  const r = await handle(req({ 'x-push-secret': S }, { notification_id: 7, tabla: 'notificaciones_pacientes' }), { admin, appKeys: {} as any, secret: S })
  assertEquals(r.status, 200); assertEquals((await r.json()).idempotente, true)
})

Deno.test('no existe → 404', async () => {
  const admin = fakeAdmin({ claimRows: [null], exists: false })
  assertEquals((await handle(req({ 'x-push-secret': S }, { notification_id: 9, tabla: 'notificaciones' }), { admin, appKeys: {} as any, secret: S })).status, 404)
})

Deno.test('CLAIM atómico: doble-invocación → un solo envío', async () => {
  const admin = fakeAdmin({ claimRows: [okRow(), null], exists: true, pacAuth: 'pac-auth-1', subs: [] })
  const r1 = await handle(req({ 'x-push-secret': S }, { notification_id: 7, tabla: 'notificaciones_pacientes' }), { admin, appKeys: {} as any, secret: S })
  const r2 = await handle(req({ 'x-push-secret': S }, { notification_id: 7, tabla: 'notificaciones_pacientes' }), { admin, appKeys: {} as any, secret: S })
  assertEquals((await r1.json()).idempotente, undefined)   // 1ra reclamó (procesó)
  assertEquals((await r2.json()).idempotente, true)        // 2da NO re-empuja
  // el claim usó la condición push_enviado IS NULL (atómico)
  assertEquals((admin as any)._calls.some((c: any) => c.op === 'is' && c.c === 'push_enviado' && c.v === null), true)
})

Deno.test('contenido/target de la FILA, no del body', async () => {
  const admin = fakeAdmin({ claimRows: [okRow()], exists: true, pacAuth: 'pac-auth-1', subs: [] })
  const r = await handle(
    req({ 'x-push-secret': S }, { notification_id: 7, tabla: 'notificaciones_pacientes', titulo: 'HACK', usuario_id: 'attacker' }),
    { admin, appKeys: {} as any, secret: S },
  )
  assertEquals(r.status, 200)
  const calls = (admin as any)._calls
  const subEq = calls.find((c: any) => c.op === 'eq' && c.table === 'push_subscriptions' && c.c === 'user_id')
  assertEquals(subEq?.v, 'pac-auth-1')   // target derivado de la fila, no del body
  assertEquals(JSON.stringify(calls).includes('attacker') || JSON.stringify(calls).includes('HACK'), false)
})
