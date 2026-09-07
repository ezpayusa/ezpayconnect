import { useCallback, useEffect, useRef, useState } from 'react'
import { toast } from 'sonner'
import {
  IdCard, Copy, Check, ExternalLink, RefreshCw, Trash2, Upload, AlertTriangle, Loader2,
} from 'lucide-react'
import { useAuth } from '@/hooks/useAuth'
import { reportarError } from '@/comercial/lib/reportarError'
import {
  miFichaTarjeta, tarjetaSetConsentimiento, tarjetaRotarToken, guardarFotoPublica,
  subirFotoPublica, urlFirmadaFoto, urlPublicaTarjeta, validarFoto, ACCEPT_FOTO,
  type FichaTarjeta,
} from '@/comercial/lib/tarjeta'

// Mi tarjeta — la pantalla con la que el asesor controla su propia tarjeta pública (D11 pieza 4a).
//
// Hasta este archivo, encender la tarjeta se hacía por SQL. Eso importa para entender el tono: el
// consentimiento NO es un toggle más de configuración, es el momento en que alguien decide publicar
// su cara y su teléfono en internet. Por eso el texto explicativo está ANTES del interruptor y no
// escondido en un tooltip, y por eso rotar el enlace pide confirmación escrita de lo que rompe.
//
// TODO LO QUE DECIDE ESTÁ EN LA BASE. Las tres RPCs operan sobre auth.uid() y ninguna toma id de
// asesor: esta pantalla no puede tocar la tarjeta de otro ni aunque quisiera. Lo que hace acá el
// front es contar la verdad de lo que va a pasar.

/** Las iniciales del avatar, mismo criterio que la edge (primera palabra + última). */
function iniciales(nombre: string): string {
  const p = nombre.trim().split(/\s+/).filter(Boolean)
  if (p.length === 0) return '?'
  return ((p[0][0] ?? '') + (p.length > 1 ? (p[p.length - 1][0] ?? '') : '')).toUpperCase()
}

function fecha(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString('es-GT', {
    day: '2-digit', month: 'short', year: 'numeric',
  })
}

