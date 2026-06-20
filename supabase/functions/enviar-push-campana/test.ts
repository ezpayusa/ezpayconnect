// Test REAL del borde de autz de enviar-push-campana (l.7). Ejecuta: deno test --allow-none
// Cubre: (a) sin/JWT inválido → 401; (b) no-super_admin → 403; (c) body con usuario_ids arbitrarios →
// IGNORADO (sólo se usa solicitud_id + drenar_targets_push); (d) falta solicitud_id → 400.
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { handle, type Deps } from './index.ts'

// Admin falso que REGISTRA todas las llamadas (para verificar qué columnas/args se usan).
function makeFakeAdmin(opts: { rol: string | null; claimed: any[] }) {
  const calls: any[] = []
  function from(table: string) {
    const builder: any = {
      select: (..._a: any[]) => builder,
      eq: (col: string, val: any) => { calls.push({ op: 'eq', table, col, val }); return builder },
      maybeSingle: () => {
        if (table === 'perfiles') return Promise.resolve({ data: opts.rol ? { rol: opts.rol } : null, error: null })
        if (table === 'solicitudes_push') return Promise.resolve({ data: { id: 'sol-1', estado: 'aprobada', titulo: 'T', mensaje: 'M', url: '/' }, error: null })
        return Promise.resolve({ data: null, error: null })
      },
      insert: (row: any) => { calls.push({ op: 'insert', table, row }); return Promise.resolve({ data: null, error: null }) },
      update: (patch: any) => { calls.push({ op: 'update', table, patch }); return { eq: (c: string, v: any) => { calls.push({ op: 'update.eq', table, col: c, val: v }); return Promise.resolve({ data: null, error: null }) } } },
      delete: () => ({ eq: (c: string, v: any) => { calls.push({ op: 'delete.eq', table, col: c, val: v }); return Promise.resolve({ data: null, error: null }) } }),
      // thenable: para `await admin.from('push_subscriptions').select('*').eq('user_id', x)`
      then: (resolve: any) => resolve({ data: [], error: null }),
    }
    return builder
  }
  const rpc = (name: string, args: any) => { calls.push({ op: 'rpc', name, args }); return Promise.resolve({ data: name === 'drenar_targets_push' ? opts.claimed : null, error: null }) }
  return { from, rpc, _calls: calls }
}

const userClient = (rol: string | null) => ({
  makeUserClient: (_h: string) => ({ auth: { getUser: () => Promise.resolve({ data: { user: rol === null ? null : { id: 'u-1' } }, error: rol === null ? { msg: 'invalid' } : null }) } }),
}) as Pick<Deps, 'makeUserClient'>

const req = (headers: Record<string, string>, body: unknown) =>
  new Request('http://x/enviar-push-campana', { method: 'POST', headers, body: JSON.stringify(body) })

Deno.test('sin Authorization → 401', async () => {
  const admin = makeFakeAdmin({ rol: 'super_admin', claimed: [] })
  const res = await handle(req({}, { solicitud_id: 'sol-1' }), { ...userClient('super_admin'), admin, appKeys: null })
  assertEquals(res.status, 401)
})

Deno.test('JWT no-super_admin → 403', async () => {
  const admin = makeFakeAdmin({ rol: 'medico', claimed: [] })
  const res = await handle(req({ Authorization: 'Bearer x' }, { solicitud_id: 'sol-1' }), { ...userClient('medico'), admin, appKeys: null })
  assertEquals(res.status, 403)
})

Deno.test('falta solicitud_id → 400', async () => {
  const admin = makeFakeAdmin({ rol: 'super_admin', claimed: [] })
  const res = await handle(req({ Authorization: 'Bearer x' }, { usuario_ids: ['bogus-1'] }), { ...userClient('super_admin'), admin, appKeys: null })
  assertEquals(res.status, 400)
})

Deno.test('super_admin: usuario_ids del body IGNORADO; sólo cola/drenar', async () => {
  const claimed = [{ cola_id: 'c1', audiencia: 'staff', usuario_id: 'staff-1', push_user_id: 'staff-1', paciente_id: null }]
  const admin = makeFakeAdmin({ rol: 'super_admin', claimed })
  const res = await handle(
    req({ Authorization: 'Bearer x' }, { solicitud_id: 'sol-1', usuario_ids: ['bogus-1', 'bogus-2'] }),
    { ...userClient('super_admin'), admin, appKeys: {} as any },
  )
  assertEquals(res.status, 200)
  const calls = (admin as any)._calls
  // (1) drenó la cola de la solicitud (única fuente)
  const drn = calls.find((c: any) => c.op === 'rpc' && c.name === 'drenar_targets_push')
  assertEquals(drn?.args, { p_solicitud_id: 'sol-1' })
  // (2) la suscripción se buscó por el push_user_id RECLAMADO, no por la lista del body
  const subEq = calls.find((c: any) => c.op === 'eq' && c.table === 'push_subscriptions' && c.col === 'user_id')
  assertEquals(subEq?.val, 'staff-1')
  // (3) NINGUNA llamada referencia los usuario_ids arbitrarios del body
  const blob = JSON.stringify(calls)
  assertEquals(blob.includes('bogus-1') || blob.includes('bogus-2'), false)
  // (4) in-app a notificaciones (staff) con el usuario reclamado
  const ins = calls.find((c: any) => c.op === 'insert' && c.table === 'notificaciones')
  assertEquals(ins?.row?.usuario_id, 'staff-1')
})
