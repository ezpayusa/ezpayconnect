import { useEffect, useMemo, useState } from 'react'
import { useLaboratorio } from '@/laboratorio/hooks/useLaboratorio'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { ListChecks, Plus, Trash2, Loader2 } from 'lucide-react'

export default function LabCatalogoPage() {
  const { catalogo, fetchCatalogo, crearCatalogo, toggleCatalogo, eliminarCatalogo } = useLaboratorio()
  const [loading, setLoading] = useState(true)
  const [form, setForm] = useState({ nombre: '', categoria: '' })
  const [saving, setSaving] = useState(false)

  useEffect(() => { fetchCatalogo().finally(() => setLoading(false)) }, [fetchCatalogo])

  const porCategoria = useMemo(() => {
    const acc: Record<string, typeof catalogo> = {}
    catalogo.forEach((c) => {
      const k = c.categoria || 'Sin categoría'
      ;(acc[k] ||= []).push(c)
    })
    return acc
  }, [catalogo])

  const categoriasExistentes = useMemo(
    () => Array.from(new Set(catalogo.map((c) => c.categoria).filter(Boolean))) as string[],
    [catalogo]
  )

  const agregar = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.nombre.trim()) return
    setSaving(true)
    const ok = await crearCatalogo(form.nombre, form.categoria)
    setSaving(false)
    if (ok) setForm({ nombre: '', categoria: form.categoria })
  }

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2 text-[#0c2a26]">
          <ListChecks className="h-7 w-7 text-[#0E7C6B]" /> Catálogo de exámenes
        </h1>
        <p className="text-sm text-muted-foreground">
          Define los exámenes que ofreces. El médico los verá como una hoja con casillas al ordenar.
        </p>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-lg flex items-center gap-2"><Plus className="h-4 w-4" /> Agregar examen</CardTitle></CardHeader>
        <CardContent>
          <form onSubmit={agregar} className="grid grid-cols-1 md:grid-cols-[1fr_220px_auto] gap-3 items-end">
            <div className="space-y-1">
              <Label>Nombre del examen *</Label>
              <Input value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })}
                placeholder="Ej: Hemograma completo" required />
            </div>
            <div className="space-y-1">
              <Label>Categoría (opcional)</Label>
              <Input value={form.categoria} onChange={(e) => setForm({ ...form, categoria: e.target.value })}
                placeholder="Hematología" list="categorias" />
              <datalist id="categorias">
                {categoriasExistentes.map((c) => <option key={c} value={c} />)}
              </datalist>
            </div>
            <Button type="submit" className="bg-[#0E7C6B] hover:bg-[#0a5e51]" disabled={saving || !form.nombre.trim()}>
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
              <span className="ml-1">Agregar</span>
            </Button>
          </form>
        </CardContent>
      </Card>

      {loading ? (
        <div className="flex justify-center py-10"><Loader2 className="h-7 w-7 animate-spin text-[#0E7C6B]" /></div>
      ) : catalogo.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-10 text-center text-muted-foreground">
            <ListChecks className="h-10 w-10 mx-auto mb-3 text-gray-300" />
            Tu catálogo está vacío. Agrega tus exámenes para que los médicos puedan ordenarlos.
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {Object.entries(porCategoria).map(([cat, items]) => (
            <Card key={cat}>
              <CardHeader className="pb-2"><CardTitle className="text-base">{cat}</CardTitle></CardHeader>
              <CardContent className="space-y-2">
                {items.map((c) => (
                  <div key={c.id} className="flex items-center justify-between p-2 rounded-lg hover:bg-gray-50">
                    <div className="flex items-center gap-2">
                      <span className={c.activo ? '' : 'line-through text-muted-foreground'}>{c.nombre}</span>
                      {!c.activo && <Badge variant="outline" className="text-xs">Inactivo</Badge>}
                    </div>
                    <div className="flex items-center gap-2">
                      <Button size="sm" variant="ghost" onClick={() => toggleCatalogo(c.id, !c.activo)}>
                        {c.activo ? 'Desactivar' : 'Activar'}
                      </Button>
                      <Button size="sm" variant="ghost" className="text-red-600 hover:bg-red-50" onClick={() => eliminarCatalogo(c.id)}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
