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

interface BibliotecaQuery {
  query: string
  tipo: 'pubmed' | 'wikipedia' | 'all'
}

async function buscarPubMed(query: string) {
  try {
    // ESearch: buscar IDs
    const searchUrl = `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=${encodeURIComponent(query)}&retmax=5&retmode=json`
    const searchRes = await fetch(searchUrl)
    const searchData = await searchRes.json()
    const ids = searchData.esearchresult?.idlist || []

    if (ids.length === 0) return []

    // ESummary: obtener resúmenes
    const summaryUrl = `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=${ids.join(',')}&retmode=json`
    const summaryRes = await fetch(summaryUrl)
    const summaryData = await summaryRes.json()

    return ids.map((id: string) => {
      const doc = summaryData.result?.[id]
      return {
        fuente: 'pubmed',
        id,
        titulo: doc?.title || 'Sin título',
        autores: (doc?.authors || []).map((a: any) => a.name).join(', '),
        fecha: doc?.pubdate || '',
        fuente_revista: doc?.source || '',
        url: `https://pubmed.ncbi.nlm.nih.gov/${id}/`,
      }
    })
  } catch (e) {
    console.error('Error PubMed:', e)
    return []
  }
}

async function buscarWikipedia(query: string) {
  try {
    const url = `https://es.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(query.replace(/\s+/g, '_'))}`
    const res = await fetch(url)
    if (!res.ok) {
      // Si no encuentra exacto, buscar con search
      const searchUrl = `https://es.wikipedia.org/w/api.php?action=query&list=search&srsearch=${encodeURIComponent(query)}&srlimit=3&format=json&origin=*`
      const searchRes = await fetch(searchUrl)
      const searchData = await searchRes.json()
      const results = searchData.query?.search || []

      return results.map((r: any) => ({
        fuente: 'wikipedia',
        titulo: r.title,
        extracto: r.snippet.replace(/<[^>]*>/g, ''),
        url: `https://es.wikipedia.org/wiki/${encodeURIComponent(r.title.replace(/\s+/g, '_'))}`,
      }))
    }

    const data = await res.json()
    return [{
      fuente: 'wikipedia',
      titulo: data.title,
      extracto: data.extract,
      url: data.content_urls?.desktop?.page || `https://es.wikipedia.org/wiki/${encodeURIComponent(data.title.replace(/\s+/g, '_'))}`,
      imagen: data.thumbnail?.source || null,
    }]
  } catch (e) {
    console.error('Error Wikipedia:', e)
    return []
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // ---------------------------------------------------------------------------------------
  // GATE DE SESIÓN. `verify_jwt = true` en el gateway NO alcanza: medido el 20-sep contra el
  // deploy real, esta función pasaba el gateway con la sola key pública (la que viaja en el
  // bundle) y llegaba a su propia validación de body — o sea que cualquiera podía usarla como
  // proxy a PubMed y Wikipedia. Sin costo directo, a diferencia de geocodificar, pero el mismo
  // defecto: la IP que consulta esas APIs es la nuestra, y ellas aplican rate limit por IP.
  //
  // Mismo patrón que geocodificar / dictado-voz / asistente-ia: cliente anon + el JWT del
  // caller y getUser(). Va ANTES de leer el body y antes de cualquier fetch saliente.
  //
  // Caller único: src/components/consulta/BibliotecaMedica.tsx:34, montado en ConsultaPage
  // (rutas /consulta/:citaId bajo PrivateLayout y /medico/consulta/:citaId), o sea siempre con
  // sesión de médico. `supabase.functions.invoke` manda el access_token de esa sesión.
  // ---------------------------------------------------------------------------------------
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim()
  if (!jwt) {
    return json({ error: 'No autorizado' }, 401)
  }

  const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY')
  if (!supabaseUrl || !anonKey) {
    console.error('[consultar-biblioteca] faltan SB_URL/SB_ANON_KEY')
    return json({ error: 'Configuración incompleta' }, 500)
  }

  const supa = createClient(supabaseUrl, anonKey, { auth: { persistSession: false } })
  const { data: { user }, error: authError } = await supa.auth.getUser(jwt)
  if (authError || !user) {
    return json({ error: 'No autorizado' }, 401)
  }

  try {
    const { query, tipo = 'all' } = (await req.json()) as BibliotecaQuery

    if (!query || query.trim().length < 2) {
      return new Response(JSON.stringify({ error: 'Query muy corta' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    let resultados: any[] = []

    if (tipo === 'all' || tipo === 'pubmed') {
      const pubmed = await buscarPubMed(query)
      resultados = [...resultados, ...pubmed]
    }

    if (tipo === 'all' || tipo === 'wikipedia') {
      const wiki = await buscarWikipedia(query)
      resultados = [...resultados, ...wiki]
    }

    return new Response(JSON.stringify({ resultados, query }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Error consultar-biblioteca:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
