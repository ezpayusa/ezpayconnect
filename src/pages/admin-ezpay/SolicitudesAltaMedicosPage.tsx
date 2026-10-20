import { useState, useEffect, useCallback } from 'react'
import { useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Textarea } from '@/components/ui/textarea'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { UserPlus, Loader2, Send, XCircle, RotateCw } from 'lucide-react'
import { useSolicitudesAlta } from '@/hooks/admin/useSolicitudesAlta'
import { badgeEstadoSolicitud } from '@/visitador/lib/enrolamiento'
import {
  FILTROS_ESTADO, MOTIVO_MAX, MOTIVO_MIN, accionesDeEstado, filtrarPorPais, motivoValido, pEstado,
  textoConfirmarAprobar, textoConfirmarReenviar, type FiltroEstado, type SolicitudAltaAdmin,
} from '@/lib/solicitudesAltaAdmin'

// Bandeja de solicitudes de alta de médico (migs 377/378). Dual-mount: /admin-ezpay/pais/:paisId/... (solo las de ese
// país) y /admin-ezpay/solicitudes-alta-medicos (super_admin, todas). La RPC ya acota por país (admin_pais solo ve
// el suyo); el filtro por paisId es de pantalla. Las acciones las decide el servidor (PV022-PV025).
export default function SolicitudesAltaMedicosPage() {
  const { paisId } = useParams<{ paisId: string }>()
  const { listar, aprobar, rechazar, reenviar } = useSolicitudesAlta()
  const [solicitudes, setSolicitudes] = useState<SolicitudAltaAdmin[]>([])
  const [loading, setLoading] = useState(true)
  const [filtro, setFiltro] = useState<FiltroEstado>('pendiente')
  const [procesando, setProcesando] = useState<string | null>(null)
  const [aRechazar, setARechazar] = useState<SolicitudAltaAdmin | null>(null)
  const [motivo, setMotivo] = useState('')

  const cargar = useCallback(async () => {
    setLoading(true)
    const r = await listar(pEstado(filtro))
    setLoading(false)
    if (!r.ok) {
      toast.error(r.error.mensaje)
      setSolicitudes([])
      return
    }
    setSolicitudes(filtrarPorPais(r.data, paisId))
  }, [listar, filtro, paisId])

  useEffect(() => { cargar() }, [cargar])

  // Ejecuta una acción, muestra el resultado y recarga la lista (con éxito o con error: el estado pudo cambiar).
  const ejecutar = async (id: string, accion: () => Promise<{ ok: boolean; error?: { mensaje: string } }>, exito: string) => {
    setProcesando(id)
    const r = await accion()
    setProcesando(null)
    if (r.ok) toast.success(exito)
    else toast.error(r.error?.mensaje)
    await cargar()
    return r.ok
  }

  const onAprobar = async (s: SolicitudAltaAdmin) => {
    if (!window.confirm(textoConfirmarAprobar(s.email))) return
    await ejecutar(s.id, () => aprobar(s.id), `Invitación enviada a ${s.email}.`)
  }

  const onReenviar = async (s: SolicitudAltaAdmin) => {
    if (!window.confirm(textoConfirmarReenviar(s.email))) return
    await ejecutar(s.id, () => reenviar(s.id), `Invitación reenviada a ${s.email}.`)
  }

  const abrirRechazo = (s: SolicitudAltaAdmin) => { setARechazar(s); setMotivo('') }
  const cerrarRechazo = () => { setARechazar(null); setMotivo('') }

  const onConfirmarRechazo = async () => {
    if (!aRechazar || !motivoValido(motivo)) return // el botón ya está deshabilitado; candado extra
    const ok = await ejecutar(aRechazar.id, () => rechazar(aRechazar.id, motivo.trim()), 'Solicitud rechazada.')
    if (ok) cerrarRechazo()
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-800 flex items-center gap-2">
            <UserPlus className="h-6 w-6 text-[#1E5C8E]" /> Solicitudes de alta de médicos
          </h1>
          <p className="text-slate-500 mt-1">Médicos que los visitadores proponen dar de alta en MED</p>
        </div>
        <select
          aria-label="Filtrar por estado"
          value={filtro}
          onChange={(e) => setFiltro(e.target.value as FiltroEstado)}
          className="h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
        >
          {FILTROS_ESTADO.map((f) => <option key={f.value} value={f.value}>{f.label}</option>)}
        </select>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : solicitudes.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-slate-500">
            <UserPlus className="h-12 w-12 mx-auto mb-3 text-slate-300" />
            <p>No hay solicitudes con este filtro.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {solicitudes.map((s) => {
            const badge = badgeEstadoSolicitud(s.estado)
            const acciones = accionesDeEstado(s.estado)
            const ocupada = procesando === s.id
            return (
              <Card key={s.id} className="bg-white" data-testid="solicitud-alta">
                <CardContent className="p-4 space-y-3">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-slate-800">{s.nombre_completo}</span>
                    <Badge className={`text-[10px] ${badge.clase}`} data-testid="badge-estado">{badge.label}</Badge>
                  </div>
                  <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1 text-sm">
                    <div><dt className="inline text-slate-500">Correo: </dt><dd className="inline text-slate-700">{s.email}</dd></div>
                    <div><dt className="inline text-slate-500">Teléfono: </dt><dd className="inline text-slate-700">{s.telefono || '—'}</dd></div>
                    <div><dt className="inline text-slate-500">Especialidad: </dt><dd className="inline text-slate-700">{s.especialidad_nombre || '—'}</dd></div>
                    <div><dt className="inline text-slate-500">Colegiado: </dt><dd className="inline text-slate-700">{s.numero_colegiado || '—'}</dd></div>
                    <div><dt className="inline text-slate-500">Clínica: </dt><dd className="inline text-slate-700">{s.nombre_clinica || '—'}</dd></div>
                    <div><dt className="inline text-slate-500">Laboratorio: </dt><dd className="inline text-slate-700">{s.empresa_nombre || '—'}</dd></div>
                    <div><dt className="inline text-slate-500">Visitador: </dt><dd className="inline text-slate-700">{s.solicitante_nombre || '—'}</dd></div>
                    <div><dt className="inline text-slate-500">Fecha: </dt><dd className="inline text-slate-700">{new Date(s.created_at).toLocaleString('es-GT')}</dd></div>
                  </dl>
                  {s.estado === 'rechazada' && s.motivo_rechazo && (
                    <p className="rounded-lg border border-red-200 bg-red-50 p-2 text-sm text-red-700" data-testid="motivo-rechazo">
                      <span className="font-medium">Motivo del rechazo:</span> {s.motivo_rechazo}
                    </p>
                  )}
                  {acciones.length > 0 && (
                    <div className="flex flex-wrap gap-2 pt-1">
                      {acciones.includes('aprobar') && (
                        <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700 text-white" disabled={ocupada} onClick={() => onAprobar(s)}>
                          {ocupada ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Send className="h-4 w-4 mr-1" />}
                          Aprobar y enviar invitación
                        </Button>
                      )}
                      {acciones.includes('rechazar') && (
                        <Button size="sm" variant="outline" className="text-red-600 hover:bg-red-50" disabled={ocupada} onClick={() => abrirRechazo(s)}>
                          <XCircle className="h-4 w-4 mr-1" /> Rechazar
                        </Button>
                      )}
                      {acciones.includes('reenviar') && (
                        <Button size="sm" variant="outline" disabled={ocupada} onClick={() => onReenviar(s)}>
                          {ocupada ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <RotateCw className="h-4 w-4 mr-1" />}
                          Reenviar invitación
                        </Button>
                      )}
                    </div>
                  )}
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      {/* Rechazo con motivo OBLIGATORIO (5-500, como la RPC): botón deshabilitado + return temprano. */}
      <Dialog open={!!aRechazar} onOpenChange={(o) => { if (!o) cerrarRechazo() }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Rechazar solicitud</DialogTitle>
          </DialogHeader>
          {aRechazar && (
            <div className="space-y-3">
              <p className="text-sm text-slate-600">
                Vas a rechazar el alta de <span className="font-medium">{aRechazar.nombre_completo}</span>. El visitador verá el motivo.
              </p>
              <label htmlFor="motivo-rechazo" className="text-sm font-medium">Motivo del rechazo <span className="text-red-500">*</span></label>
              <Textarea
                id="motivo-rechazo"
                placeholder={`Explica por qué se rechaza (entre ${MOTIVO_MIN} y ${MOTIVO_MAX} caracteres)…`}
                value={motivo}
                onChange={(e) => setMotivo(e.target.value)}
                maxLength={MOTIVO_MAX}
                rows={3}
              />
              <div className="flex gap-3">
                <Button variant="outline" className="flex-1" disabled={procesando === aRechazar.id} onClick={cerrarRechazo}>Volver</Button>
                <Button
                  className="flex-1 bg-red-600 hover:bg-red-700 text-white"
                  disabled={procesando === aRechazar.id || !motivoValido(motivo)}
                  onClick={onConfirmarRechazo}
                >
                  {procesando === aRechazar.id ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <XCircle className="h-4 w-4 mr-1" />}
                  Confirmar rechazo
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
