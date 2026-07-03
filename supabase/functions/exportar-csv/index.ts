// supabase/functions/exportar-csv/index.ts
// EzPayConnect — Exportar datos a CSV
// Panel Médico + Panel Admin EZPay
// Actualizado con columnas reales de Supabase
// VERSIÓN SIN AUTENTICACIÓN (solo para pruebas)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function escapeCSV(field: any): string {
  if (field === null || field === undefined) return '""'
  if (typeof field === 'object') return `"${JSON.stringify(field).replace(/"/g, '""')}"`
  return `"${String(field).replace(/"/g, '""')}"`
}

function convertToCSV(data: any[], tipo: string): string {
  if (!data || data.length === 0) return ''

  let headers: string[] = []
  let rows: string[] = []

  switch (tipo) {
    // ═══════════════════════════════════════════════════
    // PANEL MÉDICO (existente — NO MODIFICAR)
    // ═══════════════════════════════════════════════════
    case 'citas': {
      headers = ['ID', 'Fecha', 'Hora', 'Paciente', 'Telefono', 'Medico', 'Estado', 'Motivo', 'Notas']
      rows = data.map(r => [
        r.id,
        r.fecha,
        r.hora,
        r.paciente?.nombre || 'N/A',
        r.paciente?.telefono || 'N/A',
        r.medico?.nombre || 'N/A',
        r.estado,
        r.motivo || '',
        r.notas || ''
      ].map(escapeCSV).join(','))
      break
    }

    case 'pacientes': {
      headers = ['ID', 'Nombre', 'Telefono', 'Total Citas', 'Ultima Cita', 'Total Recetas', 'Canceladas']
      rows = data.map(r => [
        r.paciente_id,
        r.paciente_nombre,
        r.telefono || 'N/A',
        r.total_citas,
        r.ultima_cita || 'Nunca',
        r.total_recetas,
        r.citas_canceladas
      ].map(escapeCSV).join(','))
      break
    }

    case 'recetas': {
      headers = ['ID', 'Fecha', 'Paciente', 'Medico', 'Diagnostico', 'Medicamentos', 'Indicaciones', 'Estado']
      rows = data.map(r => [
        r.id,
        r.created_at?.split('T')[0] || '',
        r.paciente?.nombre || 'N/A',
        r.medico?.nombre || 'N/A',
        r.diagnostico || '',
        Array.isArray(r.medicamentos) ? r.medicamentos.join('; ') : r.medicamentos || '',
        r.indicaciones || '',
        r.estado || 'activa'
      ].map(escapeCSV).join(','))
      break
    }

    case 'resumen': {
      headers = ['Mes', 'Total Citas', 'Atendidas', 'Canceladas', 'Pendientes', 'Pacientes Nuevos', 'Recetas']
      rows = data.map(r => [
        r.mes,
        r.total_citas,
        r.citas_atendidas,
        r.citas_canceladas,
        r.citas_pendientes,
        r.pacientes_nuevos,
        r.recetas_emitidas
      ].map(escapeCSV).join(','))
      break
    }

    // ═══════════════════════════════════════════════════
    // PANEL ADMIN EZPAY (nuevos — ajustados a columnas reales)
    // ═══════════════════════════════════════════════════
    case 'empleados': {
      headers = ['ID', 'Nombre', 'Email', 'Rol', 'Rol ID', 'Activo', 'Creado', 'Actualizado']
      rows = data.map(r => [
        r.id,
        r.nombre || r.nombre_completo || 'N/A',
        r.email || 'N/A',
        r.rol || 'N/A',
        r.rol_id || 'N/A',
        r.activo ? 'Si' : 'No',
        r.created_at?.split('T')[0] || '',
        r.updated_at?.split('T')[0] || ''
      ].map(escapeCSV).join(','))
      break
    }

    case 'planes': {
      headers = ['ID', 'Nombre', 'Categoria', 'Pais ID', 'Precio', 'Moneda', 'Estado', 'Creado', 'Actualizado']
      rows = data.map(r => [
        r.id,
        r.nombre || 'N/A',
        r.categoria || 'N/A',
        r.pais_id || 'N/A',
        r.precio || r.precio_mensual || r.precio_anual || 0,
        r.moneda || 'USD',
        r.activo ? 'Activo' : 'Inactivo',
        r.created_at?.split('T')[0] || '',
        r.updated_at?.split('T')[0] || ''
      ].map(escapeCSV).join(','))
      break
    }

    case 'transacciones': {
      headers = ['ID', 'Usuario ID', 'Plan ID', 'Pais ID', 'Monto', 'Moneda', 'Tipo Pago', 'Estado', 'Metodo Pago', 'Referencia Externa', 'Comision Aplicada', 'Monto Comision', 'Fecha Pago', 'Creado', 'Actualizado']
      rows = data.map(r => [
        r.id,
        r.usuario_id || 'N/A',
        r.plan_id || 'N/A',
        r.pais_id || 'N/A',
        r.monto || 0,
        r.moneda || 'USD',
        r.tipo_pago || 'N/A',
        r.estado || 'N/A',
        r.metodo_pago || 'N/A',
        r.referencia_externa || 'N/A',
        r.comision_aplicada || 0,
        r.monto_comision || 0,
        r.fecha_pago?.split('T')[0] || '',
        r.created_at?.split('T')[0] || '',
        r.updated_at?.split('T')[0] || ''
      ].map(escapeCSV).join(','))
      break
    }

    case 'audit_logs': {
      headers = ['ID', 'Fecha', 'Usuario', 'Accion', 'Tabla', 'Registro ID', 'Cambios', 'IP', 'User Agent']
      rows = data.map(r => [
        r.id,
        r.created_at?.split('T')[0] || '',
        r.usuario_email || r.usuario_id || 'Sistema',
        r.accion || 'N/A',
        r.tabla || 'N/A',
        r.registro_id || 'N/A',
        r.cambios ? JSON.stringify(r.cambios) : '',
        r.ip_address || 'N/A',
        r.user_agent || 'N/A'
      ].map(escapeCSV).join(','))
      break
    }

    default:
      headers = Object.keys(data[0])
      rows = data.map(r => headers.map(h => escapeCSV(r[h])).join(','))
  }

  const BOM = '\uFEFF'
  return BOM + [headers.join(','), ...rows].join('\n')
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // GATE DE AUTORIZACIÓN — solo super_admin. Esta función usa service_role (bypass RLS) y es la más
    // sensible del censo (exporta transacciones/audit_logs/perfiles). Mismo patrón que reportes-ezpay:
    // se valida el JWT con un cliente anon (getUser) y el rol se lee con el admin client.
    const supabaseAnonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY') || ''
    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader) {
      return new Response(JSON.stringify({ success: false, error: 'Falta Authorization' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }
    const userClient = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } })
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) {
      return new Response(JSON.stringify({ success: false, error: 'JWT inválido' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }
    const { data: perfilCaller } = await supabase.from('perfiles').select('rol').eq('id', user.id).maybeSingle()
    if (!perfilCaller || perfilCaller.rol !== 'super_admin') {
      return new Response(JSON.stringify({ success: false, error: 'No autorizado: sólo super_admin' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 })
    }

    const { tipo, nombre_archivo, filtros } = await req.json()

    if (!tipo) throw new Error('Se requiere el parametro "tipo"')

    let data: any[] = []
    let titulo = ''
    let query: any

    switch (tipo) {
      // ═══════════════════════════════════════════════════
      // PANEL MÉDICO
      // ═══════════════════════════════════════════════════
      case 'citas': {
        titulo = 'Reporte de Citas'
        query = supabase
          .from('citas')
          .select('*, paciente:pacientes(nombre, telefono), medico:perfiles!citas_medico_id_fkey(nombre)')
          .order('fecha', { ascending: false })
          .limit(1000)
        break
      }

      case 'pacientes': {
        titulo = 'Reporte de Pacientes'
        query = supabase
          .from('v_pacientes_actividad')
          .select('*')
          .order('ultima_cita', { ascending: false })
          .limit(1000)
        break
      }

      case 'recetas': {
        titulo = 'Reporte de Recetas'
        query = supabase
          .from('recetas')
          .select('*, paciente:pacientes(nombre), medico:perfiles!recetas_medico_id_fkey(nombre)')
          .order('created_at', { ascending: false })
          .limit(1000)
        break
      }

      case 'resumen': {
        titulo = 'Resumen Mensual'
        query = supabase
          .from('v_resumen_mensual')
          .select('*')
          .order('mes', { ascending: false })
          .limit(24)
        break
      }

      // ═══════════════════════════════════════════════════
      // PANEL ADMIN EZPAY
      // ═══════════════════════════════════════════════════
      case 'empleados': {
        titulo = 'Reporte de Empleados'
        query = supabase
          .from('perfiles')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(5000)
        break
      }

      case 'planes': {
        titulo = 'Reporte de Planes'
        query = supabase
          .from('planes')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(1000)
        break
      }

      case 'transacciones': {
        titulo = 'Reporte de Transacciones'
        query = supabase
          .from('transacciones')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(5000)
        break
      }

      case 'audit_logs': {
        titulo = 'Reporte de Auditoria'
        query = supabase
          .from('audit_logs')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(5000)
        break
      }

      default:
        throw new Error(`Tipo no soportado: ${tipo}`)
    }

    // Aplicar filtros si existen
    if (filtros) {
      if (filtros.pais_id) query = query.eq('pais_id', filtros.pais_id)
      if (filtros.estado) query = query.eq('estado', filtros.estado)
      if (filtros.fecha_desde) query = query.gte('created_at', filtros.fecha_desde)
      if (filtros.fecha_hasta) query = query.lte('created_at', filtros.fecha_hasta)
      if (filtros.rol) query = query.eq('rol', filtros.rol)
      if (filtros.categoria) query = query.eq('categoria', filtros.categoria)
      if (filtros.tipo_pago) query = query.eq('tipo_pago', filtros.tipo_pago)
      if (filtros.metodo_pago) query = query.eq('metodo_pago', filtros.metodo_pago)
    }

    const { data: result, error } = await query
    if (error) throw error
    data = result || []

    const csv = convertToCSV(data, tipo)

    const fecha = new Date().toISOString().split('T')[0]
    const filename = nombre_archivo || `ezpayconnect_${tipo}_${fecha}.csv`

    return new Response(csv, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': `attachment; filename="${filename}"`,
      },
      status: 200,
    })

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})
