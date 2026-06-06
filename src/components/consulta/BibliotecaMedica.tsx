import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { Search, BookOpen, ExternalLink, Loader2, Copy, CheckCircle2 } from 'lucide-react'

interface ResultadoBiblioteca {
  fuente: string
  titulo: string
  extracto?: string
  autores?: string
  fecha?: string
  url: string
  fuente_revista?: string
}

interface BibliotecaMedicaProps {
  onCopiar?: (texto: string) => void
}

export default function BibliotecaMedica({ onCopiar }: BibliotecaMedicaProps) {
  const [query, setQuery] = useState('')
  const [resultados, setResultados] = useState<ResultadoBiblioteca[]>([])
  const [loading, setLoading] = useState(false)
  const [copiadoId, setCopiadoId] = useState<string | null>(null)

  const buscar = async () => {
    if (!query.trim()) return
    setLoading(true)
    try {
      const { data, error } = await supabase.functions.invoke('consultar-biblioteca', {
        body: { query: query.trim(), tipo: 'all' }
      })
      if (error) throw error
      setResultados(data?.resultados || [])
    } catch (e: any) {
      toast.error('Error buscando: ' + e.message)
    } finally {
      setLoading(false)
    }
  }

  const copiar = (r: ResultadoBiblioteca) => {
    const texto = `${r.titulo}\n${r.extracto || r.autores || ''}\nFuente: ${r.fuente}\n${r.url}`
    navigator.clipboard.writeText(texto)
    setCopiadoId(r.url)
    if (onCopiar) onCopiar(texto)
    toast.success('Copiado al portapapeles')
    setTimeout(() => setCopiadoId(null), 2000)
  }

  return (
    <div className="space-y-4">
      <div className="flex gap-2">
        <Input
          placeholder="Buscar en biblioteca medica..."
          value={query}
          onChange={e => setQuery(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && buscar()}
        />
        <Button onClick={buscar} disabled={loading} size="icon">
          {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
        </Button>
      </div>

      {resultados.length === 0 && !loading && query && (
        <p className="text-sm text-muted-foreground text-center py-4">No se encontraron resultados</p>
      )}

      <div className="space-y-3 max-h-[500px] overflow-y-auto">
        {resultados.map((r, i) => (
          <Card key={i} className="border-l-4 border-l-[#1E5C8E]">
            <CardContent className="p-3">
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <Badge variant="outline" className="text-[10px]">
                      {r.fuente === 'pubmed' ? 'PubMed' : 'Wikipedia'}
                    </Badge>
                    {r.fecha && <span className="text-[10px] text-muted-foreground">{r.fecha}</span>}
                  </div>
                  <h4 className="text-sm font-medium leading-tight">{r.titulo}</h4>
                  {r.extracto && (
                    <p className="text-xs text-muted-foreground mt-1 line-clamp-3">{r.extracto}</p>
                  )}
                  {r.autores && (
                    <p className="text-[10px] text-muted-foreground mt-1">{r.autores}</p>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-2 mt-2">
                <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={() => copiar(r)}>
                  {copiadoId === r.url ? <CheckCircle2 className="h-3 w-3 mr-1" /> : <Copy className="h-3 w-3 mr-1" />}
                  {copiadoId === r.url ? 'Copiado' : 'Copiar'}
                </Button>
                <a href={r.url} target="_blank" rel="noopener noreferrer" className="text-xs text-[#1E5C8E] hover:underline flex items-center gap-1">
                  <ExternalLink className="h-3 w-3" /> Ver fuente
                </a>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="flex items-center gap-2 text-[10px] text-muted-foreground pt-2 border-t">
        <BookOpen className="h-3 w-3" />
        Fuentes: PubMed (NCBI) · Wikipedia
      </div>
    </div>
  )
}
