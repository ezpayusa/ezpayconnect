// supabase/functions/reportes-ezpay/index.ts
// EzPayConnect — Reportes EZPay V2 con datos reales
// Bypass RLS usando service role key

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const { periodo, tabActiva, fechaInicio } = await req.json()

    console.log('📊 Reportes EZPay - Request:', { periodo, tabActiva, fechaInicio })

    // Cargar países
    const { data: paisesData, error: errPaises } = await supabase
      .from('configuracion_pais')
      .select('id, nombre, codigo, moneda')
      .order('nombre')

    if (errPaises) throw new Error('Error países: ' + errPaises.message)

    const paisesMap: Record<string, any> = {}
    paisesData?.forEach((p: any) => {
      paisesMap[p.id] = { nombre: p.nombre, codigo: p.codigo, moneda: p.moneda }
    })

    // Cargar planes
    const { data: planesData, error: errPlanes } = await supabase
      .from('planes_base')
      .select('id, nombre, tipo')
      .eq('activo', true)

    if (errPlanes) throw new Error('Error planes: ' + errPlanes.message)

    const planesMap: Record<string, any> = {}
    planesData?.forEach((p: any) => {
      planesMap[p.id] = { nombre: p.nombre, tipo: p.tipo }
    })

    // Filtrar planes por tipo
    let planIdsFiltrados: string[] | null = null
    if (tabActiva !== 'todos') {
      planIdsFiltrados = planesData?.filter((p: any) => p.tipo === tabActiva).map((p: any) => p.id) || []
      if (planIdsFiltrados.length === 0) {
        return new Response(
          JSON.stringify({ 
            success: true, 
            data: {
              paises: [],
              planes: [],
              mensual: [],
              stats: { totalIngresos: 0, totalVentas: 0, paisesActivos: 0, planesVendidos: 0, comisionesEstimadas: 0 }
            }
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
        )
      }
    }

    // Cargar transacciones con service role (bypass RLS)
    let query = supabase
      .from('transacciones')
      .select('*')
      .eq('estado', 'completado')

    if (fechaInicio && periodo !== 'todos') {
      query = query.gte('fecha_pago', fechaInicio)
    }

    if (planIdsFiltrados) {
      query = query.in('plan_id', planIdsFiltrados)
    }

    const { data: transData, error: errTrans } = await query

    if (errTrans) throw new Error('Error transacciones: ' + errTrans.message)

    console.log('✅ Transacciones cargadas:', transData?.length || 0)

    // Procesar datos
    const paisesReporte: Record<string, any> = {}
    const planesReporte: Record<string, any> = {}
    const mensualMap: Record<string, any> = {}

    let procesadas = 0
    let ignoradas = 0

    transData?.forEach((t: any) => {
      const planInfo = planesMap[t.plan_id]
      const paisInfo = paisesMap[t.pais_id]

      if (!planInfo) { ignoradas++; return }
      if (!paisInfo) { ignoradas++; return }

      procesadas++

      // Por país
      const paisKey = paisInfo.nombre
      if (!paisesReporte[paisKey]) {
        paisesReporte[paisKey] = {
          pais: paisInfo.nombre,
          codigo: paisInfo.codigo,
          transacciones: 0,
          ingresos: 0,
          moneda: paisInfo.moneda,
        }
      }
      paisesReporte[paisKey].transacciones += 1
      paisesReporte[paisKey].ingresos += parseFloat(t.monto) || 0

      // Por plan
      const planKey = planInfo.nombre
      if (!planesReporte[planKey]) {
        planesReporte[planKey] = {
          plan: planInfo.nombre,
          tipo: planInfo.tipo,
          ventas: 0,
          ingresos: 0,
        }
      }
      planesReporte[planKey].ventas += 1
      planesReporte[planKey].ingresos += parseFloat(t.monto) || 0

      // Mensual
      const fecha = t.fecha_pago ? new Date(t.fecha_pago) : new Date(t.created_at)
      const mesKey = `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}`
      const mesNombre = fecha.toLocaleDateString('es-ES', { month: 'short', year: 'numeric' })

      if (!mensualMap[mesKey]) {
        mensualMap[mesKey] = {
          mes: mesNombre,
          anio: fecha.getFullYear(),
          total: 0,
          transacciones: 0,
        }
      }
      mensualMap[mesKey].total += parseFloat(t.monto) || 0
      mensualMap[mesKey].transacciones += 1
    })

    const paisesArray = Object.values(paisesReporte)
    const planesArray = Object.values(planesReporte)
    const mensualArray = Object.values(mensualMap).sort((a: any, b: any) => {
      if (a.anio !== b.anio) return a.anio - b.anio
      return a.mes.localeCompare(b.mes)
    })

    const totalIngresos = paisesArray.reduce((sum: number, p: any) => sum + p.ingresos, 0)

    console.log('📊 Resumen:', { procesadas, ignoradas, paises: paisesArray.length, planes: planesArray.length, totalIngresos })

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          paises: paisesArray,
          planes: planesArray,
          mensual: mensualArray,
          stats: {
            totalIngresos,
            totalVentas: paisesArray.reduce((sum: number, p: any) => sum + p.transacciones, 0),
            paisesActivos: paisesArray.length,
            planesVendidos: planesArray.length,
            comisionesEstimadas: totalIngresos * 0.05,
          }
        }
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error: any) {
    console.error('❌ Error:', error.message)
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
