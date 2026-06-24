import { useRef, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowLeft, MapPin, Phone, Camera, PenLine, Eye, Loader2, MapPinned, Banknote,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import MapaInteractivo from '@/components/MapaInteractivo'
import { validarImagen, comprimirImagen } from '@/repartidor/lib/imagen'
import { useEntregasRepartidor } from '@/repartidor/hooks/useEntregasRepartidor'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import {
  transicionesValidas, puedeCobrarDesde, MOTIVOS_FALLO, LABEL_ESTADO, LABEL_TRANSICION, colorEstado,
} from '@/repartidor/lib/estados'
import type { EstadoEntrega, MetodoCobro, MotivoFallo } from '@/repartidor/types'
import FirmaPad from '@/repartidor/components/FirmaPad'

const METODOS: { value: MetodoCobro; label: string }[] = [
  { value: 'efectivo', label: 'Efectivo' },
  { value: 'tarjeta', label: 'Tarjeta' },
  { value: 'transferencia', label: 'Transferencia' },
  { value: 'sin_cobro', label: 'Sin cobro' },
]

export default function EntregaDetallePage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const entregaId = Number(id)
  const { entregas, loading, actualizarEstado, cobrar, subirEvidencia, verEvidencia } = useEntregasRepartidor()
  const { tienePermiso } = useFarmaciaPermisos()
  const puedeCobrar = tienePermiso('entregas_cobrar')

  const entrega = entregas.find((e) => e.entrega_id === entregaId) ?? null

  const [busy, setBusy] = useState(false)
  const [motivoOpen, setMotivoOpen] = useState(false)
  const [motivo, setMotivo] = useState<MotivoFallo>('ausente')
  const [metodo, setMetodo] = useState<MetodoCobro>('efectivo')
  const [firmaOpen, setFirmaOpen] = useState(false)
  const fotoRef = useRef<HTMLInputElement | null>(null)

  const conManejo = async (fn: () => Promise<unknown>, okMsg: string) => {
    setBusy(true)
    try {
      await fn()
      toast.success(okMsg)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error inesperado')
    } finally {
      setBusy(false)
    }
  }

  const onTransicion = (nuevo: EstadoEntrega) => {
    if (nuevo === 'fallida') {
      setMotivoOpen(true)
      return
    }
    void conManejo(() => actualizarEstado(entregaId, nuevo), `Entrega ${LABEL_ESTADO[nuevo].toLowerCase()}`)
  }

  const confirmarFallida = () =>
    conManejo(async () => {
      await actualizarEstado(entregaId, 'fallida', motivo)
      setMotivoOpen(false)
    }, 'Entrega marcada como fallida')

  const onCobrar = () => conManejo(() => cobrar(entregaId, metodo), 'Cobro registrado')

  const onFoto = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    const err = validarImagen(file) // no confiar en `accept`: validar tipo/peso reales
    if (err) {
      toast.error(err)
      return
    }
    void conManejo(async () => {
      const blob = await comprimirImagen(file) // acota el peso (foto de cámara puede pesar varios MB)
      await subirEvidencia(entregaId, blob, 'foto')
    }, 'Foto subida')
  }

  const onFirma = (blob: Blob) =>
    conManejo(async () => {
      await subirEvidencia(entregaId, blob, 'firma')
      setFirmaOpen(false)
    }, 'Firma subida')

  if (loading && !entrega) {
    return (
      <div className="flex items-center justify-center py-16 text-gray-400">
        <Loader2 className="h-6 w-6 animate-spin" />
      </div>
    )
  }

  if (!entrega) {
    return (
      <div className="space-y-4">
        <button type="button" onClick={() => navigate('/repartidor')} className="flex items-center gap-1 text-sm text-gray-500">
          <ArrowLeft className="h-4 w-4" /> Volver
        </button>
        <div className="rounded-lg bg-white border border-gray-100 p-8 text-center text-gray-500">
          Esta entrega no está en tu cola.
        </div>
      </div>
    )
  }

  const transiciones = transicionesValidas(entrega.estado)
  const mostrarCobro = puedeCobrar && puedeCobrarDesde(entrega.estado) && !entrega.cobrado

  return (
    <div className="space-y-4 pb-8">
      <button type="button" onClick={() => navigate('/repartidor')} className="flex items-center gap-1 text-sm text-gray-500">
        <ArrowLeft className="h-4 w-4" /> Volver a la cola
      </button>

      {/* Cabecera */}
      <div className="rounded-lg bg-white border border-gray-100 shadow-sm p-4 space-y-2">
        <div className="flex items-center justify-between">
          <span className={`text-xs font-medium px-2 py-0.5 rounded-full border ${colorEstado(entrega.estado)}`}>
            {LABEL_ESTADO[entrega.estado]}
          </span>
          {entrega.intentos > 0 && <span className="text-xs text-gray-400">Reintentos: {entrega.intentos}</span>}
        </div>
        <p className="font-semibold text-gray-800">{entrega.sucursal_nombre ?? `Sucursal ${entrega.farmacia_id}`}</p>
        <p className="text-sm text-gray-600 flex items-start gap-1">
          <MapPin className="h-4 w-4 shrink-0 mt-0.5" /> {entrega.direccion_entrega ?? 'Sin dirección'}
        </p>
        {entrega.telefono_contacto && (
          <a href={`tel:${entrega.telefono_contacto}`} className="text-sm text-[#1E5C8E] flex items-center gap-1">
            <Phone className="h-4 w-4" /> {entrega.telefono_contacto}
          </a>
        )}
        {entrega.motivo_fallo && <p className="text-sm text-red-600">Motivo de fallo: {entrega.motivo_fallo}</p>}
      </div>

      {/* Mapa */}
      <div className="rounded-lg bg-white border border-gray-100 shadow-sm p-4 space-y-2">
        <p className="text-sm font-medium text-gray-700 flex items-center gap-1"><MapPinned className="h-4 w-4" /> Ubicación</p>
        {entrega.lat != null && entrega.lng != null ? (
          <MapaInteractivo lat={entrega.lat} lng={entrega.lng} onChange={() => { /* solo lectura */ }} height="220px" />
        ) : (
          <p className="text-sm text-gray-500">Sin coordenadas. Navegá por la dirección de arriba.</p>
        )}
      </div>

      {/* Cobro (oculto si no tiene el permiso) */}
      {mostrarCobro && (
        <div className="rounded-lg bg-white border border-gray-100 shadow-sm p-4 space-y-3">
          <p className="text-sm font-medium text-gray-700 flex items-center gap-1"><Banknote className="h-4 w-4" /> Cobro</p>
          {entrega.monto != null && (
            <p className="text-2xl font-bold text-gray-800">Q{Number(entrega.monto).toFixed(2)}</p>
          )}
          <p className="text-xs text-gray-400">El monto lo calcula el sistema; vos solo elegís el método.</p>
          <div className="grid grid-cols-2 gap-2">
            {METODOS.map((m) => (
              <button
                key={m.value}
                type="button"
                onClick={() => setMetodo(m.value)}
                className={`rounded-md border px-3 py-2 text-sm ${
                  metodo === m.value ? 'border-[#1E5C8E] bg-blue-50 text-[#1E5C8E]' : 'border-gray-200 text-gray-600'
                }`}
              >
                {m.label}
              </button>
            ))}
          </div>
          <Button type="button" className="w-full" onClick={onCobrar} disabled={busy}>
            {busy ? 'Procesando…' : 'Registrar cobro'}
          </Button>
        </div>
      )}
      {entrega.cobrado && (
        <div className="rounded-lg bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">
          Cobrado{entrega.metodo_cobro ? ` (${entrega.metodo_cobro})` : ''}{entrega.monto != null ? ` · Q${Number(entrega.monto).toFixed(2)}` : ''}
        </div>
      )}

      {/* Evidencia */}
      <div className="rounded-lg bg-white border border-gray-100 shadow-sm p-4 space-y-3">
        <p className="text-sm font-medium text-gray-700">Evidencia de entrega</p>
        <div className="grid grid-cols-2 gap-2">
          <Button type="button" variant="outline" onClick={() => fotoRef.current?.click()} disabled={busy}>
            <Camera className="h-4 w-4 mr-1" /> Tomar foto
          </Button>
          <Button type="button" variant="outline" onClick={() => setFirmaOpen((v) => !v)} disabled={busy}>
            <PenLine className="h-4 w-4 mr-1" /> Firma
          </Button>
          <input ref={fotoRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={onFoto} />
        </div>
        {firmaOpen && <FirmaPad onSave={onFirma} saving={busy} />}
        {entrega.evidencia_path && (
          <Button type="button" variant="ghost" size="sm" onClick={() => verEvidencia(entrega.evidencia_path)}>
            <Eye className="h-4 w-4 mr-1" /> Ver evidencia
          </Button>
        )}
      </div>

      {/* Transiciones de estado */}
      {transiciones.length > 0 && (
        <div className="space-y-2">
          {transiciones.map((t) => (
            <Button
              key={t}
              type="button"
              variant={t === 'fallida' ? 'outline' : 'default'}
              className={`w-full ${t === 'fallida' ? 'border-red-300 text-red-600 hover:bg-red-50' : ''}`}
              onClick={() => onTransicion(t)}
              disabled={busy}
            >
              {LABEL_TRANSICION[t]}
            </Button>
          ))}
        </div>
      )}

      {/* Selector de motivo (fallida) */}
      {motivoOpen && (
        <div className="rounded-lg bg-white border border-red-200 shadow-sm p-4 space-y-3">
          <p className="text-sm font-medium text-gray-700">Motivo del fallo</p>
          <div className="space-y-2">
            {MOTIVOS_FALLO.map((m) => (
              <button
                key={m.value}
                type="button"
                onClick={() => setMotivo(m.value)}
                className={`w-full text-left rounded-md border px-3 py-2 text-sm ${
                  motivo === m.value ? 'border-red-400 bg-red-50 text-red-700' : 'border-gray-200 text-gray-600'
                }`}
              >
                {m.label}
              </button>
            ))}
          </div>
          <div className="flex gap-2">
            <Button type="button" variant="outline" className="flex-1" onClick={() => setMotivoOpen(false)} disabled={busy}>
              Cancelar
            </Button>
            <Button type="button" className="flex-1 bg-red-600 hover:bg-red-700" onClick={confirmarFallida} disabled={busy}>
              Confirmar fallo
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
