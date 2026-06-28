import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { useAdmisionCitas, type CitaAdmision } from '@/clinica/hooks/useAdmisionCitas'
import { FormularioVitales, type VitalesValues, VITALES_VACIO } from '@/clinica/components/FormularioVitales'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { ClipboardList, RefreshCw, Clock, User, Stethoscope, X, Loader2, Activity, Check, ShieldCheck } from 'lucide-react'
import { FotoPacienteAvatar } from '@/components/FotoPacienteAvatar'
import { ConsentimientoPresencial } from '@/components/ConsentimientoPresencial'

const num = (v: string) => (v.trim() === '' ? null : Number(v))
const horaCorta = (t: string | null) => (t ? t.slice(0, 5) : '—')

export default function ClinicaAdmisionPage() {
  const { clinica } = useClinicaAuth()
  const { citas, loading, error, recargar, tomasPorCita, recargarConteos } = useAdmisionCitas()
  const [citaSel, setCitaSel] = useState<CitaAdmision | null>(null)

  return (
    <div className="max-w-4xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <ClipboardList className="w-6 h-6 text-[#1E5C8E]" /> Admisión
          </h1>
          <p className="text-sm text-muted-foreground">{clinica?.nombre || 'Clínica'} · Citas de hoy</p>
        </div>
        <Button variant="outline" onClick={recargar}>
          <RefreshCw className="h-4 w-4 mr-2" /> Recargar
        </Button>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-lg">Cola de hoy ({citas.length})</CardTitle></CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center p-8"><Loader2 className="h-6 w-6 animate-spin text-[#1E5C8E]" /></div>
          ) : error ? (
            <div className="text-center py-8 text-red-600 text-sm">{error}</div>
          ) : citas.length === 0 ? (
            <div className="text-center py-8 text-gray-500">
              <ClipboardList className="w-12 h-12 mx-auto mb-3 text-gray-300" />
              <p>No hay citas para hoy</p>
            </div>
          ) : (
            <div className="divide-y">
              {citas.map((c) => (
                <button
                  key={c.id}
                  onClick={() => setCitaSel(c)}
                  className="w-full flex items-center gap-4 py-3 px-2 text-left hover:bg-gray-50 rounded transition-colors"
                >
                  <span className="flex items-center gap-1 text-sm font-medium text-[#1E5C8E] w-16">
                    <Clock className="h-4 w-4" /> {horaCorta(c.hora_inicio)}
                  </span>
                  <span className="flex-1 flex items-center gap-2 text-sm">
                    <User className="h-4 w-4 text-gray-400" />
                    {c.paciente_nombre} {c.paciente_apellido || ''}
                  </span>
                  <span className="flex items-center gap-1 text-xs text-muted-foreground">
                    <Stethoscope className="h-3 w-3" /> {c.medico_nombre || 'Sin médico'}
                  </span>
                  <Badge variant="secondary" className="text-xs">{c.estado}</Badge>
                  {tomasPorCita[c.id] > 0 && (
                    <Badge className="text-xs bg-emerald-100 text-emerald-700 flex items-center gap-1">
                      <Check className="h-3 w-3" /> {tomasPorCita[c.id]}
                    </Badge>
                  )}
                </button>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {citaSel && <ModalAdmision cita={citaSel} onClose={() => setCitaSel(null)} onTomaGuardada={recargarConteos} />}
    </div>
  )
}

// ============================================================
// Modal: serie de tomas (read-only) + agregar toma. La cola queda de fondo.
// ============================================================
function ModalAdmision({ cita, onClose, onTomaGuardada }: { cita: CitaAdmision; onClose: () => void; onTomaGuardada: () => void }) {
  const [serie, setSerie] = useState<any[]>([])
  const [cargandoSerie, setCargandoSerie] = useState(true)
  const [form, setForm] = useState<VitalesValues>(VITALES_VACIO)
  const [guardando, setGuardando] = useState(false)

  const cargarSerie = useCallback(async () => {
    setCargandoSerie(true)
    const { data, error } = await supabase.rpc('listar_signos_vitales_cita', { p_cita_id: cita.id })
    if (error) toast.error(error.message)
    setSerie(Array.isArray(data) ? data : [])
    setCargandoSerie(false)
  }, [cita.id])

  useEffect(() => { cargarSerie() }, [cargarSerie])

  const onChange = (campo: keyof VitalesValues, valor: string) =>
    setForm((f) => ({ ...f, [campo]: valor }))

  const guardar = async () => {
    setGuardando(true)
    const { error } = await supabase.rpc('capturar_signo_vital', {
      p_paciente_id: cita.paciente_id,
      p_cita_id: cita.id,
      p_medico_id: cita.medico_id, // médico de la cita → el médico ve la toma luego por sus policies SELECT
      p_presion_arterial: form.presion_arterial.trim() || null,
      p_frecuencia_cardiaca: num(form.frecuencia_cardiaca),
      p_frecuencia_respiratoria: num(form.frecuencia_respiratoria),
      p_temperatura: num(form.temperatura),
      p_peso_kg: num(form.peso_kg),
      p_talla_cm: num(form.talla_cm),
      p_saturacion_o2: num(form.saturacion_o2),
      p_glucosa: num(form.glucosa),
      p_notas: form.notas.trim() || null,
      // capturado_por lo fuerza el server (NO se manda).
    })
    setGuardando(false)
    if (error) { toast.error(error.message); return }
    toast.success('Toma registrada')
    setForm(VITALES_VACIO)
    cargarSerie()    // refresca la serie del modal
    onTomaGuardada() // refresca el conteo de la cola (✓) sin recargar todo; NO cierra el modal
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={onClose}>
      <div className="bg-white rounded-lg shadow-xl w-full max-w-lg max-h-[90vh] overflow-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start justify-between p-4 border-b sticky top-0 bg-white">
          <div>
            <h2 className="font-bold text-lg">{cita.paciente_nombre} {cita.paciente_apellido || ''}</h2>
            <p className="text-xs text-muted-foreground flex items-center gap-2">
              <Clock className="h-3 w-3" /> {horaCorta(cita.hora_inicio)}
              <Stethoscope className="h-3 w-3 ml-2" /> {cita.medico_nombre || 'Sin médico'}
            </p>
          </div>
          <Button variant="ghost" size="icon" onClick={onClose}><X className="h-5 w-5" /></Button>
        </div>

        <div className="p-4 space-y-5">
          {/* Foto del paciente (subir/reemplazar). v1: sin foto PREVIA en Admisión (la cola no trae foto_path);
              tras subir, el preview se refresca. Deuda menor anotada. */}
          <div className="flex items-center gap-3">
            <FotoPacienteAvatar pacienteId={cita.paciente_id} fotoPath={null} editable size="lg" />
            <span className="text-sm text-muted-foreground">Foto del paciente</span>
          </div>

          {/* Consentimiento presencial (firma/papel por permiso) */}
          <div>
            <h3 className="text-sm font-semibold mb-2 flex items-center gap-2"><ShieldCheck className="h-4 w-4 text-[#1E5C8E]" /> Consentimiento</h3>
            <ConsentimientoPresencial pacienteId={cita.paciente_id} />
          </div>

          {/* Tomas registradas (read-only) */}
          <div>
            <h3 className="text-sm font-semibold mb-2 flex items-center gap-2"><Activity className="h-4 w-4 text-emerald-600" /> Tomas registradas</h3>
            {cargandoSerie ? (
              <div className="flex justify-center p-4"><Loader2 className="h-5 w-5 animate-spin text-[#1E5C8E]" /></div>
            ) : serie.length === 0 ? (
              <p className="text-sm text-gray-400 py-2">Sin tomas registradas</p>
            ) : (
              <div className="space-y-2">
                {serie.map((t) => (
                  <div key={t.id} className="border rounded p-2 text-xs bg-slate-50">
                    <div className="flex justify-between text-muted-foreground mb-1">
                      <span>{new Date(t.fecha_toma).toLocaleString('es-ES', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' })}</span>
                      <span>tomado por {t.capturado_por_nombre || '—'}</span>
                    </div>
                    <div className="flex flex-wrap gap-x-3 gap-y-1">
                      {t.presion_arterial && <span>PA {t.presion_arterial}</span>}
                      {t.frecuencia_cardiaca != null && <span>FC {t.frecuencia_cardiaca}</span>}
                      {t.frecuencia_respiratoria != null && <span>FR {t.frecuencia_respiratoria}</span>}
                      {t.temperatura != null && <span>T {t.temperatura}°</span>}
                      {t.peso_kg != null && <span>{t.peso_kg}kg</span>}
                      {t.talla_cm != null && <span>{t.talla_cm}cm</span>}
                      {t.imc != null && <span>IMC {t.imc}</span>}
                      {t.saturacion_o2 != null && <span>SpO2 {t.saturacion_o2}%</span>}
                      {t.glucosa != null && <span>Gluc {t.glucosa}</span>}
                      {t.notas && <span className="italic">{t.notas}</span>}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Agregar toma */}
          <div>
            <h3 className="text-sm font-semibold mb-2">Agregar toma</h3>
            <FormularioVitales values={form} onChange={onChange} onSubmit={guardar} loading={guardando} />
          </div>
        </div>
      </div>
    </div>
  )
}