export default function MiTarjetaPage() {
  const { perfil } = useAuth()
  const [ficha, setFicha] = useState<FichaTarjeta | null>(null)
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const [copiado, setCopiado] = useState(false)
  const [confirmandoRotar, setConfirmandoRotar] = useState(false)
  const [pct, setPct] = useState<number | null>(null)
  const [fotoUrl, setFotoUrl] = useState<string | null>(null)
  const inputFoto = useRef<HTMLInputElement>(null)

  const nombre = perfil?.nombre_completo || 'Asesor comercial'

  const cargar = useCallback(async () => {
    setCargando(true)
    const { data, error } = await miFichaTarjeta(perfil?.id)
    if (error) reportarError(error)
    setFicha((data as FichaTarjeta | null) ?? null)
    setCargando(false)
  }, [perfil?.id])

  useEffect(() => { void cargar() }, [cargar])

  // La vista previa se pide DESPUÉS de tener el path y vive sólo acá: la URL firmada es un bearer
  // de 5 minutos y no va a ningún almacenamiento (ver urlFirmadaFoto).
  useEffect(() => {
    let vivo = true
    const path = ficha?.foto_publica_path
    if (!path) { setFotoUrl(null); return }
    void (async () => {
      const { data, error } = await urlFirmadaFoto(path)
      if (!vivo) return
      // Un fallo acá NO es un error de la tarjeta: la foto pública se sigue sirviendo por la edge.
      // Sólo se pierde la vista previa, así que se cae al placeholder sin molestar al usuario.
      if (error || !data?.signedUrl) { setFotoUrl(null); return }
      setFotoUrl(data.signedUrl)
    })()
    return () => { vivo = false }
  }, [ficha?.foto_publica_path])

  const publicada = !!ficha?.tarjeta_publica
  const enlace = ficha ? urlPublicaTarjeta(ficha.tarjeta_token) : ''

  async function alternarConsentimiento() {
    if (!ficha || guardando) return
    const encender = !publicada
    setGuardando(true)
    const { error } = await tarjetaSetConsentimiento(encender)
    if (error) {
      reportarError(error, { onRecargar: (q) => { if (q === 'tarjeta') void cargar() } })
    } else {
      toast.success(encender
        ? 'Tu tarjeta está publicada. Ya podés compartir el enlace.'
        : 'Tu tarjeta dejó de estar disponible. El enlace ya no responde.')
      await cargar()
    }
    setGuardando(false)
  }

  async function rotar() {
    if (!ficha || guardando) return
    setGuardando(true)
    const { error } = await tarjetaRotarToken()
    if (error) {
      reportarError(error, { onRecargar: (q) => { if (q === 'tarjeta') void cargar() } })
    } else {
      // La RPC devuelve void: el token nuevo no viene en la respuesta y hay que releer la ficha.
      await cargar()
      toast.success('Enlace nuevo generado. El anterior dejó de funcionar.')
    }
    setConfirmandoRotar(false)
    setGuardando(false)
  }

  async function alElegirFoto(e: React.ChangeEvent<HTMLInputElement>) {
    const archivo = e.target.files?.[0]
    e.target.value = ''   // permite volver a elegir el mismo archivo si falló
    if (!archivo || !ficha) return

    const malo = validarFoto(archivo)
    if (malo) { toast.error(malo); return }

    setPct(0)
    const r = await subirFotoPublica(ficha.id, archivo, setPct)
    setPct(null)
    if (r.error) {
      reportarError(r.error, { onRecargar: (q) => { if (q === 'tarjeta') void cargar() } })
      if (r.huerfano) {
        toast.warning('La foto se subió pero no quedó registrada, y tampoco se pudo borrar. '
          + 'Avisale a soporte con este dato: ' + r.huerfano)
      }
      return
    }
    toast.success('Foto actualizada.')
    await cargar()
  }

  async function quitarFoto() {
    if (!ficha || guardando) return
    setGuardando(true)
    const { error } = await guardarFotoPublica(null)
    if (error) {
      reportarError(error, { onRecargar: (q) => { if (q === 'tarjeta') void cargar() } })
    } else {
      toast.success('Foto quitada. Tu tarjeta deja de mostrarla.')
      await cargar()
    }
    setGuardando(false)
  }

  async function copiar() {
    try {
      await navigator.clipboard.writeText(enlace)
      setCopiado(true)
      setTimeout(() => setCopiado(false), 2000)
    } catch {
      toast.error('No se pudo copiar. Mantené presionado el enlace para copiarlo a mano.')
    }
  }

  if (cargando) {
    return (
      <div className="flex items-center justify-center py-16 text-gray-400">
        <Loader2 className="h-5 w-5 animate-spin" />
      </div>
    )
  }

  // SIN FICHA: se dice con calma y no se ofrece ningún control. Un interruptor que siempre falla es
  // peor que no tenerlo — el usuario no puede hacer nada al respecto y sólo junta errores.
  if (!ficha) {
    return (
      <div className="space-y-3">
        <h1 className="text-lg font-semibold text-gray-900 flex items-center gap-2">
          <IdCard className="h-5 w-5 text-[#1E5C8E]" /> Mi tarjeta
        </h1>
        <div className="rounded-lg border bg-white p-4 text-sm text-gray-600">
          <p className="font-medium text-gray-900">Todavía no tenés ficha de asesor.</p>
          <p className="mt-1">
            La tarjeta pública se arma con los datos de tu ficha (cargo, territorio y teléfonos), y
            esa ficha la crea el administrador de tu país. Cuando la tengas, vas a poder publicar tu
            tarjeta desde acá.
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <h1 className="text-lg font-semibold text-gray-900 flex items-center gap-2">
        <IdCard className="h-5 w-5 text-[#1E5C8E]" /> Mi tarjeta
      </h1>

      {/* ---------------- estado ---------------- */}
      <div className="rounded-lg border bg-white p-4">
        <div className="flex items-center gap-2">
          <span
            className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold ${
              publicada ? 'bg-emerald-50 text-emerald-700' : 'bg-gray-100 text-gray-600'
            }`}
          >
            <span className={`h-1.5 w-1.5 rounded-full ${publicada ? 'bg-emerald-500' : 'bg-gray-400'}`} />
            {publicada ? 'Publicada' : 'No publicada'}
          </span>
          {publicada && ficha.tarjeta_consentimiento_at && (
            <span className="text-xs text-gray-400">desde el {fecha(ficha.tarjeta_consentimiento_at)}</span>
          )}
        </div>

        {publicada ? (
          <div className="mt-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Tu enlace</p>
            <p className="mt-1 break-all rounded border bg-gray-50 px-2 py-1.5 font-mono text-xs text-gray-700">
              {enlace}
            </p>
            <div className="mt-2 flex gap-2">
              <button
                type="button"
                onClick={copiar}
                className="flex items-center gap-1.5 rounded-md bg-[#1E5C8E] px-3 py-1.5 text-sm font-medium text-white"
              >
                {copiado ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                {copiado ? 'Copiado' : 'Copiar enlace'}
              </button>
              <a
                href={enlace}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm font-medium text-gray-700"
              >
                <ExternalLink className="h-4 w-4" /> Ver mi tarjeta
              </a>
            </div>
          </div>
        ) : (
          <p className="mt-3 text-sm text-gray-600">
            Tu tarjeta no está publicada. El enlace no le responde a nadie.
          </p>
        )}
      </div>

      {/* ---------------- consentimiento ----------------
          EL TEXTO ES PARTE DEL CONSENTIMIENTO, NO DECORACIÓN. Va completo y ANTES del interruptor:
          quien lo enciende tiene que saber qué queda expuesto y ante quién, y quien lo apaga tiene
          que saber que el enlace muere de verdad y no que se esconde un botón. */}
      <div className="rounded-lg border bg-white p-4">
        <h2 className="text-sm font-semibold text-gray-900">Publicar mi tarjeta</h2>
        <p className="mt-2 text-sm leading-relaxed text-gray-600">
          Al publicarla, <strong>cualquier persona que tenga el enlace</strong> puede abrir tu
          tarjeta <strong>sin iniciar sesión</strong> y ver tu nombre, tu cargo, tu territorio, tus
          teléfonos y tu foto. El enlace se puede reenviar: no controlás a quién se lo pasan.
        </p>
        <p className="mt-2 text-sm leading-relaxed text-gray-600">
          Si la despublicás, <strong>el enlace deja de responder de inmediato</strong> — no se
          esconde un botón: la página entera devuelve "no disponible", incluida tu foto, para todos
          los que ya lo tenían.
        </p>
        <button
          type="button"
          onClick={alternarConsentimiento}
          disabled={guardando}
          className={`mt-3 w-full rounded-md px-3 py-2.5 text-sm font-semibold disabled:opacity-50 ${
            publicada ? 'border border-gray-300 bg-white text-gray-700' : 'bg-emerald-600 text-white'
          }`}
        >
          {publicada ? 'Despublicar mi tarjeta' : 'Publicar mi tarjeta'}
        </button>
      </div>

      {/* ---------------- foto ---------------- */}
      <div className="rounded-lg border bg-white p-4">
        <h2 className="text-sm font-semibold text-gray-900">Foto</h2>
        <div className="mt-3 flex items-center gap-4">
          {fotoUrl ? (
            <img
              src={fotoUrl}
              alt="Tu foto de la tarjeta"
              className="h-20 w-20 shrink-0 rounded-full border object-cover"
            />
          ) : (
            <div
              className="flex h-20 w-20 shrink-0 items-center justify-center rounded-full border bg-gray-200 text-xl font-bold text-gray-500"
              aria-hidden="true"
            >
              {iniciales(nombre)}
            </div>
          )}
          <div className="min-w-0 flex-1">
            <p className="text-sm text-gray-600">
              {ficha.foto_publica_path
                ? 'Así se ve en tu tarjeta. Se recorta en círculo.'
                : 'Sin foto, tu tarjeta muestra un círculo con tus iniciales.'}
            </p>
            <p className="mt-0.5 text-xs text-gray-400">JPG, PNG o WebP · hasta 2 MB</p>
          </div>
        </div>

        {pct !== null && (
          <div className="mt-3">
            <div className="h-1.5 w-full overflow-hidden rounded bg-gray-200">
              <div className="h-full bg-[#1E5C8E] transition-all" style={{ width: `${pct}%` }} />
            </div>
            <p className="mt-1 text-xs text-gray-500">Subiendo… {pct}%</p>
          </div>
        )}

        <div className="mt-3 flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => inputFoto.current?.click()}
            disabled={pct !== null || guardando}
            className="flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm font-medium text-gray-700 disabled:opacity-50"
          >
            <Upload className="h-4 w-4" />
            {ficha.foto_publica_path ? 'Cambiar foto' : 'Subir foto'}
          </button>
          {ficha.foto_publica_path && (
            <button
              type="button"
              onClick={quitarFoto}
              disabled={pct !== null || guardando}
              className="flex items-center gap-1.5 rounded-md border border-red-200 px-3 py-1.5 text-sm font-medium text-red-600 disabled:opacity-50"
            >
              <Trash2 className="h-4 w-4" /> Quitar foto
            </button>
          )}
        </div>
        {ficha.foto_publica_path && (
          <p className="mt-2 text-xs text-gray-500">
            Al quitarla, tu tarjeta deja de mostrarla y la imagen deja de servirse.
          </p>
        )}
        <input
          ref={inputFoto}
          type="file"
          accept={ACCEPT_FOTO}
          onChange={alElegirFoto}
          className="hidden"
          data-testid="input-foto"
        />
      </div>

      {/* ---------------- rotar ---------------- */}
      <div className="rounded-lg border bg-white p-4">
        <h2 className="text-sm font-semibold text-gray-900">Generar un enlace nuevo</h2>
        <p className="mt-2 text-sm leading-relaxed text-gray-600">
          Sirve si compartiste el enlace con alguien a quien ya no querés dárselo.
        </p>
        {!confirmandoRotar ? (
          <button
            type="button"
            onClick={() => setConfirmandoRotar(true)}
            disabled={guardando}
            className="mt-3 flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm font-medium text-gray-700 disabled:opacity-50"
          >
            <RefreshCw className="h-4 w-4" /> Generar enlace nuevo
          </button>
        ) : (
          <div className="mt-3 rounded-md border border-amber-300 bg-amber-50 p-3">
            <p className="flex items-start gap-2 text-sm text-amber-900">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>
                <strong>El enlace anterior deja de funcionar para siempre</strong>, incluidos todos
                los que ya compartiste. Quien lo tenga guardado va a ver "tarjeta no disponible".
                Esto no se puede deshacer.
              </span>
            </p>
            <div className="mt-3 flex gap-2">
              <button
                type="button"
                onClick={rotar}
                disabled={guardando}
                className="rounded-md bg-amber-600 px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-50"
              >
                Sí, generar uno nuevo
              </button>
              <button
                type="button"
                onClick={() => setConfirmandoRotar(false)}
                disabled={guardando}
                className="rounded-md border px-3 py-1.5 text-sm font-medium text-gray-700 disabled:opacity-50"
              >
                Cancelar
              </button>
            </div>
          </div>
        )}
        {ficha.tarjeta_token_rotado_at && (
          <p className="mt-2 text-xs text-gray-400">
            Último cambio de enlace: {fecha(ficha.tarjeta_token_rotado_at)}
          </p>
        )}
      </div>
    </div>
  )
}
