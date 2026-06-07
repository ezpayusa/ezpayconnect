import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from '@/hooks/usePaisFiltro'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Megaphone, Plus, Trash2, Eye, EyeOff, Loader2, Upload, X } from 'lucide-react'
import { toast } from 'sonner'

interface Campana {
  id: number
  titulo: string
  descripcion: string | null
  tipo: string
  imagen_url: string | null
  link_url: string | null
  fecha_inicio: string
  fecha_fin: string
  activa: boolean
  condicion_filtro: string | null
  genero_filtro: string | null
  edad_min: number | null
  edad_max: number | null
  created_at: string
}

export default function CampanasPublicitariasContent() {
  const [campanas, setCampanas] = useState<Campana[]>([])
  const [loading, setLoading] = useState(true)
  const { paisId } = usePaisFiltro()
  const [mostrarForm, setMostrarForm] = useState(false)
  const [guardando, setGuardando] = useState(false)
  const [imagenFile, setImagenFile] = useState<File | null>(null)
  const [imagenPreview, setImagenPreview] = useState<string | null>(null)
  const [subiendoImagen, setSubiendoImagen] = useState(false)

  const [form, setForm] = useState({
    titulo: '',
    descripcion: '',
    tipo: 'farmacia',
    imagen_url: '',
    link_url: '',
    fecha_inicio: new Date().toISOString().split('T')[0],
    fecha_fin: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0],
    condicion_filtro: '',
    genero_filtro: '',
    edad_min: '',
    edad_max: '',
  })

  const fetchCampanas = async () => {
    setLoading(true)
    let query = supabase
      .from('campanas_publicitarias')
      .select('*')
    if (paisId) query = query.eq('pais_id', paisId)
    const { data, error } = await query.order('created_at', { ascending: false })

    if (error) {
      toast.error('Error cargando campañas')
      console.error(error)
    } else {
      setCampanas(data || [])
    }
    setLoading(false)
  }

  useEffect(() => {
    fetchCampanas()
  }, [])

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

  const subirImagen = async (): Promise<string | null> => {
    if (!imagenFile) return form.imagen_url || null
    setSubiendoImagen(true)
    const fileExt = imagenFile.name.split('.').pop()
    const fileName = `${Date.now()}.${fileExt}`
    const { error: uploadError } = await supabase.storage
      .from('campanas')
      .upload(fileName, imagenFile, { upsert: true })

    if (uploadError) {
      toast.error('Error subiendo imagen')
      console.error(uploadError)
      setSubiendoImagen(false)
      return null
    }

    const { data: publicUrlData } = supabase.storage.from('campanas').getPublicUrl(fileName)
    setSubiendoImagen(false)
    return publicUrlData.publicUrl
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.titulo || !form.fecha_fin) {
      toast.error('Título y fecha de fin son obligatorios')
      return
    }

    setGuardando(true)
    const imagenUrl = await subirImagen()

    const { error } = await supabase.from('campanas_publicitarias').insert({
      titulo: form.titulo,
      descripcion: form.descripcion || null,
      tipo: form.tipo,
      imagen_url: imagenUrl,
      link_url: form.link_url || null,
      fecha_inicio: form.fecha_inicio,
      pais_id: paisId,
      fecha_fin: form.fecha_fin,
      condicion_filtro: form.condicion_filtro || null,
      genero_filtro: form.genero_filtro || null,
      edad_min: form.edad_min ? parseInt(form.edad_min) : null,
      edad_max: form.edad_max ? parseInt(form.edad_max) : null,
    })

    if (error) {
      toast.error('Error creando campaña')
      console.error(error)
    } else {
      toast.success('Campaña creada correctamente')
      setForm({
        titulo: '',
        descripcion: '',
        tipo: 'farmacia',
        imagen_url: '',
        link_url: '',
        fecha_inicio: new Date().toISOString().split('T')[0],
        fecha_fin: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0],
        condicion_filtro: '',
        genero_filtro: '',
        edad_min: '',
        edad_max: '',
      })
      setImagenFile(null)
      setImagenPreview(null)
      setMostrarForm(false)
      fetchCampanas()
    }
    setGuardando(false)
  }

  const toggleActiva = async (campana: Campana) => {
    const { error } = await supabase
      .from('campanas_publicitarias')
      .update({ activa: !campana.activa })
      .eq('id', campana.id)

    if (error) {
      toast.error('Error actualizando campaña')
    } else {
      toast.success(campana.activa ? 'Campaña pausada' : 'Campaña activada')
      fetchCampanas()
    }
  }

  const eliminarCampana = async (id: number) => {
    if (!confirm('¿Eliminar esta campaña permanentemente?')) return
    const { error } = await supabase.from('campanas_publicitarias').delete().eq('id', id)
    if (error) {
      toast.error('Error eliminando campaña')
    } else {
      toast.success('Campaña eliminada')
      fetchCampanas()
    }
  }

  const tipoColor: Record<string, string> = {
    farmacia: 'bg-emerald-100 text-emerald-700',
    equipo_medico: 'bg-blue-100 text-blue-700',
    laboratorio: 'bg-amber-100 text-amber-700',
    general: 'bg-slate-100 text-slate-700',
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-800 flex items-center gap-2">
            <Megaphone className="h-6 w-6 text-rose-500" />
            Campañas Publicitarias
          </h1>
          <p className="text-slate-500 mt-1">Gestiona publicidad de medicamentos y equipos médicos para los pacientes</p>
        </div>
        <Button onClick={() => setMostrarForm(!mostrarForm)}>
          <Plus className="h-4 w-4 mr-1" />
          {mostrarForm ? 'Cancelar' : 'Nueva campaña'}
        </Button>
      </div>

      {mostrarForm && (
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Nueva campaña</CardTitle>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="md:col-span-2">
                <Label>Título *</Label>
                <Input
                  value={form.titulo}
                  onChange={(e) => setForm({ ...form, titulo: e.target.value })}
                  placeholder="Ej: 20% de descuento en insulina"
                  required
                />
              </div>
              <div className="md:col-span-2">
                <Label>Descripción</Label>
                <Input
                  value={form.descripcion}
                  onChange={(e) => setForm({ ...form, descripcion: e.target.value })}
                  placeholder="Detalles de la oferta..."
                />
              </div>
              <div>
                <Label>Tipo</Label>
                <Select value={form.tipo} onValueChange={(v) => setForm({ ...form, tipo: v })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="farmacia">Farmacia</SelectItem>
                    <SelectItem value="equipo_medico">Equipo Médico</SelectItem>
                    <SelectItem value="laboratorio">Laboratorio</SelectItem>
                    <SelectItem value="general">General</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="md:col-span-2">
                <Label>Imagen del producto / cupón</Label>
                <div className="flex items-center gap-4">
                  <label className="flex items-center gap-2 px-4 py-2 border border-slate-200 rounded-lg cursor-pointer hover:bg-slate-50 transition-colors">
                    <Upload className="h-4 w-4 text-slate-500" />
                    <span className="text-sm text-slate-600">
                      {imagenFile ? imagenFile.name : 'Seleccionar imagen'}
                    </span>
                    <input
                      type="file"
                      accept="image/*"
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
                  {subiendoImagen && <Loader2 className="h-4 w-4 animate-spin text-slate-400" />}
                </div>
                <p className="text-xs text-slate-400 mt-1">Máx 5MB. Formatos: JPG, PNG, WebP</p>
              </div>
              <div className="md:col-span-2">
                <Label>Link de la oferta</Label>
                <Input
                  value={form.link_url}
                  onChange={(e) => setForm({ ...form, link_url: e.target.value })}
                  placeholder="https://farmacia-afiliada.com/oferta"
                />
              </div>
              <div>
                <Label>Fecha inicio</Label>
                <Input
                  type="date"
                  value={form.fecha_inicio}
                  onChange={(e) => setForm({ ...form, fecha_inicio: e.target.value })}
                />
              </div>
              <div>
                <Label>Fecha fin *</Label>
                <Input
                  type="date"
                  value={form.fecha_fin}
                  onChange={(e) => setForm({ ...form, fecha_fin: e.target.value })}
                  required
                />
              </div>
              <div>
                <Label>Filtro por condición</Label>
                <Input
                  value={form.condicion_filtro}
                  onChange={(e) => setForm({ ...form, condicion_filtro: e.target.value })}
                  placeholder="Ej: diabetes"
                />
              </div>
              <div>
                <Label>Filtro por género</Label>
                <Select value={form.genero_filtro || 'todos'} onValueChange={(v) => setForm({ ...form, genero_filtro: v === 'todos' ? '' : v })}>
                  <SelectTrigger>
                    <SelectValue placeholder="Todos" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="todos">Todos</SelectItem>
                    <SelectItem value="M">Masculino</SelectItem>
                    <SelectItem value="F">Femenino</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label>Edad mínima</Label>
                <Input
                  type="number"
                  value={form.edad_min}
                  onChange={(e) => setForm({ ...form, edad_min: e.target.value })}
                  placeholder="Ej: 18"
                />
              </div>
              <div>
                <Label>Edad máxima</Label>
                <Input
                  type="number"
                  value={form.edad_max}
                  onChange={(e) => setForm({ ...form, edad_max: e.target.value })}
                  placeholder="Ej: 65"
                />
              </div>
              <div className="md:col-span-2">
                <Button type="submit" disabled={guardando} className="w-full md:w-auto">
                  {guardando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Plus className="h-4 w-4 mr-1" />}
                  Crear campaña
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : campanas.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-slate-500">
            <Megaphone className="h-12 w-12 mx-auto mb-3 text-slate-300" />
            <p>No hay campañas creadas aún</p>
            <p className="text-sm mt-1">Crea tu primera campaña para empezar a monetizar el portal</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {campanas.map((c) => (
            <Card key={c.id} className={c.activa ? '' : 'opacity-60'}>
              <CardContent className="p-4">
                {c.imagen_url && (
                  <div className="h-32 w-full bg-slate-100 rounded-lg mb-3 overflow-hidden">
                    <img
                      src={c.imagen_url}
                      alt={c.titulo}
                      className="w-full h-full object-cover"
                      onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
                    />
                  </div>
                )}
                <div className="flex items-center gap-2 mb-2">
                  <Badge className={tipoColor[c.tipo] || tipoColor.general}>
                    {c.tipo}
                  </Badge>
                  <Badge variant={c.activa ? 'default' : 'secondary'}>
                    {c.activa ? 'Activa' : 'Pausada'}
                  </Badge>
                </div>
                <h3 className="font-semibold text-slate-800">{c.titulo}</h3>
                {c.descripcion && <p className="text-sm text-slate-500 mt-1 line-clamp-2">{c.descripcion}</p>}
                <div className="text-xs text-slate-400 mt-2">
                  {c.fecha_inicio} → {c.fecha_fin}
                </div>
                {(c.condicion_filtro || c.genero_filtro || c.edad_min || c.edad_max) && (
                  <div className="text-xs text-slate-400 mt-1">
                    Filtros: {[c.condicion_filtro, c.genero_filtro, c.edad_min && `≥${c.edad_min}`, c.edad_max && `≤${c.edad_max}`].filter(Boolean).join(' · ')}
                  </div>
                )}
                <div className="flex items-center gap-2 mt-3">
                  <Button size="sm" variant="outline" className="flex-1" onClick={() => toggleActiva(c)}>
                    {c.activa ? <EyeOff className="h-4 w-4 mr-1" /> : <Eye className="h-4 w-4 mr-1" />}
                    {c.activa ? 'Pausar' : 'Activar'}
                  </Button>
                  <Button size="sm" className="gap-1 bg-red-600 hover:bg-red-700 text-white font-semibold shadow-sm" onClick={() => eliminarCampana(c.id)}>
                    <Trash2 className="h-4 w-4" /> Eliminar
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
