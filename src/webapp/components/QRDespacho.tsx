// QR de despacho de la receta, en el portal del paciente.
// CONTENIDO DEL QR = dispatch_token CRUDO (64 hex), sin URL ni prefijo: es lo que acepta la farmacia.
// EscanearQRModal pasa el texto decodificado (trim) a verificar_receta_despacho / registrar_dispensacion,
// que comparan `dispatch_token = p_token` exacto. Igual que el QR del PDF (generar-pdf-receta).
//
// VALIDEZ (la misma regla de la farmacia): el token vale mientras dispatch_token_expira_at > now().
// "Ya despachada" = estado_dispensacion 'dispensada' o todos los ítems dispensados (sin nada que despachar).
//
// SEGURIDAD: el token es secreto del paciente. Solo se usa como `value` del SVG; no se imprime como texto,
// ni en title/aria-label, ni se loguea, ni se persiste. Se monta solo con la receta expandida.
import type { ReactNode } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { QrCode, CheckCircle, Clock, Ban } from 'lucide-react'
import type { RecetaPaciente } from '@/webapp/types/webapp.types'

const fmtFecha = (iso: string) =>
  new Date(iso).toLocaleString('es-GT', { year: 'numeric', month: 'long', day: 'numeric', hour: '2-digit', minute: '2-digit' })

function Aviso({ icono, texto, tono }: { icono: ReactNode; texto: string; tono: string }) {
  return (
    <div className={`flex items-start gap-2 rounded-lg p-3 text-sm ${tono}`}>
      {icono}
      <span>{texto}</span>
    </div>
  )
}

export default function QRDespacho({ receta }: { receta: RecetaPaciente }) {
  const d = receta.despacho

  if (receta.estado === 'cancelada') {
    return <Aviso icono={<Ban className="h-4 w-4 mt-0.5 shrink-0" />} tono="bg-slate-50 text-slate-600"
      texto="Receta cancelada: no se puede despachar." />
  }
  if (!d) {
    return <Aviso icono={<QrCode className="h-4 w-4 mt-0.5 shrink-0" />} tono="bg-slate-50 text-slate-600"
      texto="Receta sin código de despacho." />
  }

  const despachada = d.estado_dispensacion === 'dispensada'
    || (receta.items.length > 0 && receta.items.every((it) => it.dispensado === true))
  if (despachada) {
    return <Aviso icono={<CheckCircle className="h-4 w-4 mt-0.5 shrink-0" />} tono="bg-blue-50 text-blue-700"
      texto="Receta ya despachada." />
  }

  const vencido = !d.expira_at || new Date(d.expira_at).getTime() <= Date.now()
  if (vencido) {
    return <Aviso icono={<Clock className="h-4 w-4 mt-0.5 shrink-0" />} tono="bg-amber-50 text-amber-700"
      texto={d.expira_at
        ? `El código de despacho venció (${fmtFecha(d.expira_at)}). Pide a tu médico una nueva receta.`
        : 'El código de despacho no tiene una vigencia válida. Pide a tu médico una nueva receta.'} />
  }

  return (
    <div className="flex flex-col items-center gap-2 rounded-lg bg-white border border-slate-200 p-4">
      <QRCodeSVG value={d.token} size={200} level="M" marginSize={2} aria-hidden="true" />
      <p className="text-sm text-slate-600 text-center">Muestra este código en la farmacia para retirar tus medicamentos.</p>
      <p className="text-xs text-slate-500">Válido hasta el {fmtFecha(d.expira_at!)}</p>
      {d.estado_dispensacion === 'parcial' && (
        <p className="text-xs text-amber-700">Despacho parcial: aún quedan medicamentos por retirar.</p>
      )}
      {/* La farmacia solo despacha ítems ruteados a ella (verificar_receta_despacho): sin farmacia_id, el QR no se acepta. */}
      {!receta.items.some((it) => it.farmacia_id != null) && (
        <p className="text-xs text-amber-700 bg-amber-50 rounded-md px-3 py-2 text-center">
          Esta receta aún no tiene farmacia asignada; tu médico debe dirigirla para que puedas retirarla.
        </p>
      )}
    </div>
  )
}
