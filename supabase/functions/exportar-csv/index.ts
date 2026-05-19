// supabase/functions/exportar-csv/index.ts
// Dia 16: Edge Function - Exportar datos a CSV
// EzPayConnect — Actualizado: sin facturacion

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function convertToCSV(data: any[], tipo: string): string {
  if (!data || data.length === 0) return ''

  let headers: string[] = []
  let rows: string[] = []

  switch (tipo) {
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
      ].map(field => `"${String(field).replace(/"/g, '""')}"`).join(','))
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
      ].map(field => `"${String(field).replace(/"/g, '""')}"`).join(','))
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
      ].map(field => `"${String(field).replace(/"/g, '""')}"`).join(','))
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
      ].map(field => `"${String(field).replace(/"/g, '""')}"`).join(','))
      break
    }

    default:
      headers = Object.keys(data[0])
      rows = data.map(r => headers.map(h => {
        const val = r[h]
        if (val === null || val === undefined) return '""'
        if (typeof val === 'object') return `"${JSON.stringify(val).replace(/"/g, '""')}"`
        return `"${String(val).replace(/"/g, '""')}"`
      }).join(','))
  }

  const BOM = '\uFEFF'
  return BOM + [headers.join(','), ...rows].join('\n')
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const { tipo, nombre_archivo } = await req.json()

    if (!tipo) throw new Error('Se requiere el parametro "tipo"')

    let data: any[] = []
    let titulo = ''

    switch (tipo) {
      case 'citas': {
        titulo = 'Reporte de Citas'
        const { data: result, error } = await supabase
          .from('citas')
          .select('*, paciente:pacientes(nombre, telefono), medico:perfiles!citas_medico_id_fkey(nombre)')
          .order('fecha', { ascending: false })
          .limit(1000)
        if (error) throw error
        data = result || []
        break
      }

      case 'pacientes': {
        titulo = 'Reporte de Pacientes'
        const { data: result, error } = await supabase
          .from('v_pacientes_actividad')
          .select('*')
          .order('ultima_cita', { ascending: false })
          .limit(1000)
        if (error) throw error
        data = result || []
        break
      }

      case 'recetas': {
        titulo = 'Reporte de Recetas'
        const { data: result, error } = await supabase
          .from('recetas')
          .select('*, paciente:pacientes(nombre), medico:perfiles!recetas_medico_id_fkey(nombre)')
          .order('created_at', { ascending: false })
          .limit(1000)
        if (error) throw error
        data = result || []
        break
      }

      case 'resumen': {
        titulo = 'Resumen Mensual'
        const { data: result, error } = await supabase
          .from('v_resumen_mensual')
          .select('*')
          .order('mes', { ascending: false })
          .limit(24)
        if (error) throw error
        data = result || []
        break
      }

      default:
        throw new Error(`Tipo no soportado: ${tipo}`)
    }

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
