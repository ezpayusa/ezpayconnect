import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

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
