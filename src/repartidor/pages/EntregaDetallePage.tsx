import { useRef, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowLeft, MapPin, Phone, Camera, PenLine, Eye, Loader2, MapPinned, Banknote, Navigation,
  CheckCircle2, ShieldCheck, ImageIcon, XCircle,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import MapaInteractivo from '@/components/MapaInteractivo'
import { validarImagen, comprimirImagen } from '@/repartidor/lib/imagen'
import { useEntregasRepartidor } from '@/repartidor/hooks/useEntregasRepartidor'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import {
  transicionesValidas, puedeCobrarDesde, MOTIVOS_FALLO, LABEL_ESTADO, LABEL_TRANSICION, colorEstado,
} from '@/repartidor/lib/estados'
import { folioEntrega, refCobro } from '@/repartidor/lib/folio'
import type { EstadoEntrega, MetodoCobro, MotivoFallo } from '@/repartidor/types'
import FirmaPad from '@/repartidor/components/FirmaPad'

const METODOS: { value: MetodoCobro; label: string }[] = [
  { value: 'efectivo', label: 'Efectivo' },
  { value: 'tarjeta', label: 'Tarjeta' },
  { value: 'transferencia', label: 'Transferencia' },
  { value: 'sin_cobro', label: 'Sin cobro' },
]

function fechaHora(iso?: string | null): string {
  if (!iso) return ''
  try {
    return new Date(iso).toLocaleString('es-GT', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
  } catch {
    return ''
  }
}

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
        <div className="rounded-2xl bg-white border border-gray-100 p-8 text-center text-gray-500">
          Esta entrega no está en tu cola.
        </div>
      </div>
    )
  }

  const transiciones = transicionesValidas(entrega.estado)
  // Acción primaria de la barra inferior = la transición que no es "fallida" (asignada→en_camino, en_camino→entregada).
  const primaria = transiciones.find((t) => t !== 'fallida')
  const puedeFallar = transiciones.includes('fallida')
  // NOTA: el rol `delivery` SIEMPRE tiene `entregas_cobrar` por TECHO 117 (no removible por override), así que
  // `puedeCobrar` es true en el caso vivo. El gate !tienePermiso NO es código muerto: es defensa-en-profundidad
  // para roles futuros / no-delivery que pudieran abrir esta vista (el server igual hace RAISE). No borrar.
  const mostrarCobro = puedeCobrar && puedeCobrarDesde(entrega.estado) && !entrega.cobrado
  const montoFmt = entrega.monto != null ? `Q${Number(entrega.monto).toFixed(2)}` : '—'

  return (
    <div className="space-y-4 pb-28">
      <button type="button" onClick={() => navigate('/repartidor')} className="flex items-center gap-1 text-sm text-gray-500">
        <ArrowLeft className="h-4 w-4" /> Volver a la cola
      </button>

      {/* Cabecera */}
      <div className="rounded-2xl bg-white border border-gray-100 shadow-sm p-4 space-y-2">
        <div className="flex items-center justify-between">
          <span className="font-semibold text-gray-800">Entrega #{folioEntrega(entrega.entrega_id)}</span>
          <span className={`text-xs font-semibold px-2 py-0.5 rounded-full border ${colorEstado(entrega.estado)}`}>
            {LABEL_ESTADO[entrega.estado]}
          </span>
        </div>
        <p className="text-sm text-gray-600">{entrega.sucursal_nombre ?? `Sucursal ${entrega.farmacia_id}`}</p>
        {entrega.intentos > 0 && <p className="text-xs text-gray-400">Reintentos: {entrega.intentos}</p>}
        {entrega.motivo_fallo && (
          <p className="text-sm text-red-600 flex items-center gap-1"><XCircle className="h-4 w-4" /> Motivo de fallo: {entrega.motivo_fallo}</p>
        )}
      </div>

      {/* Entrega completada */}
      {entrega.estado === 'entregada' && (
        <div className="rounded-2xl bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-800 flex items-center gap-2">
          <CheckCircle2 className="h-5 w-5 shrink-0" />
          <span>Entrega completada{entrega.entregado_at ? ` · ${fechaHora(entrega.entregado_at)}` : ''}</span>
        </div>
      )}

      {/* Contacto */}
      {entrega.telefono_contacto && (
        <div className="rounded-2xl bg-white border border-gray-100 shadow-sm p-4 flex items-center justify-between">
          <div className="min-w-0">
            <p className="text-xs text-gray-400">Contacto de entrega</p>
            <p className="text-sm text-gray-800 truncate">{entrega.telefono_contacto}</p>
          </div>
          <a href={`tel:${entrega.telefono_contacto}`} className="inline-flex items-center gap-1 rounded-full bg-[#1E5C8E] text-white text-sm px-4 py-2 shrink-0">
            <Phone className="h-4 w-4" /> Llamar
          </a>
        </div>
      )}

      {/* Ubicación — degrada limpio sin coords. El pin (lat/lng) lo puebla el GESTOR en F3
          (actualizar_direccion_entrega + geocodificar); la PWA del repartidor NO geocodifica. */}
      <div className="rounded-2xl bg-white border border-gray-100 shadow-sm p-4 space-y-2">
        <p className="text-sm font-medium text-gray-700 flex items-center gap-1"><MapPinned className="h-4 w-4" /> Ubicación</p>
        {entrega.lat != null && entrega.lng != null ? (
          <MapaInteractivo lat={entrega.lat} lng={entrega.lng} onChange={() => { /* solo lectura */ }} height="200px" />
        ) : (
          <p className="text-sm text-gray-500">Sin ubicación en el mapa. Usá la dirección para llegar.</p>
        )}
        <p className="text-sm text-gray-600 flex items-start gap-1">
          <MapPin className="h-4 w-4 shrink-0 mt-0.5 text-gray-400" /> {entrega.direccion_entrega ?? 'Sin dirección'}
        </p>
        {/* "Cómo llegar" abre la app de mapas del teléfono con coords (si hay) o con la dirección en texto. */}
        {(entrega.direccion_entrega || (entrega.lat != null && entrega.lng != null)) && (
          <a
            href={
              entrega.lat != null && entrega.lng != null
                ? `https://www.google.com/maps/dir/?api=1&destination=${entrega.lat},${entrega.lng}`
                : `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(entrega.direccion_entrega ?? '')}`
            }
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-sm text-[#1E5C8E] font-medium"
          >
            <Navigation className="h-4 w-4" /> Cómo llegar
          </a>
        )}
      </div>

      {/* Cobro registrado (cobrado) */}
      {entrega.cobrado && (
        <div className="rounded-2xl bg-white border border-emerald-200 shadow-sm p-4 space-y-2">
          <div className="flex items-center justify-between">
            <p className="text-sm font-medium text-gray-700 flex items-center gap-1"><Banknote className="h-4 w-4" /> Cobro registrado</p>
            <span className="inline-flex items-center gap-1 text-xs font-semibold text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-full px-2 py-0.5">
              <ShieldCheck className="h-3.5 w-3.5" /> Pagado
            </span>
          </div>
          <p className="text-2xl font-bold text-gray-800">{montoFmt}</p>
          <div className="flex items-center justify-between text-xs text-gray-500">
            <span className="font-mono">{refCobro(entrega.entrega_id)}</span>
            {entrega.metodo_cobro && <span className="capitalize">{entrega.metodo_cobro}</span>}
          </div>
        </div>
      )}

      {/* Cobro (oculto si no tiene el permiso / fuera de estado válido / ya cobrado) */}
      {mostrarCobro && (
        <div className="rounded-2xl bg-white border border-gray-100 shadow-sm p-4 space-y-3">
          <p className="text-sm font-medium text-gray-700 flex items-center gap-1"><Banknote className="h-4 w-4" /> Registrar cobro</p>
          <p className="text-2xl font-bold text-gray-800">{montoFmt}</p>
          <p className="text-xs text-gray-400">El monto lo calcula el sistema; vos solo elegís el método.</p>
          <div className="grid grid-cols-2 gap-2">
            {METODOS.map((m) => (
              <button
                key={m.value}
                type="button"
                onClick={() => setMetodo(m.value)}
                className={`rounded-lg border px-3 py-2 text-sm ${
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

      {/* Evidencia (el backend guarda UNA evidencia_path; foto/firma comparten esa referencia) */}
      <div className="rounded-2xl bg-white border border-gray-100 shadow-sm p-4 space-y-3">
        <p className="text-sm font-medium text-gray-700">Evidencia de entrega</p>
        {entrega.evidencia_path && (
          <button
            type="button"
            onClick={() => verEvidencia(entrega.evidencia_path)}
            className="w-full flex items-center gap-3 rounded-xl border border-gray-100 bg-gray-50 p-3 text-left"
          >
            <div className="h-12 w-12 rounded-lg bg-white border border-gray-200 grid place-items-center shrink-0">
              <ImageIcon className="h-5 w-5 text-gray-400" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-700">Evidencia adjunta</p>
              <p className="text-xs text-gray-400">Tocá para ver</p>
            </div>
            <Eye className="h-4 w-4 text-[#1E5C8E] shrink-0" />
          </button>
        )}
        <div className="grid grid-cols-2 gap-2">
          <Button type="button" variant="outline" onClick={() => fotoRef.current?.click()} disabled={busy}>
            <Camera className="h-4 w-4 mr-1" /> Tomar foto
          </Button>
          <Button type="button" variant="outline" onClick={() => setFirmaOpen((v) => !v)} disabled={busy}>
            <PenLine className="h-4 w-4 mr-1" /> Firma
          </Button>
          <input ref={fotoRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={onFoto} />
        </div>
        {firmaOpen && <FirmaPad folio={folioEntrega(entrega.entrega_id)} onSave={onFirma} onCancel={() => setFirmaOpen(false)} saving={busy} />}
      </div>

      {/* Marcar fallida (acción secundaria) */}
      {puedeFallar && (
        <Button
          type="button"
          variant="outline"
          className="w-full border-red-300 text-red-600 hover:bg-red-50"
          onClick={() => setMotivoOpen(true)}
          disabled={busy}
        >
          <XCircle className="h-4 w-4 mr-1" /> Marcar como fallida
        </Button>
      )}

      {/* Barra inferior fija: total + acción primaria según estado */}
      {(primaria || (entrega.monto != null)) && (
        <div className="fixed bottom-0 inset-x-0 z-20 bg-white border-t border-gray-200">
          <div className="mx-auto w-full max-w-md px-4 py-3 flex items-center gap-3">
            <div className="min-w-0">
              <p className="text-xs text-gray-400">
                {entrega.cobrado ? 'Cobrado' : 'Total a cobrar'}
                {!entrega.cobrado && metodo ? ` · ${METODOS.find((m) => m.value === metodo)?.label}` : ''}
              </p>
              <p className="text-lg font-bold text-gray-800">{montoFmt}</p>
            </div>
            {primaria && (
              <Button type="button" className="ml-auto" onClick={() => onTransicion(primaria)} disabled={busy}>
                {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : LABEL_TRANSICION[primaria]}
              </Button>
            )}
          </div>
        </div>
      )}

      {/* Bottom sheet: motivo de falla */}
      {motivoOpen && (
        <div className="fixed inset-0 z-30 flex items-end bg-black/40" onClick={() => !busy && setMotivoOpen(false)}>
          <div className="w-full bg-white rounded-t-3xl p-5 space-y-4" onClick={(e) => e.stopPropagation()}>
            <div className="mx-auto h-1 w-10 rounded-full bg-gray-200" />
            <p className="font-semibold text-gray-800">¿Por qué falló la entrega?</p>
            <div className="space-y-2">
              {MOTIVOS_FALLO.map((m) => (
                <label
                  key={m.value}
                  className={`flex items-center gap-3 rounded-xl border px-3 py-3 text-sm cursor-pointer ${
                    motivo === m.value ? 'border-red-400 bg-red-50 text-red-700' : 'border-gray-200 text-gray-700'
                  }`}
                >
                  <input
                    type="radio"
                    name="motivo"
                    className="accent-red-600"
                    checked={motivo === m.value}
                    onChange={() => setMotivo(m.value)}
                  />
                  {m.label}
                </label>
              ))}
            </div>
            <div className="flex gap-2 pt-1">
              <Button type="button" variant="outline" className="flex-1" onClick={() => setMotivoOpen(false)} disabled={busy}>
                Cancelar
              </Button>
              <Button type="button" className="flex-1 bg-red-600 hover:bg-red-700" onClick={confirmarFallida} disabled={busy}>
                Marcar como fallida
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
