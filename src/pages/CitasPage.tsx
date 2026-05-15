import { useState } from 'react'
import { useSearchParams } from 'react-router'
import { usePacientes } from '@/hooks/usePacientes'
import { useCitas } from '@/hooks/useCitas'
import BotonWhatsAppCita from '@/components/BotonWhatsAppCita'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Plus, Clock, Loader2 } from 'lucide-react'

const ESTADOS = ['agendada', 'confirmada', 'en_curso', 'completada', 'cancelada'] as const
const DIAS = ['Dom', 'Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab']

export default function CitasPage() {
  const [searchParams] = useSearchParams()
  const { pacientes } = usePacientes()
  const { citas, createCita, updateCita } = useCitas()
  const [showForm, setShowForm] = useState(searchParams.get('nuevo') === 'true')
  const [currentDate, setCurrentDate] = useState(new Date())
  const [selectedDate, setSelectedDate] = useState<string>('')
  const [saving, setSaving] = useState(false)

  const [form, setForm] = useState({
    paciente_id: '', fecha: '', hora_inicio: '', hora_fin: '', motivo: '', notas: ''
  })
  const [formError, setFormError] = useState('')

  const year = currentDate.getFullYear()
  const month = currentDate.getMonth()
  const firstDay = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()
  const monthNames = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

  const citasPorDia = (dia: number) => {
    const fechaStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`
    return citas.filter(c => c.fecha === fechaStr && c.estado !== 'cancelada')
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setFormError('')
    const { error } = await createCita({
      paciente_id: parseInt(form.paciente_id),
      fecha: form.fecha,
      hora_inicio: form.hora_inicio,
      hora_fin: form.hora_fin || null,
      motivo: form.motivo,
      notas: form.notas,
      estado: 'agendada'
    })
    if (error) {
      setFormError(typeof error === 'string' ? error : 'Error al crear cita. Verifica que seleccionaste un paciente.')
      setSaving(false)
      return
    }
    setForm({ paciente_id: '', fecha: '', hora_inicio: '', hora_fin: '', motivo: '', notas: '' })
    setShowForm(false)
    setSaving(false)
  }

  const cambiarEstado = async (id: number, estado: string) => {
    await updateCita(id, { estado: estado as any })
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-[#1a2a3a]">Agenda de Citas</h1>
          <p className="text-[#8a9aaa] mt-1">Calendario y gestion de citas</p>
        </div>
        <Button onClick={() => setShowForm(true)} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
          <Plus className="h-4 w-4 mr-2" /> Nueva Cita
        </Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <Card className="lg:col-span-2">
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="text-lg">{monthNames[month]} {year}</CardTitle>
            <div className="flex gap-2">
              <Button variant="outline" size="sm" onClick={() => setCurrentDate(new Date(year, month - 1))}>Anterior</Button>
              <Button variant="outline" size="sm" onClick={() => setCurrentDate(new Date())}>Hoy</Button>
              <Button variant="outline" size="sm" onClick={() => setCurrentDate(new Date(year, month + 1))}>Siguiente</Button>
            </div>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-7 gap-1">
              {DIAS.map(d => <div key={d} className="text-center text-sm font-medium text-[#8a9aaa] py-2">{d}</div>)}
              {Array.from({ length: firstDay }).map((_, i) => <div key={`empty-${i}`} />)}
              {Array.from({ length: daysInMonth }).map((_, i) => {
                const dia = i + 1
                const fechaStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`
                const citasDia = citasPorDia(dia)
                const isSelected = selectedDate === fechaStr
                const isToday = new Date().toISOString().split('T')[0] === fechaStr
                return (
                  <button
                    key={dia}
                    onClick={() => setSelectedDate(fechaStr)}
                    className={`min-h-[80px] p-2 rounded-lg text-left transition-all ${
                      isSelected ? 'bg-[#1E5C8E] text-white' : isToday ? 'bg-[#e8f0f8] border-2 border-[#1E5C8E]' : 'hover:bg-gray-50'
                    }`}
                  >
                    <span className={`text-sm font-medium ${isSelected ? 'text-white' : ''}`}>{dia}</span>
                    {citasDia.length > 0 && (
                      <div className="mt-1 space-y-1">
                        {citasDia.slice(0, 2).map(c => (
                          <div key={c.id} className={`text-[10px] truncate px-1 rounded ${isSelected ? 'bg-white/20' : 'bg-[#e8f0f8] text-[#1E5C8E]'}`}>
                            {c.hora_inicio} - {c.motivo || 'Consulta'}
                          </div>
                        ))}
                        {citasDia.length > 2 && <p className={`text-[10px] ${isSelected ? 'text-white/70' : 'text-[#8a9aaa]'}`}>+{citasDia.length - 2} mas</p>}
                      </div>
                    )}
                  </button>
                )
              })}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <Clock className="h-5 w-5 text-[#1E5C8E]" />
              {selectedDate ? `Citas: ${selectedDate}` : 'Selecciona un dia'}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {selectedDate ? (
              citas.filter(c => c.fecha === selectedDate && c.estado !== 'cancelada').length === 0 ? (
                <p className="text-[#8a9aaa] text-sm text-center py-4">No hay citas este dia</p>
              ) : (
                <div className="space-y-3">
                  {citas.filter(c => c.fecha === selectedDate && c.estado !== 'cancelada').map(cita => {
                    const paciente = pacientes.find(p => p.id === cita.paciente_id)
                    return (
                      <div key={cita.id} className="p-3 rounded-lg bg-[#e8f0f8] space-y-2">
                        <div className="flex justify-between items-start">
                          <div>
                            <p className="font-medium text-sm">{paciente?.nombre} {paciente?.apellido}</p>
                            <p className="text-xs text-[#1E5C8E] font-medium">{cita.hora_inicio} {cita.hora_fin ? `- ${cita.hora_fin}` : ''}</p>
                            <p className="text-xs text-[#8a9aaa]">{cita.motivo || 'Consulta general'}</p>
                          </div>
                          <div className="flex gap-2">
                            <BotonWhatsAppCita 
                              paciente={paciente} 
                              cita={cita}
                              tipo="recordatorio"
                            />
                          </div>
                        </div>
                        <Select value={cita.estado} onValueChange={(v) => cambiarEstado(cita.id, v)}>
                          <SelectTrigger className="h-8 text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {ESTADOS.map(e => <SelectItem key={e} value={e}>{e.charAt(0).toUpperCase() + e.slice(1)}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                    )
                  })}
                </div>
              )
            ) : (
              <p className="text-[#8a9aaa] text-sm text-center py-8">Haz clic en un dia para ver sus citas</p>
            )}
          </CardContent>
        </Card>
      </div>

      <Dialog open={showForm} onOpenChange={setShowForm}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Nueva Cita</DialogTitle>
          </DialogHeader>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label>Paciente *</Label>
              <Select value={form.paciente_id} onValueChange={(v) => setForm({...form, paciente_id: v})}>
                <SelectTrigger><SelectValue placeholder="Seleccionar paciente" /></SelectTrigger>
                <SelectContent>
                  {pacientes.map(p => <SelectItem key={p.id} value={String(p.id)}>{p.nombre} {p.apellido}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>Fecha *</Label><Input type="date" value={form.fecha} onChange={e => setForm({...form, fecha: e.target.value})} required /></div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2"><Label>Hora Inicio *</Label><Input type="time" value={form.hora_inicio} onChange={e => setForm({...form, hora_inicio: e.target.value})} required /></div>
              <div className="space-y-2"><Label>Hora Fin</Label><Input type="time" value={form.hora_fin} onChange={e => setForm({...form, hora_fin: e.target.value})} /></div>
            </div>
            <div className="space-y-2"><Label>Motivo</Label><Input value={form.motivo} onChange={e => setForm({...form, motivo: e.target.value})} placeholder="Consulta general" /></div>
            <div className="space-y-2"><Label>Notas</Label><textarea className="w-full border rounded-md p-2 min-h-[60px]" value={form.notas} onChange={e => setForm({...form, notas: e.target.value})} /></div>
            {formError && (
              <p className="text-sm text-red-500 bg-red-50 p-2 rounded">{formError}</p>
            )}
            <div className="flex justify-end gap-3">
              <Button type="button" variant="outline" onClick={() => { setShowForm(false); setFormError('') }}>Cancelar</Button>
              <Button type="submit" className="bg-[#1E5C8E] hover:bg-[#3A8ABF]" disabled={saving}>
                {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Guardar Cita
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}