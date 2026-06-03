import { useState } from 'react'
import { supabase } from '@/lib/supabase'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { CalendarDays, Clock, FileText, StickyNote, X, Loader2 } from 'lucide-react'
import { toast } from 'sonner'

interface Props {
  pacienteId: number | undefined
  open: boolean
  onClose: () => void
  onSuccess?: () => void
}

export default function AgendarCitaModal({ pacienteId, open, onClose, onSuccess }: Props) {
  const [form, setForm] = useState({
    fecha: '',
    hora_inicio: '',
    motivo: '',
    notas: '',
  })
  const [guardando, setGuardando] = useState(false)

  if (!open) return null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!pacienteId || !form.fecha || !form.hora_inicio) {
      toast.error('Completa fecha y hora obligatorias')
      return
    }

    try {
      setGuardando(true)

      // Calcular hora_fin (30 minutos después de hora_inicio)
      const [h, m] = form.hora_inicio.split(':').map(Number)
      const finDate = new Date()
      finDate.setHours(h, m + 30)
      const hora_fin = `${String(finDate.getHours()).padStart(2, '0')}:${String(finDate.getMinutes()).padStart(2, '0')}:00`

      const { error } = await supabase.from('citas').insert({
        paciente_id: pacienteId,
        fecha: form.fecha,
        hora_inicio: form.hora_inicio,
        hora_fin: hora_fin,
        motivo: form.motivo || 'Consulta general',
        notas: form.notas || null,
        estado: 'solicitada',
      })

      if (error) throw error

      toast.success('Cita solicitada correctamente')
      setForm({ fecha: '', hora_inicio: '', motivo: '', notas: '' })
      onClose()
      onSuccess?.()
    } catch (err: any) {
      console.error('Error agendando cita:', err)
      toast.error('Error: ' + (err.message || 'No se pudo agendar la cita'))
    } finally {
      setGuardando(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-md overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-slate-100">
          <h2 className="text-lg font-semibold text-slate-800">Agendar Cita</h2>
          <button
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-slate-100 text-slate-400 transition-colors"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="p-4 space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label className="text-xs text-slate-500 flex items-center gap-1">
                <CalendarDays className="h-3.5 w-3.5" />
                Fecha *
              </Label>
              <Input
                type="date"
                required
                value={form.fecha}
                onChange={(e) => setForm({ ...form, fecha: e.target.value })}
                className="h-9 text-sm"
                min={new Date().toISOString().split('T')[0]}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs text-slate-500 flex items-center gap-1">
                <Clock className="h-3.5 w-3.5" />
                Hora *
              </Label>
              <Input
                type="time"
                required
                value={form.hora_inicio}
                onChange={(e) => setForm({ ...form, hora_inicio: e.target.value })}
                className="h-9 text-sm"
              />
            </div>
          </div>

          <div className="space-y-1.5">
            <Label className="text-xs text-slate-500 flex items-center gap-1">
              <FileText className="h-3.5 w-3.5" />
              Motivo de consulta
            </Label>
            <Input
              placeholder="Ej: Dolor de cabeza, control general..."
              value={form.motivo}
              onChange={(e) => setForm({ ...form, motivo: e.target.value })}
              className="h-9 text-sm"
            />
          </div>

          <div className="space-y-1.5">
            <Label className="text-xs text-slate-500 flex items-center gap-1">
              <StickyNote className="h-3.5 w-3.5" />
              Notas adicionales
            </Label>
            <textarea
              placeholder="Síntomas, medicamentos actuales, etc."
              value={form.notas}
              onChange={(e) => setForm({ ...form, notas: e.target.value })}
              className="w-full rounded-md border border-slate-200 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-transparent"
              rows={3}
            />
          </div>

          <div className="flex gap-2 pt-2">
            <Button type="button" variant="outline" className="flex-1" onClick={onClose}>
              Cancelar
            </Button>
            <Button type="submit" className="flex-1 bg-sky-500 hover:bg-sky-600" disabled={guardando}>
              {guardando ? (
                <Loader2 className="h-4 w-4 animate-spin mr-1" />
              ) : (
                <CalendarDays className="h-4 w-4 mr-1" />
              )}
              Solicitar cita
            </Button>
          </div>
        </form>
      </div>
    </div>
  )
}
