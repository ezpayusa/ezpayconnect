import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useDisponibilidadMedico } from '@/hooks/useDisponibilidadMedico'
import { useClinicas } from '@/hooks/useClinicas'
import { ArrowLeft, Plus, Trash2, Loader2, Clock } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'

const DIAS = [
  'Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'
]

export default function MedicoDisponibilidadPage() {
  const navigate = useNavigate()
  const { disponibilidad, loading, saving, crearSlot, eliminarSlot } = useDisponibilidadMedico()
  const { clinicas } = useClinicas()
  const [mostrarForm, setMostrarForm] = useState(false)

  const [form, setForm] = useState({
    dia_semana: 1,
    hora_inicio: '09:00',
    hora_fin: '12:00',
    duracion_slot: 30,
    clinica_id: '',
  })

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const ok = await crearSlot({
      dia_semana: form.dia_semana,
      hora_inicio: form.hora_inicio,
      hora_fin: form.hora_fin,
      duracion_slot: form.duracion_slot,
      clinica_id: form.clinica_id || null,
    })
    if (ok) {
      setMostrarForm(false)
      setForm({ dia_semana: 1, hora_inicio: '09:00', hora_fin: '12:00', duracion_slot: 30, clinica_id: '' })
    }
  }

  const agrupados = disponibilidad.reduce((acc: Record<string, typeof disponibilidad>, item) => {
    const dia = DIAS[item.dia_semana] || 'Desconocido'
    if (!acc[dia]) acc[dia] = []
    acc[dia].push(item)
    return acc
  }, {})

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate('/medico')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1">
          <h1 className="text-2xl font-bold text-[#1a2a3a] flex items-center gap-2">
            <Clock className="h-7 w-7 text-[#1E5C8E]" />
            Mi Disponibilidad
          </h1>
          <p className="text-sm text-muted-foreground">
            Configura los horarios en los que los pacientes pueden agendar citas contigo.
          </p>
        </div>
      </div>

      <div className="flex justify-end">
        <Button onClick={() => setMostrarForm(!mostrarForm)}>
          <Plus className="h-4 w-4 mr-1" />
          {mostrarForm ? 'Cancelar' : 'Agregar horario'}
        </Button>
      </div>

      {mostrarForm && (
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Nuevo horario de atención</CardTitle>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>Día de la semana</Label>
                <select
                  value={form.dia_semana}
                  onChange={(e) => setForm({ ...form, dia_semana: parseInt(e.target.value) })}
                  className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
                >
                  {DIAS.map((dia, i) => (
                    <option key={i} value={i}>{dia}</option>
                  ))}
                </select>
              </div>
              <div className="space-y-2">
                <Label>Hora inicio</Label>
                <Input type="time" value={form.hora_inicio} onChange={(e) => setForm({ ...form, hora_inicio: e.target.value })} required />
              </div>
              <div className="space-y-2">
                <Label>Hora fin</Label>
                <Input type="time" value={form.hora_fin} onChange={(e) => setForm({ ...form, hora_fin: e.target.value })} required />
              </div>
              <div className="space-y-2">
                <Label>Duración por cita (min)</Label>
                <Input type="number" min={15} step={15} value={form.duracion_slot} onChange={(e) => setForm({ ...form, duracion_slot: parseInt(e.target.value) })} required />
              </div>
              <div className="space-y-2 md:col-span-2">
                <Label>Clínica (opcional)</Label>
                <select
                  value={form.clinica_id}
                  onChange={(e) => setForm({ ...form, clinica_id: e.target.value })}
                  className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
                >
                  <option value="">Cualquier clínica / Consulta virtual</option>
                  {clinicas.map((c) => (
                    <option key={c.id} value={c.id}>{c.nombre}</option>
                  ))}
                </select>
              </div>
              <div className="md:col-span-3">
                <Button type="submit" disabled={saving} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                  {saving ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Plus className="h-4 w-4 mr-1" />}
                  Guardar horario
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : disponibilidad.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center">
            <Clock className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-gray-700">Sin horarios configurados</h3>
            <p className="text-sm text-muted-foreground max-w-md mx-auto mt-1">
              Agrega al menos un horario para que los pacientes puedan agendar citas contigo.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {Object.entries(agrupados).map(([dia, slots]) => (
            <Card key={dia}>
              <CardHeader className="pb-2">
                <CardTitle className="text-base font-semibold">{dia}</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {slots.map((slot) => (
                  <div key={slot.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <div className="flex items-center gap-3">
                      <Clock className="h-4 w-4 text-[#1E5C8E]" />
                      <span className="text-sm font-medium">
                        {slot.hora_inicio} – {slot.hora_fin}
                      </span>
                      <Badge variant="outline" className="text-xs">
                        {slot.duracion_slot} min/cita
                      </Badge>
                      {slot.clinica_id && (
                        <Badge variant="secondary" className="text-xs">
                          {clinicas.find(c => String(c.id) === String(slot.clinica_id))?.nombre || 'Clínica'}
                        </Badge>
                      )}
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      className="text-red-600 hover:bg-red-50"
                      onClick={() => eliminarSlot(slot.id)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
