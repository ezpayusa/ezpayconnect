import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { usePacientes } from '@/hooks/usePacientes'
import { useHistorialMedico } from '@/hooks/useHistorialMedico'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'
import { 
  ArrowLeft, User, Calendar, Phone, Mail, MapPin, AlertTriangle, 
  Heart, FileText, Plus, Stethoscope, Clock, ChevronRight 
} from 'lucide-react'

export default function PacienteDetallePage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { pacientes } = usePacientes()
  const { historial, loading: loadingHistorial, createHistorial } = useHistorialMedico(Number(id))

  const [paciente, setPaciente] = useState(pacientes.find(p => p.id === Number(id)))
  const [showNuevaConsulta, setShowNuevaConsulta] = useState(false)
  const [saving, setSaving] = useState(false)

  const [consultaForm, setConsultaForm] = useState({
    fecha: new Date().toISOString().split('T')[0],
    motivo_consulta: '',
    diagnostico: '',
    tratamiento: '',
    notas_medicas: '',
    examenes_solicitados: ''
  })

  useEffect(() => {
    const found = pacientes.find(p => p.id === Number(id))
    if (found) setPaciente(found)
  }, [pacientes, id])

  if (!paciente) {
    return (
      <div className="p-8 text-center">
        <p className="text-[#8a9aaa]">Paciente no encontrado</p>
        <Button onClick={() => navigate('/pacientes')} className="mt-4">
          <ArrowLeft className="h-4 w-4 mr-2" /> Volver a Pacientes
        </Button>
      </div>
    )
  }

  const handleSubmitConsulta = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    const { error } = await createHistorial(consultaForm)
    if (!error) {
      setConsultaForm({
        fecha: new Date().toISOString().split('T')[0],
        motivo_consulta: '',
        diagnostico: '',
        tratamiento: '',
        notas_medicas: '',
        examenes_solicitados: ''
      })
      setShowNuevaConsulta(false)
    }
    setSaving(false)
  }

  const calcularEdad = (fechaNacimiento: string | null) => {
    if (!fechaNacimiento) return 'N/A'
    const hoy = new Date()
    const nacimiento = new Date(fechaNacimiento)
    let edad = hoy.getFullYear() - nacimiento.getFullYear()
    const mes = hoy.getMonth() - nacimiento.getMonth()
    if (mes < 0 || (mes === 0 && hoy.getDate() < nacimiento.getDate())) {
      edad--
    }
    return edad + ' años'
  }

  return (
    <div className="p-8 space-y-6 max-w-6xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <Button variant="outline" size="sm" onClick={() => navigate('/pacientes')}>
            <ArrowLeft className="h-4 w-4 mr-2" /> Volver
          </Button>
          <div>
            <h1 className="text-3xl font-bold text-[#1a2a3a]">
              {paciente.nombre} {paciente.apellido}
            </h1>
            <p className="text-[#8a9aaa]">Expediente Clínico</p>
          </div>
        </div>
        <Button 
          onClick={() => setShowNuevaConsulta(true)} 
          className="bg-[#1E5C8E] hover:bg-[#3A8ABF]"
        >
          <Plus className="h-4 w-4 mr-2" /> Nueva Consulta
        </Button>
      </div>

      {/* Info rápida */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card className="border-l-4 border-l-[#1E5C8E]">
          <CardContent className="p-4 flex items-center gap-3">
            <User className="h-8 w-8 text-[#1E5C8E]" />
            <div>
              <p className="text-xs text-[#8a9aaa]">Edad</p>
              <p className="font-bold">{calcularEdad(paciente.fecha_nacimiento)}</p>
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#3A8ABF]">
          <CardContent className="p-4 flex items-center gap-3">
            <Heart className="h-8 w-8 text-[#3A8ABF]" />
            <div>
              <p className="text-xs text-[#8a9aaa]">Género</p>
              <p className="font-bold capitalize">{paciente.genero || 'N/A'}</p>
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#5BA8D1]">
          <CardContent className="p-4 flex items-center gap-3">
            <Phone className="h-8 w-8 text-[#5BA8D1]" />
            <div>
              <p className="text-xs text-[#8a9aaa]">Teléfono</p>
              <p className="font-bold">{paciente.telefono || 'N/A'}</p>
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#1a2a3a]">
          <CardContent className="p-4 flex items-center gap-3">
            <AlertTriangle className="h-8 w-8 text-[#1a2a3a]" />
            <div>
              <p className="text-xs text-[#8a9aaa]">Alergias</p>
              <p className="font-bold truncate">{paciente.alergias || 'Ninguna'}</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Tabs */}
      <Tabs defaultValue="info" className="w-full">
        <TabsList className="grid w-full grid-cols-3">
          <TabsTrigger value="info">Información General</TabsTrigger>
          <TabsTrigger value="historial">Historial Médico</TabsTrigger>
          <TabsTrigger value="recetas">Recetas</TabsTrigger>
        </TabsList>

        {/* Tab: Información General */}
        <TabsContent value="info" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <User className="h-5 w-5 text-[#1E5C8E]" />
                Datos Personales
              </CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4">
              <div>
                <Label className="text-[#8a9aaa]">Nombre Completo</Label>
                <p className="font-medium">{paciente.nombre} {paciente.apellido}</p>
              </div>
              <div>
                <Label className="text-[#8a9aaa]">Fecha de Nacimiento</Label>
                <p className="font-medium">{paciente.fecha_nacimiento || 'N/A'}</p>
              </div>
              <div>
                <Label className="text-[#8a9aaa]">Email</Label>
                <p className="font-medium">{paciente.email || 'N/A'}</p>
              </div>
              <div>
                <Label className="text-[#8a9aaa]">Teléfono</Label>
                <p className="font-medium">{paciente.telefono || 'N/A'}</p>
              </div>
              <div className="col-span-2">
                <Label className="text-[#8a9aaa]">Dirección</Label>
                <p className="font-medium">{paciente.direccion || 'N/A'}</p>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <AlertTriangle className="h-5 w-5 text-red-500" />
                Información de Emergencia
              </CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4">
              <div>
                <Label className="text-[#8a9aaa]">Contacto de Emergencia</Label>
                <p className="font-medium">{paciente.emergencia_nombre || 'N/A'}</p>
              </div>
              <div>
                <Label className="text-[#8a9aaa]">Teléfono de Emergencia</Label>
                <p className="font-medium">{paciente.emergencia_telefono || 'N/A'}</p>
              </div>
              <div className="col-span-2">
                <Label className="text-[#8a9aaa]">Alergias Conocidas</Label>
                <p className="font-medium text-red-600">{paciente.alergias || 'Ninguna registrada'}</p>
              </div>
              <div className="col-span-2">
                <Label className="text-[#8a9aaa]">Notas Adicionales</Label>
                <p className="font-medium">{paciente.notas || 'Sin notas'}</p>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        {/* Tab: Historial Médico */}
        <TabsContent value="historial" className="space-y-4">
          {loadingHistorial ? (
            <div className="text-center py-8">
              <p className="text-[#8a9aaa]">Cargando historial...</p>
            </div>
          ) : historial.length === 0 ? (
            <div className="text-center py-8">
              <Stethoscope className="h-12 w-12 mx-auto mb-3 text-[#8a9aaa] opacity-50" />
              <p className="text-[#8a9aaa]">No hay consultas registradas</p>
              <Button 
                onClick={() => setShowNuevaConsulta(true)} 
                className="mt-4 bg-[#1E5C8E] hover:bg-[#3A8ABF]"
              >
                <Plus className="h-4 w-4 mr-2" /> Registrar Primera Consulta
              </Button>
            </div>
          ) : (
            <div className="space-y-4">
              {historial.map((consulta) => (
                <Card key={consulta.id} className="border-l-4 border-l-[#1E5C8E]">
                  <CardContent className="p-4">
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-2">
                          <Calendar className="h-4 w-4 text-[#1E5C8E]" />
                          <span className="font-medium">
                            {new Date(consulta.fecha).toLocaleDateString('es-GT', {
                              weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
                            })}
                          </span>
                        </div>

                        {consulta.motivo_consulta && (
                          <div className="mb-2">
                            <span className="text-xs text-[#8a9aaa]">Motivo:</span>
                            <p className="text-sm">{consulta.motivo_consulta}</p>
                          </div>
                        )}

                        {consulta.diagnostico && (
                          <div className="mb-2">
                            <span className="text-xs text-[#8a9aaa]">Diagnóstico:</span>
                            <p className="text-sm font-medium text-[#1E5C8E]">{consulta.diagnostico}</p>
                          </div>
                        )}

                        {consulta.tratamiento && (
                          <div className="mb-2">
                            <span className="text-xs text-[#8a9aaa]">Tratamiento:</span>
                            <p className="text-sm">{consulta.tratamiento}</p>
                          </div>
                        )}

                        {consulta.examenes_solicitados && (
                          <div className="mb-2">
                            <span className="text-xs text-[#8a9aaa]">Exámenes:</span>
                            <p className="text-sm">{consulta.examenes_solicitados}</p>
                          </div>
                        )}

                        {consulta.notas_medicas && (
                          <div className="mt-3 p-3 bg-[#e8f0f8] rounded-lg">
                            <span className="text-xs text-[#8a9aaa]">Notas Médicas:</span>
                            <p className="text-sm mt-1">{consulta.notas_medicas}</p>
                          </div>
                        )}
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </TabsContent>

        {/* Tab: Recetas */}
        <TabsContent value="recetas">
          <Card>
            <CardContent className="p-8 text-center">
              <FileText className="h-12 w-12 mx-auto mb-3 text-[#8a9aaa] opacity-50" />
              <p className="text-[#8a9aaa]">Las recetas del paciente se muestran en la sección de Recetas</p>
              <Button 
                onClick={() => navigate('/recetas')} 
                className="mt-4 bg-[#1E5C8E] hover:bg-[#3A8ABF]"
              >
                Ver Recetas <ChevronRight className="h-4 w-4 ml-2" />
              </Button>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Dialog: Nueva Consulta */}
      <Dialog open={showNuevaConsulta} onOpenChange={setShowNuevaConsulta}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Stethoscope className="h-5 w-5 text-[#1E5C8E]" />
              Nueva Consulta Médica
            </DialogTitle>
          </DialogHeader>

          <form onSubmit={handleSubmitConsulta} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Fecha de Consulta *</Label>
                <Input 
                  type="date" 
                  value={consultaForm.fecha}
                  onChange={e => setConsultaForm({...consultaForm, fecha: e.target.value})}
                  required
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label>Motivo de Consulta</Label>
              <Input 
                value={consultaForm.motivo_consulta}
                onChange={e => setConsultaForm({...consultaForm, motivo_consulta: e.target.value})}
                placeholder="Ej: Dolor de cabeza persistente"
              />
            </div>

            <div className="space-y-2">
              <Label>Diagnóstico</Label>
              <textarea 
                className="w-full border rounded-md p-3 min-h-[80px]"
                value={consultaForm.diagnostico}
                onChange={e => setConsultaForm({...consultaForm, diagnostico: e.target.value})}
                placeholder="Diagnóstico del paciente..."
              />
            </div>

            <div className="space-y-2">
              <Label>Tratamiento</Label>
              <textarea 
                className="w-full border rounded-md p-3 min-h-[80px]"
                value={consultaForm.tratamiento}
                onChange={e => setConsultaForm({...consultaForm, tratamiento: e.target.value})}
                placeholder="Medicamentos, terapias, recomendaciones..."
              />
            </div>

            <div className="space-y-2">
              <Label>Exámenes Solicitados</Label>
              <Input 
                value={consultaForm.examenes_solicitados}
                onChange={e => setConsultaForm({...consultaForm, examenes_solicitados: e.target.value})}
                placeholder="Ej: Hemograma completo, Radiografía de tórax"
              />
            </div>

            <div className="space-y-2">
              <Label>Notas Médicas Privadas</Label>
              <textarea 
                className="w-full border rounded-md p-3 min-h-[80px]"
                value={consultaForm.notas_medicas}
                onChange={e => setConsultaForm({...consultaForm, notas_medicas: e.target.value})}
                placeholder="Observaciones internas del médico..."
              />
            </div>

            <div className="flex justify-end gap-3">
              <Button type="button" variant="outline" onClick={() => setShowNuevaConsulta(false)}>
                Cancelar
              </Button>
              <Button 
                type="submit" 
                className="bg-[#1E5C8E] hover:bg-[#3A8ABF]"
                disabled={saving}
              >
                {saving ? 'Guardando...' : 'Guardar Consulta'}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}
