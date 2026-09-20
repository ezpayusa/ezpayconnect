import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // ---------------------------------------------------------------------------------------
  // GATE DE SESIÓN. `verify_jwt = true` en el gateway NO alcanza: medido el 20-sep contra el
  // deploy real, esta función respondía 200 con sólo la key pública e incluso SIN header
  // Authorization. O sea que cualquiera con la key que viaja en el bundle podía usarla como
  // proxy de geocodificación y gastar GOOGLE_MAPS_API_KEY.
  //
  // El gate valida el JWT contra el auth server con un cliente anon + el token del caller
  // (mismo patrón que dictado-voz / asistente-ia / invitar-visitador). La key pública NO es
  // un usuario, así que getUser() la rechaza. Va ANTES de leer el body y antes de cualquier
  // fetch saliente: el objetivo es no gastar la cuota, no sólo no devolver el resultado.
  //
  // Los dos callers (useUbicacionesMedico.ts:121 y useEntregasMonitoreo.ts:120) corren dentro
  // de paneles con sesión de Supabase Auth (useProveedorAuth usa signInWithPassword), y
  // `supabase.functions.invoke` manda el access_token de esa sesión. No se rompe ninguno.
  // ---------------------------------------------------------------------------------------
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim()
  if (!jwt) {
    return json({ error: 'No autorizado' }, 401)
  }

  const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY')
  if (!supabaseUrl || !anonKey) {
    console.error('[geocodificar] faltan SB_URL/SB_ANON_KEY')
    return json({ error: 'Configuración incompleta' }, 500)
  }

  const supa = createClient(supabaseUrl, anonKey, { auth: { persistSession: false } })
  const { data: { user }, error: authError } = await supa.auth.getUser(jwt)
  if (authError || !user) {
    return json({ error: 'No autorizado' }, 401)
  }

  try {
    const { direccion } = await req.json()
    if (!direccion || typeof direccion !== 'string') {
      return new Response(JSON.stringify({ error: 'Dirección requerida' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      })
    }

    const googleApiKey = Deno.env.get('GOOGLE_MAPS_API_KEY')
    let result: { lat: number; lng: number; display_name: string } | null = null

    // 1. Intentar Google Maps Geocoding si hay API key
    if (googleApiKey) {
      try {
        const gUrl = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(direccion)}&key=${googleApiKey}&region=gt`
        const gRes = await fetch(gUrl)
        const gData = await gRes.json()
        if (gData.status === 'OK' && gData.results && gData.results.length > 0) {
          const loc = gData.results[0].geometry.location
          result = {
            lat: loc.lat,
            lng: loc.lng,
            display_name: gData.results[0].formatted_address,
          }
        }
      } catch (e) {
        console.error('Google Maps error:', e)
      }
    }

    // 2. Fallback a Nominatim (OpenStreetMap) si Google falla o no hay API key
    if (!result) {
      const url = `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(direccion)}&limit=1&countrycodes=gt`
      const res = await fetch(url, {
        headers: {
          'User-Agent': 'EzPayConnect/1.0 (ezpayconnect.com)',
          'Accept': 'application/json',
        },
      })

      if (res.ok) {
        const data = await res.json()
        if (Array.isArray(data) && data.length > 0) {
          result = {
            lat: parseFloat(data[0].lat),
            lng: parseFloat(data[0].lon),
            display_name: data[0].display_name,
          }
        }
      }
    }

    if (!result) {
      return new Response(JSON.stringify({ error: 'No se encontraron resultados' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      })
    }

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  }
})
