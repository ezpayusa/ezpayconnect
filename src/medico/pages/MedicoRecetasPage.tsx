import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/hooks/useAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import {
  FileText,
  Search,
  Loader2,
  RefreshCw,
  User,
  CalendarDays,
  Eye,
  Printer,
  ArrowLeft,
} from 'lucide-react'
import { imprimirPDFReceta } from '@/lib/pdfReceta'
import RecetaModal from '@/components/consulta/RecetaModal'

interface RecetaConPaciente {
  id: number
  paciente_id: number
  estado: string
  instrucciones_generales: string | null
  created_at: string
  paciente: {
    nombre: string
    apellido: string
  } | null
}

export default function MedicoRecetasPage() {
  const navigate = useNavigate()
  const { perfil } = useAuth()
  const [recetas, setRecetas] = useState<RecetaConPaciente[]>([])
  const [loading, setLoading] = useState(true)
  const [busqueda, setBusqueda] = useState('')
  const [imprimiendo, setImprimiendo] = useState<number | null>(null)
  const [showNueva, setShowNueva] = useState(false)

  const cargarRecetas = useCallback(async () => {
    if (!perfil?.id) return
    setLoading(true)
    try {
      const { data, error } = await supabase
        .from('recetas')
        .select(`
          id,
          paciente_id,
          estado,
          instrucciones_generales,
          created_at,
          paciente:pacientes(nombre, apellido)
        `)
        .eq('medico_id', perfil.id)
        .order('created_at', { ascending: false })

      if (error) throw error

      const formateadas = (data || []).map((r: any) => ({
        ...r,
        paciente: r.paciente ? {
          nombre: r.paciente.nombre,
          apellido: r.paciente.apellido,
        } : null,
      }))
      setRecetas(formateadas)
    } catch (err) {
      console.error('Error cargando recetas:', err?.message ?? err?.code)
    } finally {
      setLoading(false)
    }
  }, [perfil?.id])

  useEffect(() => {
    cargarRecetas()
  }, [cargarRecetas])

  const handleImprimir = async (receta: RecetaConPaciente) => {
    if (!perfil) return
    setImprimiendo(receta.id)
    try {
      const [{ data: items }, { data: pacienteCompleto }] = await Promise.all([
        supabase.from('receta_items').select('*').eq('receta_id', receta.id),
        supabase.from('pacientes').select('*').eq('id', receta.paciente_id).single(),
      ])

      if (!pacienteCompleto) {
        console.error('Error imprimiendo: paciente no encontrado')
        return
      }

      imprimirPDFReceta(receta as any, items || [], pacienteCompleto as any, perfil)
    } catch (e: any) {
      console.error('Error imprimiendo:', e?.message ?? e?.code)
    } finally {
      setImprimiendo(null)
    }
  }

  const recetasFiltradas = recetas.filter((r) => {
    const q = busqueda.toLowerCase()
    const nombrePaciente = r.paciente
      ? `${r.paciente.nombre} ${r.paciente.apellido}`.toLowerCase()
      : ''
    return nombrePaciente.includes(q) || String(r.id).includes(q)
  })

  const getEstadoBadge = (estado: string) => {
    switch (estado) {
      case 'activa': return <Badge className="bg-emerald-100 text-emerald-700">Activa</Badge>
      case 'completada': return <Badge className="bg-blue-100 text-blue-700">Completada</Badge>
      case 'vencida': return <Badge className="bg-amber-100 text-amber-700">Vencida</Badge>
      case 'cancelada': return <Badge className="bg-red-100 text-red-700">Cancelada</Badge>
      default: return <Badge variant="secondary">{estado}</Badge>
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <Loader2 className="h-10 w-10 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center flex-wrap gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate('/medico')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1 min-w-0">
          <h1 className="text-2xl font-bold text-[#1a2a3a] flex items-center gap-2">
            <FileText className="h-7 w-7 text-[#1E5C8E]" />
            Mis Recetas
          </h1>
          <p className="text-sm text-muted-foreground">
            {recetas.length} recetas emitidas
          </p>
        </div>
        <div className="flex gap-2 w-full sm:w-auto sm:ml-auto">
          <Button size="sm" onClick={() => setShowNueva(true)}>
            <FileText className="h-4 w-4 mr-1" />
            Nueva Receta
          </Button>
          <Button variant="outline" size="sm" onClick={cargarRecetas}>
            <RefreshCw className="h-4 w-4 mr-1" />
            Recargar
          </Button>
        </div>
      </div>

      {/* Búsqueda */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          placeholder="Buscar por paciente o número de receta..."
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
          className="pl-9"
        />
      </div>

      {/* Listado */}
      <div className="space-y-3">
        {recetasFiltradas.length === 0 ? (
          <div className="text-center py-16 bg-white rounded-xl border border-dashed">
            <FileText className="h-12 w-12 mx-auto mb-4 text-gray-300" />
            <p className="text-lg font-medium text-gray-500">
              {busqueda ? 'No se encontraron recetas' : 'No has emitido recetas'}
            </p>
          </div>
        ) : (
          recetasFiltradas.map((r) => (
            <Card key={r.id} className="transition-shadow hover:shadow-sm">
              <CardContent className="p-4">
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap mb-1">
                      {getEstadoBadge(r.estado)}
                      <Badge variant="outline" className="text-xs">
                        <CalendarDays className="h-3 w-3 mr-1" />
                        {new Date(r.created_at).toLocaleDateString('es-GT')}
                      </Badge>
                    </div>
                    <div className="flex items-center gap-2">
                      <User className="h-4 w-4 text-muted-foreground" />
                      <span className="font-medium">
                        {r.paciente
                          ? `${r.paciente.nombre} ${r.paciente.apellido}`
                          : `Paciente #${r.paciente_id}`}
                      </span>
                    </div>
                    {r.instrucciones_generales && (
                      <p className="text-sm text-muted-foreground mt-1 line-clamp-2">
                        {r.instrucciones_generales}
                      </p>
                    )}
                  </div>
                  <div className="flex flex-col gap-2">
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => navigate(`/recetas/${r.id}`)}
                    >
                      <Eye className="h-4 w-4 mr-1" />
                      Ver
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => handleImprimir(r)}
                      disabled={imprimiendo === r.id}
                    >
                      {imprimiendo === r.id ? (
                        <Loader2 className="h-4 w-4 animate-spin mr-1" />
                      ) : (
                        <Printer className="h-4 w-4 mr-1" />
                      )}
                      Imprimir
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>
      <RecetaModal
        open={showNueva}
        onOpenChange={setShowNueva}
        onSuccess={cargarRecetas}
      />
    </div>
  )
}
