import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { usePacientes } from '@/hooks/usePacientes'
import { useCitas } from '@/hooks/useCitas'
import { useHistorialMedico } from '@/hooks/useHistorialMedico'
import { useRecetas } from '@/hooks/useRecetas'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Textarea } from '@/components/ui/textarea'
import { Calendar, Stethoscope, FileText, User, ArrowLeft, Plus, Mail, Phone, MapPin, Clock } from 'lucide-react'
import TimelineHistorial from '@/components/TimelineHistorial'

export default function PacienteDetallePage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { pacientes, loading } = usePacientes()
  const { citas } = useCitas()
  const { historial, loading: loadingHistorial, createHistorial } = useHistorialMedico(Number(id))
  const { recetas } = useRecetas()

  const [activeTab, setActiveTab] = useState('info')
  const [showNuevaConsulta, setShowNuevaConsulta] = useState(false)
  const [nuevaConsulta, setNuevaConsulta] = useState({
    fecha: new Date().toISOString().split('T')[0],
    motivo_consulta: '',
    diagnostico: '',
    tratamiento: '',
    notas_medicas: '',
    examenes_solicitados: ''
  })

  const paciente = pacientes.find(p => p.id === Number(id))
  const citasPaciente = citas?.filter(c => c.paciente_id === Number(id)) || []
  const recetasPaciente = recetas?.filter(r => r.paciente_id === Number(id)) || []

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  if (!paciente) {
    return (
      <div className="p-8">
        <Button variant="ghost" onClick={() => navigate('/pacientes')}>
          <ArrowLeft className="h-4 w-4 mr-2" /> Volver
        </Button>
        <p className="mt-4 text-[#8a9aaa]">Paciente no encontrado</p>
      </div>
    )
  }

  const handleGuardarConsulta = async () => {
    const { error } = await createHistorial(nuevaConsulta)
    if (!error) {
      setShowNuevaConsulta(false)
      setNuevaConsulta({
        fecha: new Date().toISOString().split('T')[0],
        motivo_consulta: '',
        diagnostico: '',
        tratamiento: '',
        notas_medicas: '',
        examenes_solicitados: ''
      })
    }
  }

  return (
    <div className="p-8 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <Button variant="ghost" onClick={() => navigate('/pacientes')} className="mb-2">
            <ArrowLeft className="h-4 w-4 mr-2" /> Volver a Pacientes
          </Button>
          <h1 className="text-3xl font-bold text-[#1a2a3a] flex items-center gap-3">
            <User className="h-8 w-8 text-[#1E5C8E]" />
            {paciente.nombre} {paciente.apellido}
          </h1>
          <p className="text-[#8a9aaa] mt-1">Ficha médica completa</p>
        </div>
        <div className="flex gap-2">
          <Button onClick={() => setShowNuevaConsulta(true)} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
            <Plus className="h-4 w-4 mr-2" /> Nueva Consulta
          </Button>
        </div>
      </div>

      {/* Info rápida */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="border-l-4 border-l-[#1E5C8E]">
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <Phone className="h-5 w-5 text-[#1E5C8E]" />
              <div>
                <p className="text-xs text-[#8a9aaa]">Teléfono</p>
                <p className="font-medium">{paciente.telefono || 'No registrado'}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#3A8ABF]">
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <Mail className="h-5 w-5 text-[#3A8ABF]" />
              <div>
                <p className="text-xs text-[#8a9aaa]">Email</p>
                <p className="font-medium">{paciente.email || 'No registrado'}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#5BA8D1]">
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <MapPin className="h-5 w-5 text-[#5BA8D1]" />
              <div>
                <p className="text-xs text-[#8a9aaa]">Dirección</p>
                <p className="font-medium">{paciente.direccion || 'No registrada'}</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList className="bg-[#e8f0f8] p-1">
          <TabsTrigger value="info" className="flex items-center gap-2">
            <User className="h-4 w-4" /> Información
          </TabsTrigger>
          <TabsTrigger value="historial" className="flex items-center gap-2">
            <Stethoscope className="h-4 w-4" /> Historial Médico
          </TabsTrigger>
          <TabsTrigger value="citas" className="flex items-center gap-2">
            <Calendar className="h-4 w-4" /> Citas
          </TabsTrigger>
          <TabsTrigger value="recetas" className="flex items-center gap-2">
            <FileText className="h-4 w-4" /> Recetas
          </TabsTrigger>
        </TabsList>

        {/* Tab: Información */}
        <TabsContent value="info" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Datos Personales</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <Label className="text-xs text-[#8a9aaa]">Nombre Completo</Label>
                <p className="font-medium">{paciente.nombre} {paciente.apellido}</p>
              </div>
              <div>
                <Label className="text-xs text-[#8a9aaa]">Fecha de Nacimiento</Label>
                <p className="font-medium">{paciente.fecha_nacimiento || 'No registrada'}</p>
              </div>
              <div>
                <Label className="text-xs text-[#8a9aaa]">Género</Label>
                <p className="font-medium">{paciente.genero || 'No registrado'}</p>
              </div>
              <div>
                <Label className="text-xs text-[#8a9aaa]">Tipo de Sangre</Label>
                <p className="font-medium">{paciente.tipo_sangre || 'No registrado'}</p>
              </div>
              <div className="md:col-span-2">
                <Label className="text-xs text-[#8a9aaa]">Alergias</Label>
                <p className="font-medium">{paciente.alergias || 'Ninguna registrada'}</p>
              </div>
              <div className="md:col-span-2">
                <Label className="text-xs text-[#8a9aaa]">Notas</Label>
                <p className="font-medium">{paciente.notas || 'Sin notas'}</p>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        {/* Tab: Historial Médico - NUEVO TIMELINE */}
        <TabsContent value="historial" className="space-y-4">
          <TimelineHistorial pacienteId={Number(id)} />
        </TabsContent>

        {/* Tab: Citas */}
        <TabsContent value="citas" className="space-y-4">
          {citasPaciente.length === 0 ? (
            <Card className="bg-[#f8fafc]">
              <CardContent className="p-8 text-center">
                <Calendar className="h-12 w-12 mx-auto mb-4 text-[#8a9aaa]" />
                <p className="text-[#8a9aaa]">No hay citas registradas</p>
              </CardContent>
            </Card>
          ) : (
            <div className="space-y-3">
              {citasPaciente.map(cita => (
                <Card key={cita.id} className="hover:shadow-md transition-shadow">
                  <CardContent className="p-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="flex items-center gap-2 mb-1">
                          <Calendar className="h-4 w-4 text-[#1E5C8E]" />
                          <span className="font-medium">{cita.fecha}</span>
                          <span className="text-[#8a9aaa]">{cita.hora_inicio}</span>
                        </div>
                        <p className="text-sm text-[#8a9aaa]">{cita.motivo || 'Consulta general'}</p>
                      </div>
                      <Badge variant="outline" className={
                        cita.estado === 'completada' ? 'bg-green-100 text-green-700' :
                        cita.estado === 'cancelada' ? 'bg-red-100 text-red-700' :
                        'bg-blue-100 text-blue-700'
                      }>
                        {cita.estado}
                      </Badge>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </TabsContent>

        {/* Tab: Recetas */}
        <TabsContent value="recetas" className="space-y-4">
          {recetasPaciente.length === 0 ? (
            <Card className="bg-[#f8fafc]">
              <CardContent className="p-8 text-center">
                <FileText className="h-12 w-12 mx-auto mb-4 text-[#8a9aaa]" />
                <p className="text-[#8a9aaa]">No hay recetas registradas</p>
              </CardContent>
            </Card>
          ) : (
            <div className="space-y-3">
              {recetasPaciente.map(receta => (
                <Card key={receta.id} className="hover:shadow-md transition-shadow">
                  <CardContent className="p-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="flex items-center gap-2 mb-1">
                          <FileText className="h-4 w-4 text-[#1E5C8E]" />
                          <span className="font-medium">Receta #{receta.id}</span>
                        </div>
                        <p className="text-sm text-[#8a9aaa]">{receta.instrucciones_generales || 'Sin instrucciones'}</p>
                      </div>
                      <Badge variant="outline" className={
                        receta.estado === 'activa' ? 'bg-green-100 text-green-700' :
                        'bg-gray-100 text-gray-700'
                      }>
                        {receta.estado}
                      </Badge>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </TabsContent>
      </Tabs>

      {/* Dialog: Nueva Consulta */}
      <Dialog open={showNuevaConsulta} onOpenChange={setShowNuevaConsulta}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Stethoscope className="h-5 w-5 text-[#1E5C8E]" />
              Nueva Consulta Médica
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Fecha</Label>
              <Input
                type="date"
                value={nuevaConsulta.fecha}
                onChange={e => setNuevaConsulta(prev => ({ ...prev, fecha: e.target.value }))}
              />
            </div>
            <div className="space-y-2">
              <Label>Motivo de Consulta</Label>
              <Input
                value={nuevaConsulta.motivo_consulta}
                onChange={e => setNuevaConsulta(prev => ({ ...prev, motivo_consulta: e.target.value }))}
                placeholder="Ej: Dolor de cabeza, fiebre..."
              />
            </div>
            <div className="space-y-2">
              <Label>Diagnóstico</Label>
              <Input
                value={nuevaConsulta.diagnostico}
                onChange={e => setNuevaConsulta(prev => ({ ...prev, diagnostico: e.target.value }))}
                placeholder="Diagnóstico médico"
              />
            </div>
            <div className="space-y-2">
              <Label>Tratamiento</Label>
              <Textarea
                value={nuevaConsulta.tratamiento}
                onChange={e => setNuevaConsulta(prev => ({ ...prev, tratamiento: e.target.value }))}
                placeholder="Medicamentos, terapias, recomendaciones..."
                rows={3}
              />
            </div>
            <div className="space-y-2">
              <Label>Exámenes Solicitados</Label>
              <Input
                value={nuevaConsulta.examenes_solicitados}
                onChange={e => setNuevaConsulta(prev => ({ ...prev, examenes_solicitados: e.target.value }))}
                placeholder="Ej: Sangre, orina, rayos X..."
              />
            </div>
            <div className="space-y-2">
              <Label>Notas Médicas</Label>
              <Textarea
                value={nuevaConsulta.notas_medicas}
                onChange={e => setNuevaConsulta(prev => ({ ...prev, notas_medicas: e.target.value }))}
                placeholder="Observaciones adicionales..."
                rows={2}
              />
            </div>
            <div className="flex justify-end gap-3">
              <Button variant="outline" onClick={() => setShowNuevaConsulta(false)}>
                Cancelar
              </Button>
              <Button onClick={handleGuardarConsulta} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
                Guardar Consulta
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}