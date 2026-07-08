import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const body = await req.json()
    console.log('[programar-recordatorio] recordatorio solicitado:', { tipo: body?.tipo, hasReferencia: !!body?.referencia_id })
    
    // destinatario_email del body se IGNORA a propósito: el email SIEMPRE se deriva server-side de la
    // fila (paciente/visitador). Evita que un caller mande el recordatorio a un email arbitrario.
    const { tipo, referencia_id, horas_antes = 24 } = body

    if (!tipo || !referencia_id) {
      console.error('[programar-recordatorio] Faltan campos:', { tipo, referencia_id })
      return new Response(
        JSON.stringify({ error: 'Faltan campos requeridos: tipo, referencia_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (tipo !== 'cita' && tipo !== 'visita') {
      return new Response(
        JSON.stringify({ error: "tipo debe ser 'cita' o 'visita'" }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // GATE DE OWNERSHIP — auth amplio (paciente/médico/clínica/proveedor), NO super_admin. En vez de un
    // helper nuevo, se lee la fila referenciada con un cliente ANON + JWT del caller: la RLS por-actor de
    // citas/visitas_agendadas ya resuelve "¿es suya?". Si la lectura no devuelve fila (RLS la bloqueó o no
    // existe) → 403. Recién después se usa el service_role (arriba) para derivar datos e insertar.
    const supabaseAnonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY') || ''
    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Falta Authorization' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    })
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) {
      return new Response(
        JSON.stringify({ error: 'JWT inválido' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
    const tablaRef = tipo === 'cita' ? 'citas' : 'visitas_agendadas'
    const { data: filaOwn } = await userClient.from(tablaRef).select('id').eq('id', referencia_id).maybeSingle()
    if (!filaOwn) {
      return new Response(
        JSON.stringify({ error: 'No autorizado sobre esta cita/visita' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    let cita_id: number | null = null
    let visita_id: string | null = null
    let fecha_envio_programada: string
    let mensaje: string
    let emailDestinatario: string | null = null
    let telefonoDestinatario: string | null = null

    if (tipo === 'cita') {
      // Query separada 1: cita
      const { data: cita, error: citaError } = await supabase
        .from('citas')
        .select('*')
        .eq('id', referencia_id)
        .single()

      if (citaError || !cita) {
        console.error('[programar-recordatorio] Error buscando cita:', citaError?.message ?? citaError?.code)
        return new Response(
          JSON.stringify({ error: 'Cita no encontrada' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      cita_id = cita.id

      // Query separada 2: paciente
      const { data: paciente } = await supabase
        .from('pacientes')
        .select('nombre, email, telefono')
        .eq('id', cita.paciente_id)
        .single()

      // Query separada 3: médico
      const { data: medico } = await supabase
        .from('medicos')
        .select('nombre_completo, email')
        .eq('id', cita.medico_id)
        .single()

      const fechaCita = new Date(`${cita.fecha}T${cita.hora_inicio || '00:00:00'}`)
      const fechaEnvio = new Date(fechaCita.getTime() - horas_antes * 60 * 60 * 1000)
      fecha_envio_programada = fechaEnvio.toISOString()

      const pacienteNombre = paciente?.nombre || 'Paciente'
      const medicoNombre = medico?.nombre_completo || 'Médico'
      mensaje = `Hola ${pacienteNombre}, le recordamos su cita médica el ${cita.fecha} a las ${cita.hora_inicio || 'hora por confirmar'} con el Dr. ${medicoNombre}. EzPayConnect`

      if (!emailDestinatario) {
        emailDestinatario = paciente?.email || null
      }
      telefonoDestinatario = paciente?.telefono || null
    } else {
      // tipo === 'visita'
      // Query separada 1: visita
      const { data: visita, error: visitaError } = await supabase
        .from('visitas_agendadas')
        .select('*')
        .eq('id', referencia_id)
        .single()

      if (visitaError || !visita) {
        console.error('[programar-recordatorio] Error buscando visita:', visitaError?.message ?? visitaError?.code)
        return new Response(
          JSON.stringify({ error: 'Visita no encontrada' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      visita_id = visita.id

      // Query separada 2: visitador
      const { data: visitador } = await supabase
        .from('cuentas_proveedor')
        .select('nombre_completo, email, telefono')
        .eq('id', visita.visitador_id)
        .single()

      // Query separada 3: médico
      const { data: medico } = await supabase
        .from('medicos')
        .select('nombre_completo')
        .eq('id', visita.medico_id)
        .single()

      const fechaVisita = new Date(`${visita.fecha_visita}T${visita.hora_inicio || '00:00:00'}`)
      const fechaEnvio = new Date(fechaVisita.getTime() - horas_antes * 60 * 60 * 1000)
      fecha_envio_programada = fechaEnvio.toISOString()

      const visitadorNombre = visitador?.nombre_completo || 'Visitador'
      const medicoNombre = medico?.nombre_completo || 'Médico'
      mensaje = `Hola ${visitadorNombre}, le recordamos su visita programada el ${visita.fecha_visita} a las ${visita.hora_inicio || 'hora por confirmar'} con el Dr. ${medicoNombre}. EzPayConnect`

      if (!emailDestinatario) {
        emailDestinatario = visitador?.email || null
      }
      telefonoDestinatario = visitador?.telefono || null
    }

    const { data: recordatorio, error: recError } = await supabase
      .from('recordatorios')
      .insert({
        tipo,
        cita_id,
        visita_id,
        destinatario_email: emailDestinatario,
        destinatario_telefono: telefonoDestinatario,
        mensaje,
        fecha_envio_programada,
        estado: 'pendiente',
      })
      .select()
      .single()

    if (recError) {
      console.error('[programar-recordatorio] Error insertando:', recError?.message ?? recError?.code)
      return new Response(
        JSON.stringify({ error: 'Error guardando recordatorio', details: recError }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          recordatorio_id: recordatorio.id,
          tipo,
          referencia_id,
          estado: 'pendiente',
          fecha_envio_programada,
          mensaje,
          destinatario_email: emailDestinatario,
        },
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (error: any) {
    console.error('[programar-recordatorio] Error:', error?.message ?? error?.code)
    return new Response(
      JSON.stringify({ error: error.message || 'Error interno' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
