import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent } from '@/components/ui/card'
import { toast } from 'sonner'
import { ArrowLeft, Loader2, Upload, X } from 'lucide-react'
import { useSolicitudesCampana } from '@/proveedor/hooks/useSolicitudesCampana'
import { supabase } from '@/lib/supabase'
import type { SolicitudCampana } from '@/proveedor/types/proveedor.types'

const TIPOS = [
  { value: 'farmacia', label: 'Farmacia' },
  { value: 'equipo_medico', label: 'Equipo Médico' },
  { value: 'laboratorio', label: 'Laboratorio' },
  { value: 'general', label: 'General' },
]

export default function PublicidadCampanaFormPage() {
  const navigate = useNavigate()
  const { id } = useParams()
  const isEditing = Boolean(id)
  const { crearSolicitud, actualizarSolicitud, saving } = useSolicitudesCampana()
  const [loadingData, setLoadingData] = useState(isEditing)

  const [form, setForm] = useState({
    titulo: '',
    descripcion: '',
    tipo: 'general',
    link_url: '',
    fecha_inicio: '',
    fecha_fin: '',
    condicion_filtro: '',
    genero_filtro: '',
    edad_min: '',
    edad_max: '',
  })
  const [imagenFile, setImagenFile] = useState<File | null>(null)
  const [imagenPreview, setImagenPreview] = useState<string | null>(null)

  useEffect(() => {
    if (isEditing && id) {
      const fetchCampana = async () => {
        const { data, error } = await supabase
          .from('solicitudes_campana')
          .select('*')
          .eq('id', id)
          .single()

        if (error || !data) {
          toast.error('Error cargando campaña')
          navigate('/proveedor/publicidad/campanas')
          return
        }

        setForm({
          titulo: data.titulo || '',
          descripcion: data.descripcion || '',
          tipo: data.tipo || 'general',
          link_url: data.link_url || '',
          fecha_inicio: data.fecha_inicio || '',
          fecha_fin: data.fecha_fin || '',
          condicion_filtro: data.condicion_filtro || '',
          genero_filtro: data.genero_filtro || '',
          edad_min: data.edad_min ? String(data.edad_min) : '',
          edad_max: data.edad_max ? String(data.edad_max) : '',
        })
        if (data.imagen_url) setImagenPreview(data.imagen_url)
        setLoadingData(false)
      }
      fetchCampana()
    }
  }, [isEditing, id, navigate])

  const update = (field: string, value: any) => setForm((prev) => ({ ...prev, [field]: value }))

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    if (file.size > 5 * 1024 * 1024) {
      toast.error('La imagen no puede superar 5MB')
      return
    }
    setImagenFile(file)
    setImagenPreview(URL.createObjectURL(file))
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.titulo || !form.fecha_inicio || !form.fecha_fin) {
      toast.error('Completa los campos obligatorios')
      return
    }

    const campanaData: Partial<SolicitudCampana> = {
      ...form,
      edad_min: form.edad_min ? parseInt(form.edad_min) : null,
      edad_max: form.edad_max ? parseInt(form.edad_max) : null,
    }

    if (isEditing && id) {
      const ok = await actualizarSolicitud(id, campanaData, imagenFile)
      if (ok) navigate('/proveedor/publicidad/campanas')
    } else {
      const ok = await crearSolicitud({ ...campanaData, estado: 'borrador' }, imagenFile)
      if (ok) navigate('/proveedor/publicidad/campanas')
    }
  }

  if (loadingData) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
      </div>
    )
  }

  return (
    <div className="space-y-6 max-w-2xl mx-auto">
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate('/proveedor/publicidad/campanas')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">
            {isEditing ? 'Editar campaña' : 'Nueva campaña'}
          </h1>
          <p className="text-sm text-muted-foreground">Diseña tu campaña publicitaria</p>
        </div>
      </div>

      <Card>
        <CardContent className="p-6">
          <form onSubmit={handleSubmit} className="space-y-5">
            <div className="space-y-2">
              <Label>Título *</Label>
              <Input
                value={form.titulo}
                onChange={(e) => update('titulo', e.target.value)}
                placeholder="Ej: 20% de descuento en insulina"
                required
              />
            </div>
            <div className="space-y-2">
              <Label>Descripción</Label>
              <Input
                value={form.descripcion}
                onChange={(e) => update('descripcion', e.target.value)}
                placeholder="Detalles de la oferta..."
              />
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo</Label>
                <select
                  value={form.tipo}
                  onChange={(e) => update('tipo', e.target.value)}
                  className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
                >
                  {TIPOS.map((t) => (
                    <option key={t.value} value={t.value}>{t.label}</option>
                  ))}
                </select>
              </div>
              <div className="space-y-2">
                <Label>Link URL</Label>
                <Input
                  type="text"
                  value={form.link_url}
                  onChange={(e) => update('link_url', e.target.value)}
                  placeholder="https://..."
                />
              </div>
              <div className="space-y-2">
                <Label>Fecha inicio *</Label>
                <Input
                  type="date"
                  value={form.fecha_inicio}
                  onChange={(e) => update('fecha_inicio', e.target.value)}
                  required
                />
              </div>
              <div className="space-y-2">
                <Label>Fecha fin *</Label>
                <Input
                  type="date"
                  value={form.fecha_fin}
                  onChange={(e) => update('fecha_fin', e.target.value)}
                  required
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label>Imagen de la campaña</Label>
              <div className="flex items-center gap-4">
                <label className="flex items-center gap-2 px-4 py-2 border border-slate-200 rounded-lg cursor-pointer hover:bg-slate-50 transition-colors">
                  <Upload className="h-4 w-4 text-slate-500" />
                  <span className="text-sm text-slate-600">
                    {imagenFile ? imagenFile.name : 'Seleccionar imagen'}
                  </span>
                  <input
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    className="hidden"
                    onChange={handleFileChange}
                  />
                </label>
                {imagenPreview && (
                  <div className="relative">
                    <img src={imagenPreview} alt="Preview" className="h-16 w-16 object-cover rounded-lg border" />
                    <button
                      type="button"
                      className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full p-0.5"
                      onClick={() => { setImagenFile(null); setImagenPreview(null) }}
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </div>
                )}
              </div>
              <p className="text-xs text-slate-400">Máx 5MB. Formatos: JPG, PNG, WebP</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Filtro por condición</Label>
                <Input
                  value={form.condicion_filtro}
                  onChange={(e) => update('condicion_filtro', e.target.value)}
                  placeholder="Ej: diabetes"
                />
              </div>
              <div className="space-y-2">
                <Label>Filtro por género</Label>
                <select
                  value={form.genero_filtro || ''}
                  onChange={(e) => update('genero_filtro', e.target.value)}
                  className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
                >
                  <option value="">Todos</option>
                  <option value="M">Masculino</option>
                  <option value="F">Femenino</option>
                </select>
              </div>
              <div className="space-y-2">
                <Label>Edad mínima</Label>
                <Input
                  type="number"
                  value={form.edad_min}
                  onChange={(e) => update('edad_min', e.target.value)}
                  placeholder="Ej: 18"
                />
              </div>
              <div className="space-y-2">
                <Label>Edad máxima</Label>
                <Input
                  type="number"
                  value={form.edad_max}
                  onChange={(e) => update('edad_max', e.target.value)}
                  placeholder="Ej: 65"
                />
              </div>
            </div>

            <div className="flex gap-3 pt-2">
              <Button
                type="button"
                variant="outline"
                className="flex-1"
                onClick={() => navigate('/proveedor/publicidad/campanas')}
              >
                Cancelar
              </Button>
              <Button type="submit" className="flex-1 bg-[#1E5C8E] hover:bg-[#164a70]" disabled={saving}>
                {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                {isEditing ? 'Guardar cambios' : 'Enviar a revisión'}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
