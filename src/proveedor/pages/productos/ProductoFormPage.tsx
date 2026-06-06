import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { toast } from 'sonner'
import { ArrowLeft, Loader2, Upload, X } from 'lucide-react'
import { useProductosEmpresa } from '@/proveedor/hooks/useProductosEmpresa'
import { supabase } from '@/lib/supabase'
import type { ProductoEmpresa } from '@/proveedor/types/proveedor.types'

export default function ProductoFormPage() {
  const navigate = useNavigate()
  const { id } = useParams()
  const isEditing = Boolean(id)
  const { crearProducto, actualizarProducto, saving } = useProductosEmpresa()
  const [loadingData, setLoadingData] = useState(isEditing)

  const [form, setForm] = useState({
    nombre_producto: '',
    principio_activo: '',
    presentacion: '',
    concentracion: '',
    categoria: '',
    precio_unitario: '',
    moneda: 'GTQ',
    stock_disponible: '',
    requiere_receta: false,
    imagen_url: '',
    estado: 'activo' as ProductoEmpresa['estado'],
  })

  const [imagenFile, setImagenFile] = useState<File | null>(null)
  const [imagenPreview, setImagenPreview] = useState<string | null>(null)

  useEffect(() => {
    if (isEditing && id) {
      const fetchProducto = async () => {
        const { data, error } = await supabase
          .from('productos_empresa')
          .select('*')
          .eq('id', id)
          .single()

        if (error || !data) {
          toast.error('Error cargando producto')
          navigate('/proveedor/productos')
          return
        }

        setForm({
          nombre_producto: data.nombre_producto || '',
          principio_activo: data.principio_activo || '',
          presentacion: data.presentacion || '',
          concentracion: data.concentracion || '',
          categoria: data.categoria || '',
          precio_unitario: data.precio_unitario ? String(data.precio_unitario) : '',
          moneda: data.moneda || 'GTQ',
          stock_disponible: data.stock_disponible ? String(data.stock_disponible) : '',
          requiere_receta: data.requiere_receta || false,
          imagen_url: data.imagen_url || '',
          estado: data.estado || 'activo',
        })

        if (data.imagen_url) {
          setImagenPreview(data.imagen_url)
        }
        setLoadingData(false)
      }
      fetchProducto()
    }
  }, [isEditing, id, navigate])

  const update = (field: string, value: any) => setForm((prev) => ({ ...prev, [field]: value }))

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    if (file.size > 2 * 1024 * 1024) {
      toast.error('La imagen no puede superar 2MB')
      return
    }
    setImagenFile(file)
    setImagenPreview(URL.createObjectURL(file))
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.nombre_producto || !form.precio_unitario) {
      toast.error('Completa los campos obligatorios')
      return
    }

    const productoData: Partial<ProductoEmpresa> = {
      ...form,
      precio_unitario: parseFloat(form.precio_unitario),
      stock_disponible: parseInt(form.stock_disponible || '0'),
    }

    if (isEditing && id) {
      const ok = await actualizarProducto(id, productoData, imagenFile)
      if (ok) navigate('/proveedor/productos')
    } else {
      const ok = await crearProducto(productoData, imagenFile)
      if (ok) navigate('/proveedor/productos')
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
        <Button variant="ghost" size="icon" onClick={() => navigate('/proveedor/productos')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">
            {isEditing ? 'Editar producto' : 'Nuevo producto'}
          </h1>
          <p className="text-sm text-muted-foreground">Completa la información de tu producto</p>
        </div>
      </div>

      <Card>
        <CardContent className="p-6">
          <form onSubmit={handleSubmit} className="space-y-5">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2 md:col-span-2">
                <Label>Nombre del producto *</Label>
                <Input
                  value={form.nombre_producto}
                  onChange={(e) => update('nombre_producto', e.target.value)}
                  placeholder="Ej: Paracetamol 500mg"
                  required
                />
              </div>
              <div className="space-y-2">
                <Label>Principio activo</Label>
                <Input
                  value={form.principio_activo}
                  onChange={(e) => update('principio_activo', e.target.value)}
                  placeholder="Ej: Paracetamol"
                />
              </div>
              <div className="space-y-2">
                <Label>Presentación</Label>
                <Input
                  value={form.presentacion}
                  onChange={(e) => update('presentacion', e.target.value)}
                  placeholder="Ej: Tabletas"
                />
              </div>
              <div className="space-y-2">
                <Label>Concentración</Label>
                <Input
                  value={form.concentracion}
                  onChange={(e) => update('concentracion', e.target.value)}
                  placeholder="Ej: 500 mg"
                />
              </div>
              <div className="space-y-2">
                <Label>Categoría</Label>
                <Input
                  value={form.categoria}
                  onChange={(e) => update('categoria', e.target.value)}
                  placeholder="Ej: Analgésicos"
                />
              </div>
              <div className="space-y-2">
                <Label>Precio unitario *</Label>
                <Input
                  type="number"
                  step="0.01"
                  min="0"
                  value={form.precio_unitario}
                  onChange={(e) => update('precio_unitario', e.target.value)}
                  placeholder="0.00"
                  required
                />
              </div>
              <div className="space-y-2">
                <Label>Stock disponible</Label>
                <Input
                  type="number"
                  min="0"
                  value={form.stock_disponible}
                  onChange={(e) => update('stock_disponible', e.target.value)}
                  placeholder="0"
                />
              </div>
              {isEditing && (
                <div className="space-y-2">
                  <Label>Estado</Label>
                  <select
                    value={form.estado}
                    onChange={(e) => update('estado', e.target.value)}
                    className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
                  >
                    <option value="activo">Activo</option>
                    <option value="agotado">Agotado</option>
                    <option value="descontinuado">Descontinuado</option>
                  </select>
                </div>
              )}
            </div>

            <div className="space-y-2">
              <Label>Imagen del producto</Label>
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
                    <img
                      src={imagenPreview}
                      alt="Preview"
                      className="h-16 w-16 object-cover rounded-lg border"
                    />
                    <button
                      type="button"
                      className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full p-0.5"
                      onClick={() => {
                        setImagenFile(null)
                        setImagenPreview(null)
                        update('imagen_url', '')
                      }}
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </div>
                )}
              </div>
              <p className="text-xs text-slate-400">Máx 2MB. Formatos: JPG, PNG, WebP</p>
            </div>

            <div className="flex items-center justify-between p-4 bg-gray-50 rounded-xl">
              <div>
                <Label className="font-medium">Requiere receta médica</Label>
                <p className="text-sm text-gray-500">Activa si el producto necesita receta</p>
              </div>
              <Switch
                checked={form.requiere_receta}
                onCheckedChange={(checked) => update('requiere_receta', checked)}
              />
            </div>

            <div className="flex gap-3 pt-2">
              <Button
                type="button"
                variant="outline"
                className="flex-1"
                onClick={() => navigate('/proveedor/productos')}
              >
                Cancelar
              </Button>
              <Button type="submit" className="flex-1 bg-[#1E5C8E] hover:bg-[#164a70]" disabled={saving}>
                {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                {isEditing ? 'Guardar cambios' : 'Crear producto'}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
