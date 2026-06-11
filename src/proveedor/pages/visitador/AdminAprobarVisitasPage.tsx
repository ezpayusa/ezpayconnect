import { useState } from 'react'
import { useVisitasAgendadas } from '@/proveedor/hooks/useVisitasAgendadas'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Separator } from '@/components/ui/separator'
import { toast } from 'sonner'
import { 
  CheckCircle, XCircle, Clock, Calendar, MapPin, User, 
  AlertTriangle, ChevronDown, ChevronUp, Edit3 
} from 'lucide-react'

export default function AdminAprobarVisitasPage() {
  const { visitas, loading, saving, administrarVisita, fetchVisitas } = useVisitasAgendadas()
  const { cuenta, puede } = useProveedorAuth()
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [modificandoId, setModificandoId] = useState<string | null>(null)
  const [nuevaFecha, setNuevaFecha] = useState('')
  const [nuevaHoraInicio, setNuevaHoraInicio] = useState('')
  const [nuevaHoraFin, setNuevaHoraFin] = useState('')
  const [comentario, setComentario] = useState('')

  const esAdmin = puede('visitas.aprobar')
  
  if (!esAdmin) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="mx-auto h-12 w-12 text-amber-500 mb-4" />
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">Solo administradores pueden aprobar visitas.</p>
      </div>
    )
  }

  const propuestas = visitas.filter((v) => v.estado === 'propuesta')
  const confirmadas = visitas.filter((v) => v.estado === 'confirmada' || v.estado === 'aprobada')
  const rechazadas = visitas.filter((v) => v.estado === 'rechazada')

  const handleAprobar = async (id: string) => {
    const ok = await administrarVisita(id, 'aprobar')
    if (ok) setExpandedId(null)
  }

  const handleRechazar = async (id: string) => {
    const ok = await administrarVisita(id, 'rechazar', { comentario: comentario || undefined })
    if (ok) { setExpandedId(null); setComentario('') }
  }

  const handleModificar = async (id: string) => {
    const ok = await administrarVisita(id, 'modificar', {
      fecha_visita: nuevaFecha || undefined,
      hora_inicio: nuevaHoraInicio || undefined,
      hora_fin: nuevaHoraFin || undefined,
      comentario: comentario || undefined,
    })
    if (ok) {
      setModificandoId(null)
      setExpandedId(null)
      setNuevaFecha('')
      setNuevaHoraInicio('')
      setNuevaHoraFin('')
      setComentario('')
    }
  }

  const getEstadoBadge = (estado: string) => {
    switch (estado) {
      case 'propuesta': return <Badge variant="outline" className="border-amber-500 text-amber-600"><Clock className="w-3 h-3 mr-1" />Propuesta</Badge>
      case 'confirmada': return <Badge variant="default" className="bg-green-600"><CheckCircle className="w-3 h-3 mr-1" />Confirmada</Badge>
      case 'aprobada': return <Badge variant="default" className="bg-blue-600"><CheckCircle className="w-3 h-3 mr-1" />Aprobada</Badge>
      case 'rechazada': return <Badge variant="destructive"><XCircle className="w-3 h-3 mr-1" />Rechazada</Badge>
      case 'completada': return <Badge variant="secondary"><CheckCircle className="w-3 h-3 mr-1" />Completada</Badge>
      case 'cancelada': return <Badge variant="outline" className="text-muted-foreground"><XCircle className="w-3 h-3 mr-1" />Cancelada</Badge>
      default: return <Badge variant="outline">{estado}</Badge>
    }
  }

  const renderVisitaCard = (visita: any) => {
    const isExpanded = expandedId === visita.id
    const isModificando = modificandoId === visita.id

    return (
      <Card key={visita.id} className={isExpanded ? 'border-primary' : ''}>
        <CardContent className="p-4">
          <div className="flex items-start justify-between">
            <div className="flex-1">
              <div className="flex items-center gap-2 mb-1">
                {getEstadoBadge(visita.estado)}
                <span className="text-sm text-muted-foreground">
                  <Calendar className="w-3 h-3 inline mr-1" />
                  {visita.fecha_visita} · {visita.hora_inicio?.slice(0,5)} - {visita.hora_fin?.slice(0,5)}
                </span>
              </div>
              <h3 className="font-semibold">{visita.medico?.nombre_completo || 'Médico'}</h3>
              <p className="text-sm text-muted-foreground">
                <User className="w-3 h-3 inline mr-1" />
                Propuesta por: {visita.visitador?.nombre_completo || 'Visitador'}
              </p>
              {visita.notas_empresa && (
                <p className="text-sm mt-1 text-muted-foreground italic">"{visita.notas_empresa}"</p>
              )}
            </div>
            <Button variant="ghost" size="sm" onClick={() => setExpandedId(isExpanded ? null : visita.id)}>
              {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
            </Button>
          </div>

          {isExpanded && (
            <div className="mt-4 space-y-3 border-t pt-3">
              {visita.estado === 'propuesta' && (
                <>
                  {isModificando ? (
                    <div className="space-y-3 bg-muted/50 p-3 rounded-lg">
                      <h4 className="text-sm font-medium flex items-center gap-2">
                        <Edit3 className="w-4 h-4" /> Modificar visita
                      </h4>
                      <div className="grid grid-cols-3 gap-2">
                        <div>
                          <label className="text-xs text-muted-foreground">Fecha</label>
                          <input
                            type="date"
                            className="w-full text-sm border rounded px-2 py-1"
                            value={nuevaFecha}
                            onChange={(e) => setNuevaFecha(e.target.value)}
                          />
                        </div>
                        <div>
                          <label className="text-xs text-muted-foreground">Inicio</label>
                          <input
                            type="time"
                            className="w-full text-sm border rounded px-2 py-1"
                            value={nuevaHoraInicio}
                            onChange={(e) => setNuevaHoraInicio(e.target.value)}
                          />
                        </div>
                        <div>
                          <label className="text-xs text-muted-foreground">Fin</label>
                          <input
                            type="time"
                            className="w-full text-sm border rounded px-2 py-1"
                            value={nuevaHoraFin}
                            onChange={(e) => setNuevaHoraFin(e.target.value)}
                          />
                        </div>
                      </div>
                      <textarea
                        className="w-full text-sm border rounded px-2 py-1"
                        rows={2}
                        placeholder="Comentario para el visitador..."
                        value={comentario}
                        onChange={(e) => setComentario(e.target.value)}
                      />
                      <div className="flex gap-2">
                        <Button size="sm" onClick={() => handleModificar(visita.id)} disabled={saving}>
                          Guardar y Confirmar
                        </Button>
                        <Button size="sm" variant="outline" onClick={() => setModificandoId(null)}>
                          Cancelar
                        </Button>
                      </div>
                    </div>
                  ) : (
                    <div className="flex flex-wrap gap-2">
                      <Button size="sm" onClick={() => handleAprobar(visita.id)} disabled={saving}>
                        <CheckCircle className="w-4 h-4 mr-1" /> Aprobar
                      </Button>
                      <Button size="sm" variant="outline" onClick={() => { 
                        setModificandoId(visita.id)
                        setNuevaFecha(visita.fecha_visita)
                        setNuevaHoraInicio(visita.hora_inicio)
                        setNuevaHoraFin(visita.hora_fin)
                      }} disabled={saving}>
                        <Edit3 className="w-4 h-4 mr-1" /> Modificar y Aprobar
                      </Button>
                      <Button size="sm" variant="destructive" onClick={() => handleRechazar(visita.id)} disabled={saving}>
                        <XCircle className="w-4 h-4 mr-1" /> Rechazar
                      </Button>
                    </div>
                  )}
                </>
              )}

              {visita.comentario_admin && (
                <div className="text-sm bg-blue-50 text-blue-800 p-2 rounded">
                  <strong>Comentario admin:</strong> {visita.comentario_admin}
                </div>
              )}

              {visita.fecha_aprobacion && (
                <p className="text-xs text-muted-foreground">
                  Aprobada el {new Date(visita.fecha_aprobacion).toLocaleDateString()}
                </p>
              )}
            </div>
          )}
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="p-4 max-w-4xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Aprobación de Visitas</h1>
          <p className="text-muted-foreground">Revisa, aprueba o rechaza las visitas propuestas por tus visitadores.</p>
        </div>
        <Button variant="outline" onClick={fetchVisitas} disabled={loading}>
          {loading ? '...' : 'Actualizar'}
        </Button>
      </div>

      <Tabs defaultValue="propuestas">
        <TabsList className="grid w-full grid-cols-3">
          <TabsTrigger value="propuestas">
            Propuestas {propuestas.length > 0 && <Badge variant="secondary" className="ml-1">{propuestas.length}</Badge>}
          </TabsTrigger>
          <TabsTrigger value="confirmadas">
            Confirmadas {confirmadas.length > 0 && <Badge variant="secondary" className="ml-1">{confirmadas.length}</Badge>}
          </TabsTrigger>
          <TabsTrigger value="rechazadas">
            Rechazadas {rechazadas.length > 0 && <Badge variant="secondary" className="ml-1">{rechazadas.length}</Badge>}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="propuestas" className="space-y-3 mt-4">
          {propuestas.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <CheckCircle className="mx-auto h-10 w-10 mb-3 text-green-500" />
              <p>No hay visitas pendientes de aprobación.</p>
              <p className="text-sm">Los visitadores proponen visitas y aparecen aquí.</p>
            </div>
          ) : (
            propuestas.map(renderVisitaCard)
          )}
        </TabsContent>

        <TabsContent value="confirmadas" className="space-y-3 mt-4">
          {confirmadas.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <Calendar className="mx-auto h-10 w-10 mb-3" />
              <p>No hay visitas confirmadas.</p>
            </div>
          ) : (
            confirmadas.map(renderVisitaCard)
          )}
        </TabsContent>

        <TabsContent value="rechazadas" className="space-y-3 mt-4">
          {rechazadas.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <XCircle className="mx-auto h-10 w-10 mb-3" />
              <p>No hay visitas rechazadas.</p>
            </div>
          ) : (
            rechazadas.map(renderVisitaCard)
          )}
        </TabsContent>
      </Tabs>
    </div>
  )
}
