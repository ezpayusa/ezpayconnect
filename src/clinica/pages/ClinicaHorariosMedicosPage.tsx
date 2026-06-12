import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { Clock, Plus, Trash2, Loader2, Stethoscope, Briefcase } from 'lucide-react'

const DIAS = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado']

interface Medico { id: string; nombre_completo: string; especialidad: string }
interface Slot { id: string; dia_semana: number; hora_inicio: string; hora_fin: string; duracion_slot: number }

export default function ClinicaHorariosMedicosPage() {
  const { clinica } = useClinicaAuth()
  const [medicos, setMedicos] = useState<Medico[]>([])
  const [medicoSel, setMedicoSel] = useState<string>('')
  const [slots, setSlots] = useState<Slot[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ dia_semana: 1, hora_inicio: '09:00', hora_fin: '12:00', duracion_slot: 30 })
  const [tab, setTab] = useState<'visitador' | 'paciente'>('visitador')
  const esVisitador = tab === 'visitador'

  // Cargar médicos de la clínica (vía RPC definer; excluye al propio admin)
  useEffect(() => {
    if (!clinica?.id) return
    ;(async () => {
      const { data: { user } } = await supabase.auth.getUser()
      const { data: rel } = await supabase.rpc('obtener_medicos_clinica', { p_clinica_id: clinica.id })
      const ids = (rel || []).map((r: any) => r.medico_id).filter((id: string) => id !== user?.id)
      if (ids.length === 0) { setMedicos([]); return }
      const { data: meds } = await supabase.rpc('obtener_medicos_por_ids', { p_medico_ids: ids })
      setMedicos((meds || []).map((m: any) => ({ id: m.id, nombre_completo: m.nombre_completo, especialidad: m.especialidad || '' })))
    })()
  }, [clinica?.id])

  const fetchSlots = useCallback(async (medicoId: string, contexto: string) => {
    if (!medicoId) { setSlots([]); return }
    setLoading(true)
    const { data } = await supabase
      .from('disponibilidad_medico')
      .select('id, dia_semana, hora_inicio, hora_fin, duracion_slot')
      .eq('medico_id', medicoId)
      .eq('contexto', contexto)
      .eq('activo', true)
      .order('dia_semana')
      .order('hora_inicio')
    setSlots((data || []) as Slot[])
    setLoading(false)
  }, [])

  useEffect(() => { fetchSlots(medicoSel, tab) }, [medicoSel, tab, fetchSlots])

  const crear = async () => {
    if (!medicoSel) { toast.error('Elige un médico'); return }
    if (form.hora_fin <= form.hora_inicio) { toast.error('La hora de fin debe ser posterior a la de inicio'); return }
    setSaving(true)
    const { error } = await supabase.from('disponibilidad_medico').insert({
      medico_id: medicoSel,
      dia_semana: form.dia_semana,
      hora_inicio: form.hora_inicio,
      hora_fin: form.hora_fin,
      duracion_slot: esVisitador ? 15 : (form.duracion_slot || 30),
      contexto: tab,
      activo: true,
    })
    setSaving(false)
    if (error) { toast.error('No se pudo guardar: ' + error.message); return }
    toast.success('Horario agregado')
    setForm({ dia_semana: 1, hora_inicio: '09:00', hora_fin: '12:00', duracion_slot: 30 })
    fetchSlots(medicoSel, tab)
  }

  const eliminar = async (id: string) => {
    if (!window.confirm('¿Eliminar este horario?')) return
    const { error } = await supabase.from('disponibilidad_medico').delete().eq('id', id)
    if (error) { toast.error('No se pudo eliminar'); return }
    toast.success('Horario eliminado')
    fetchSlots(medicoSel, tab)
  }

  const agrupados = slots.reduce((acc: Record<string, Slot[]>, s) => {
    const dia = DIAS[s.dia_semana] || 'Desconocido'
    if (!acc[dia]) acc[dia] = []
    acc[dia].push(s)
    return acc
  }, {})

  return (
    <div className="p-4 md:p-6 max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Clock className="h-6 w-6 text-[#1E5C8E]" /> Horarios de tus médicos
        </h1>
        <p className="text-sm text-muted-foreground">
          Configura dos agendas por médico: una para <strong>visitadores médicos</strong> (15 min) y
          otra para <strong>pacientes</strong> (la usa el portal del paciente).
        </p>
      </div>

      {/* Selector de médico */}
      <Card>
        <CardContent className="p-4">
          <Label className="text-sm">Médico</Label>
          <select
            className="w-full h-10 rounded-md border border-input bg-background px-3 mt-1 text-sm"
            value={medicoSel}
            onChange={(e) => setMedicoSel(e.target.value)}
          >
            <option value="">Selecciona un médico…</option>
            {medicos.map((m) => <option key={m.id} value={m.id}>{m.nombre_completo}{m.especialidad ? ` · ${m.especialidad}` : ''}</option>)}
          </select>
          {medicos.length === 0 && (
            <p className="text-xs text-amber-600 mt-2">No hay médicos en esta clínica todavía.</p>
          )}
        </CardContent>
      </Card>

      {medicoSel && (
        <>
          {/* Selector de agenda */}
          <div className="inline-flex rounded-lg border p-1 bg-muted/30">
            <button
              onClick={() => setTab('visitador')}
              className={`px-4 py-2 rounded-md text-sm font-medium flex items-center gap-2 ${esVisitador ? 'bg-white shadow text-[#1E5C8E]' : 'text-muted-foreground'}`}
            >
              <Briefcase className="h-4 w-4" /> Visitadores médicos
            </button>
            <button
              onClick={() => setTab('paciente')}
              className={`px-4 py-2 rounded-md text-sm font-medium flex items-center gap-2 ${!esVisitador ? 'bg-white shadow text-[#1E5C8E]' : 'text-muted-foreground'}`}
            >
              <Stethoscope className="h-4 w-4" /> Pacientes
            </button>
          </div>
          <p className="text-sm text-muted-foreground">
            {esVisitador
              ? 'Horarios en los que el médico atiende a visitadores médicos. Cada cita dura 15 minutos (fijo).'
              : 'Horarios en los que el médico atiende a pacientes. Estos horarios los usa el portal del paciente.'}
          </p>

          {/* Form nuevo horario */}
          <Card>
            <CardHeader><CardTitle className="text-lg flex items-center gap-2"><Plus className="h-4 w-4" /> Nuevo horario · {esVisitador ? 'Visitadores' : 'Pacientes'}</CardTitle></CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                <div className="space-y-1">
                  <Label className="text-xs">Día</Label>
                  <select className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
                    value={form.dia_semana} onChange={(e) => setForm({ ...form, dia_semana: parseInt(e.target.value) })}>
                    {DIAS.map((d, i) => <option key={i} value={i}>{d}</option>)}
                  </select>
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Hora inicio</Label>
                  <Input type="time" value={form.hora_inicio} onChange={(e) => setForm({ ...form, hora_inicio: e.target.value })} />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Hora fin</Label>
                  <Input type="time" value={form.hora_fin} onChange={(e) => setForm({ ...form, hora_fin: e.target.value })} />
                </div>
                {esVisitador ? (
                  <div className="space-y-1">
                    <Label className="text-xs">Duración por cita</Label>
                    <div className="h-10 flex items-center text-sm text-muted-foreground">15 min (fijo)</div>
                  </div>
                ) : (
                  <div className="space-y-1">
                    <Label className="text-xs">Duración por cita (min)</Label>
                    <Input type="number" min={10} step={5} value={form.duracion_slot} onChange={(e) => setForm({ ...form, duracion_slot: parseInt(e.target.value) })} />
                  </div>
                )}
              </div>
              <Button className="mt-3 bg-[#1E5C8E] hover:bg-[#164a70]" onClick={crear} disabled={saving}>
                {saving ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Plus className="h-4 w-4 mr-1" />} Guardar horario
              </Button>
            </CardContent>
          </Card>

          {/* Lista */}
          {loading ? (
            <div className="flex justify-center py-10"><Loader2 className="h-7 w-7 animate-spin text-slate-400" /></div>
          ) : slots.length === 0 ? (
            <Card className="bg-gray-50 border-dashed">
              <CardContent className="p-8 text-center text-muted-foreground">
                <Stethoscope className="h-9 w-9 mx-auto mb-2 text-gray-300" />
                {esVisitador
                  ? 'Este médico no tiene horarios para visitadores. Agrega al menos uno.'
                  : 'Este médico no tiene horarios de pacientes. Agrega al menos uno para que los pacientes puedan agendar.'}
              </CardContent>
            </Card>
          ) : (
            <div className="space-y-3">
              {Object.entries(agrupados).map(([dia, sl]) => (
                <Card key={dia}>
                  <CardHeader className="pb-2"><CardTitle className="text-base">{dia}</CardTitle></CardHeader>
                  <CardContent className="space-y-2">
                    {sl.map((s) => (
                      <div key={s.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                        <div className="flex items-center gap-3">
                          <Clock className="h-4 w-4 text-[#1E5C8E]" />
                          <span className="text-sm font-medium">{s.hora_inicio} – {s.hora_fin}</span>
                          <Badge variant="outline" className="text-xs">{s.duracion_slot} min/cita</Badge>
                        </div>
                        <Button size="sm" variant="ghost" className="text-red-600 hover:bg-red-50" onClick={() => eliminar(s.id)}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    ))}
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  )
}
