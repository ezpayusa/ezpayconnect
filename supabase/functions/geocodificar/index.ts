import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
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
