import { useEffect, useState } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { ArrowLeft, Loader2, Send, UserPlus } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent } from '@/components/ui/card'
import { supabase } from '@/lib/supabase'
import { useEnrolamiento } from '@/visitador/hooks/useEnrolamiento'
import { usePuedeEnrolar } from '@/visitador/hooks/usePuedeEnrolar'
import {
  validarSolicitudAlta,
  type CampoSolicitud,
  type DatosSolicitudAlta,
  type ErroresSolicitud,
} from '@/visitador/lib/enrolamiento'

// Solicitud de alta de un médico que todavía no está en MED (solicitar_alta_medico, migs 377/378). La valida el
// admin de país. La validación de acá adelanta la del servidor, no la reemplaza: la barrera es la RPC.
const VACIO: DatosSolicitudAlta = {
  nombre: '', email: '', telefono: '', especialidad_id: '', numero_colegiado: '', nombre_clinica: '', autorizado: false,
}

// Campos de la RPC que el mapa de errores manda inline (PV018/PV020/PV021); PV019 ('formulario') va arriba del botón.
const CAMPOS_INLINE: CampoSolicitud[] = ['autorizado', 'email']

export default function SolicitarAltaPage() {
  const navigate = useNavigate()
  const { puedeEnrolar, loading } = usePuedeEnrolar()
  const { solicitarAlta, enrolarMedico } = useEnrolamiento()
  const [datos, setDatos] = useState<DatosSolicitudAlta>(VACIO)
  const [errores, setErrores] = useState<ErroresSolicitud>({})
  const [errorGeneral, setErrorGeneral] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  const [especialidades, setEspecialidades] = useState<{ id: string; nombre: string }[]>([])
  // 'existe': el correo ya es de un médico activo del país → se ofrece enrolarlo (no se creó nada).
  const [medicoExistente, setMedicoExistente] = useState<string | null>(null)
  const [enrolando, setEnrolando] = useState(false)

  useEffect(() => {
    supabase.from('especialidades').select('id, nombre').eq('activo', true).order('nombre')
      .then(({ data }) => setEspecialidades((data ?? []) as { id: string; nombre: string }[]))
  }, [])

  if (loading) {
    return <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
  }
  // Gate visual (pieza 6). La RPC rechaza igual con PV016/PV014.
  if (!puedeEnrolar) return <Navigate to="/visitador/agendar" replace />

  const set = <K extends CampoSolicitud>(campo: K, valor: DatosSolicitudAlta[K]) => {
    setDatos((d) => ({ ...d, [campo]: valor }))
    setErrores((e) => ({ ...e, [campo]: undefined }))
    setMedicoExistente(null)
  }

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault()
    setErrorGeneral(null)
    const errs = validarSolicitudAlta(datos)
    setErrores(errs)
    if (Object.keys(errs).length > 0) return

    setEnviando(true)
    const r = await solicitarAlta(datos)
    setEnviando(false)
    if (!r.ok) {
      const campo = r.error.campo as CampoSolicitud | undefined
      if (r.error.destino === 'inline' && campo && CAMPOS_INLINE.includes(campo)) {
        setErrores({ [campo]: r.error.mensaje })
      } else if (r.error.destino === 'inline') {
        setErrorGeneral(r.error.mensaje)
      } else {
        toast.error(r.error.mensaje)
      }
      return
    }
    if (r.data.estado === 'creada') {
      toast.success('Solicitud enviada. Tu administrador de país la revisará.')
      navigate('/visitador/solicitudes')
      return
    }
    setMedicoExistente(r.data.medico_id)
  }

  const enrolarExistente = async () => {
    if (!medicoExistente) return
    setEnrolando(true)
    const r = await enrolarMedico(medicoExistente)
    setEnrolando(false)
    if (!r.ok) {
      toast.error(r.error.mensaje) // PV013 (otro laboratorio), PV011…: mensaje del servidor
      return
    }
    toast.success(r.data === 'enrolado' ? 'Médico enrolado. Ahora tienes prioridad con él.' : 'Ya habías enrolado a este médico.')
    navigate('/visitador/agendar')
  }

  const err = (campo: CampoSolicitud) =>
    errores[campo] ? <p className="text-xs text-red-600" data-testid={`error-${campo}`}>{errores[campo]}</p> : null

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Button variant="ghost" size="icon" onClick={() => navigate(-1)} aria-label="Volver">
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-xl font-bold text-gray-900">Solicitar alta de médico</h1>
          <p className="text-sm text-muted-foreground">Para un médico que todavía no está en MED.</p>
        </div>
      </div>

      {medicoExistente && (
        <Card className="border-blue-200 bg-blue-50" data-testid="medico-existente">
          <CardContent className="p-4 space-y-3 text-sm text-blue-900">
            <p className="font-medium">Este médico ya está en MED. ¿Quieres enrolarlo?</p>
            <Button size="sm" disabled={enrolando} onClick={enrolarExistente} className="bg-[#1E5C8E] hover:bg-[#164a70]">
              {enrolando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <UserPlus className="h-4 w-4 mr-1" />}
              Enrolar médico
            </Button>
          </CardContent>
        </Card>
      )}

      <form onSubmit={enviar} noValidate className="space-y-4">
        <div className="space-y-1">
          <Label htmlFor="sa-nombre">Nombre completo *</Label>
          <Input id="sa-nombre" value={datos.nombre} maxLength={150} onChange={(e) => set('nombre', e.target.value)} />
          {err('nombre')}
        </div>
        <div className="space-y-1">
          <Label htmlFor="sa-email">Correo *</Label>
          <Input id="sa-email" type="email" inputMode="email" value={datos.email} maxLength={254}
                 onChange={(e) => set('email', e.target.value)} />
          {err('email')}
        </div>
        <div className="space-y-1">
          <Label htmlFor="sa-telefono">Teléfono</Label>
          <Input id="sa-telefono" type="tel" inputMode="tel" value={datos.telefono} maxLength={30}
                 onChange={(e) => set('telefono', e.target.value)} />
          {err('telefono')}
        </div>
        <div className="space-y-1">
          <Label htmlFor="sa-especialidad">Especialidad</Label>
          <select
            id="sa-especialidad"
            value={datos.especialidad_id}
            onChange={(e) => set('especialidad_id', e.target.value)}
            className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
          >
            <option value="">Sin indicar</option>
            {especialidades.map((es) => <option key={es.id} value={es.id}>{es.nombre}</option>)}
          </select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="sa-colegiado">Número de colegiado</Label>
          <Input id="sa-colegiado" value={datos.numero_colegiado} maxLength={30}
                 onChange={(e) => set('numero_colegiado', e.target.value)} />
          {err('numero_colegiado')}
        </div>
        <div className="space-y-1">
          <Label htmlFor="sa-clinica">Nombre de la clínica</Label>
          <Input id="sa-clinica" value={datos.nombre_clinica} maxLength={150}
                 onChange={(e) => set('nombre_clinica', e.target.value)} />
          {err('nombre_clinica')}
        </div>
        <div className="space-y-1">
          <label className="flex items-start gap-2 text-sm">
            <input
              type="checkbox"
              className="mt-1"
              checked={datos.autorizado}
              onChange={(e) => set('autorizado', e.target.checked)}
            />
            <span>El médico autorizó compartir estos datos con EZPay *</span>
          </label>
          {err('autorizado')}
        </div>

        {errorGeneral && (
          <p className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700" data-testid="error-general">{errorGeneral}</p>
        )}

        <Button type="submit" disabled={enviando} className="w-full bg-[#1E5C8E] hover:bg-[#164a70]">
          {enviando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Send className="h-4 w-4 mr-1" />}
          Enviar solicitud
        </Button>
      </form>
    </div>
  )
}
