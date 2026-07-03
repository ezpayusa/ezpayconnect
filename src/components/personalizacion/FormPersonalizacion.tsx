import { useState, useEffect, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Loader2, Upload, Send, Clock, CheckCircle2, XCircle } from 'lucide-react'
import { TEMA_OFICIAL } from '@/components/theme/TenantThemeContext'
import { useMiSolicitudPersonalizacion } from '@/hooks/useMiSolicitudPersonalizacion'
import { PreviewMaquetaPanel } from './PreviewMaquetaPanel'

const MAX_BYTES = 1024 * 1024 // 1 MB (igual al file_size_limit del bucket)
const MIME_OK = ['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml']
const EXT: Record<string, string> = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/svg+xml': 'svg' }

interface TemaActual {
  logo_url: string | null
  color_primario: string | null
  color_secundario: string | null
  color_fondo: string | null
}

// Formulario de solicitud de personalización, compartido por Clínica y Proveedor. El tenant_tipo/tenant_id
// se derivan de la SESIÓN (los pasa el caller desde useClinicaAuth/useProveedorAuth), nunca de un input.
export function FormPersonalizacion({
  tenantTipo, tenantId, actual,
}: { tenantTipo: 'clinica' | 'empresa_proveedora'; tenantId: string | undefined; actual: TemaActual | null }) {
  const { pendiente, ultima, loading, recargar } = useMiSolicitudPersonalizacion(tenantTipo)

  // Pickers inicializados desde el tema ACTUAL del tenant (o el oficial) → enviar preserva lo no tocado.
  const [primario, setPrimario] = useState(actual?.color_primario ?? TEMA_OFICIAL.primario)
  const [secundario, setSecundario] = useState(actual?.color_secundario ?? TEMA_OFICIAL.secundario)
  const [fondo, setFondo] = useState(actual?.color_fondo ?? TEMA_OFICIAL.fondo)
  const [logoFile, setLogoFile] = useState<File | null>(null)
  const [logoPreview, setLogoPreview] = useState<string | null>(null)  // objectURL del archivo elegido
  const [enviando, setEnviando] = useState(false)
  const fileInputRef = useRef<HTMLInputElement | null>(null)

  // Sincroniza los pickers cuando llega/actualiza el tema del tenant.
  useEffect(() => {
    setPrimario(actual?.color_primario ?? TEMA_OFICIAL.primario)
    setSecundario(actual?.color_secundario ?? TEMA_OFICIAL.secundario)
    setFondo(actual?.color_fondo ?? TEMA_OFICIAL.fondo)
  }, [actual?.color_primario, actual?.color_secundario, actual?.color_fondo])

  // Libera el objectURL al desmontar / cambiar de archivo.
  useEffect(() => () => { if (logoPreview) URL.revokeObjectURL(logoPreview) }, [logoPreview])

  // Logo que ve el preview: el archivo recién elegido, si no el actual del tenant, si no el oficial.
  const previewLogoUrl = logoPreview ?? actual?.logo_url ?? TEMA_OFICIAL.logoUrl

  const onFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0]
    if (!f) return
    if (!MIME_OK.includes(f.type)) {
      toast.error('Formato no permitido. Usá PNG, JPG, WEBP o SVG.')
      e.target.value = ''
      return
    }
    if (f.size > MAX_BYTES) {
      toast.error(`El logo pesa ${(f.size / 1024 / 1024).toFixed(2)} MB. El máximo es 1 MB.`)
      e.target.value = ''
      return
    }
    if (logoPreview) URL.revokeObjectURL(logoPreview)
    setLogoFile(f)
    setLogoPreview(URL.createObjectURL(f))
  }

  const bloqueado = !!pendiente
  const puedeEnviar = !!tenantId && !bloqueado && !enviando

  const enviar = async () => {
    if (!tenantId) { toast.error('No pudimos determinar tu clínica/empresa.'); return }
    setEnviando(true)
    try {
      // 1) Subir el logo (si eligió uno) a {tenant_tipo}/{tenant_id}/{uuid}.ext — derivado de la sesión.
      let logoUrl: string | null = actual?.logo_url ?? null
      if (logoFile) {
        const ext = EXT[logoFile.type] ?? 'png'
        const path = `${tenantTipo}/${tenantId}/${crypto.randomUUID()}.${ext}`
        const { error: upErr } = await supabase.storage
          .from('personalizacion-logos')
          .upload(path, logoFile, { contentType: logoFile.type, upsert: false })
        if (upErr) { toast.error('Error subiendo el logo: ' + upErr.message); setEnviando(false); return }
        logoUrl = supabase.storage.from('personalizacion-logos').getPublicUrl(path).data.publicUrl
      }

      // 2) Crear la solicitud. El backend deriva el tenant de la sesión (no confía en params de tenant).
      const { error } = await supabase.rpc('solicitar_personalizacion', {
        p_logo_url: logoUrl,
        p_color_primario: primario,
        p_color_secundario: secundario,
        p_color_fondo: fondo,
      })
      if (error) {
        // ERRCODEs alcanzables desde solicitar_personalizacion (verificado en la def viva de mig 205):
        //   PT003 rol_insuficiente — proveedor no-admin, o clínica sin rol admin_clinica/gerente
        //   PT006 sin_tenant       — usuario de clínica sin clínica derivable
        // El resto (PT001 guard/no_autorizado, PT004 inexistente, PT005 ya_resuelta) son exclusivos de
        // aprobar/rechazar → no llegan acá. Cualquier otro error es inesperado: mensaje genérico sin
        // exponer el texto crudo de Postgres (se loguea a consola para diagnóstico).
        const code = (error as { code?: string }).code
        if (code !== 'PT003' && code !== 'PT006') console.error('[solicitar_personalizacion]', error)
        const msg =
          code === 'PT003' ? 'Tu rol no tiene permiso para solicitar personalización.' :
          code === 'PT006' ? 'No pudimos determinar tu clínica/empresa. Contactá a soporte.' :
          'No se pudo enviar la solicitud. Intentá de nuevo o contactá a soporte.'
        toast.error(msg)
        setEnviando(false)
        return
      }

      toast.success('Solicitud enviada. Un administrador la revisará.')
      if (logoPreview) { URL.revokeObjectURL(logoPreview); setLogoPreview(null) }
      setLogoFile(null)
      if (fileInputRef.current) fileInputRef.current.value = ''
      await recargar()
    } finally {
      setEnviando(false)
    }
  }

  return (
    <div className="space-y-4">
      {/* Estado de solicitudes previas */}
      {loading ? (
        <div className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Cargando estado…</div>
      ) : (
        <>
          {pendiente && (
            <div className="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-700">
              <Clock className="h-4 w-4 shrink-0" />
              Tenés una solicitud pendiente de revisión. No podés enviar otra hasta que se resuelva.
            </div>
          )}
          {!pendiente && ultima?.estado === 'rechazada' && (
            <div className="flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
              <XCircle className="h-4 w-4 shrink-0 mt-0.5" />
              <span>Tu última solicitud fue <strong>rechazada</strong>{ultima.motivo_rechazo ? <>: {ultima.motivo_rechazo}</> : '.'}</span>
            </div>
          )}
          {!pendiente && ultima?.estado === 'aprobada' && (
            <div className="flex items-center gap-2 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">
              <CheckCircle2 className="h-4 w-4 shrink-0" /> Tu última solicitud fue aprobada y aplicada.
            </div>
          )}
        </>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Controles */}
        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Logo (PNG, JPG, WEBP o SVG · máx 1 MB)</Label>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/png,image/jpeg,image/webp,image/svg+xml"
              onChange={onFile}
              disabled={bloqueado}
              className="block w-full text-sm text-slate-600 file:mr-3 file:rounded-md file:border-0 file:bg-[#1E5C8E] file:px-3 file:py-1.5 file:text-white hover:file:bg-[#164a70] disabled:opacity-50"
            />
            {logoFile && <p className="text-xs text-muted-foreground flex items-center gap-1"><Upload className="h-3 w-3" /> {logoFile.name} listo para subir al enviar.</p>}
          </div>

          {([['Primario', primario, setPrimario, false], ['Secundario', secundario, setSecundario, false], ['Fondo', fondo, setFondo, true]] as const).map(
            ([label, val, set, proximamente]) => (
              <div key={label} className="flex items-center gap-3">
                <Label className="w-24">{label}</Label>
                <input type="color" value={val} onChange={(e) => set(e.target.value)} disabled={bloqueado}
                  className="h-9 w-14 rounded border border-slate-200 disabled:opacity-50" />
                <span className="text-xs font-mono text-muted-foreground">{val}</span>
                {proximamente && <span className="text-[11px] text-slate-400 italic">(se aplicará próximamente)</span>}
              </div>
            )
          )}

          <Button className="bg-[#1E5C8E] hover:bg-[#164a70]" onClick={enviar} disabled={!puedeEnviar}>
            {enviando ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Send className="h-4 w-4 mr-2" />}
            Enviar solicitud
          </Button>
        </div>

        {/* Preview en vivo (aislado) */}
        <div className="space-y-2">
          <Label>Vista previa</Label>
          <PreviewMaquetaPanel primario={primario} secundario={secundario} logoUrl={previewLogoUrl} />
        </div>
      </div>
    </div>
  )
}
