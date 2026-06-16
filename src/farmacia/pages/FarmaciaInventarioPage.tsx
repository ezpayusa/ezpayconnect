import { useEffect, useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { toast } from 'sonner'
import { Package, Loader2, Save, Upload, Plus, EyeOff, Eye } from 'lucide-react'
import ImportarCatalogoModal from '@/farmacia/pages/ImportarCatalogoModal'

interface Med {
  id: string
  farmacia_id: number
  nombre_medicamento: string
  presentacion: string | null
  stock_actual: number | null
  stock_minimo: number | null
  precio_unitario: number | null
  activo: boolean | null
}
interface Sucursal { id: number; nombre: string }

export default function FarmaciaInventarioPage() {
  const { empresa } = useProveedorAuth()
  const { tienePermiso, loading: permLoading } = useFarmaciaPermisos()
  const [meds, setMeds] = useState<Med[]>([])
  const [sucursales, setSucursales] = useState<Sucursal[]>([])
  const [loading, setLoading] = useState(true)
  const [guardando, setGuardando] = useState<string | null>(null)
  const [edits, setEdits] = useState<Record<string, { stock_actual: string; precio_unitario: string }>>({})
  const [importOpen, setImportOpen] = useState(false)
  const [alta, setAlta] = useState<{ farmacia_id: string; nombre: string; stock: string; precio: string } | null>(null)
  const [creando, setCreando] = useState(false)

  const puedeEditar = tienePermiso('inventario_editar')

  const cargar = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data: farmacias } = await supabase.from('farmacias').select('id, nombre').eq('empresa_id', empresa.id)
    const sucs = (farmacias || []) as Sucursal[]
    setSucursales(sucs)
    const ids = sucs.map((f) => f.id)
    if (!ids.length) { setMeds([]); setLoading(false); return }
    const { data, error } = await supabase
      .from('farmacia_medicamentos')
      .select('id, farmacia_id, nombre_medicamento, presentacion, stock_actual, stock_minimo, precio_unitario, activo')
      .in('farmacia_id', ids)
      .order('nombre_medicamento')
    if (error) { toast.error('Error cargando inventario'); console.error(error) }
    else setMeds((data || []) as Med[])
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => { cargar() }, [cargar])

  const guardar = async (m: Med) => {
    const e = edits[m.id]
    if (!e) return
    setGuardando(m.id)
    const { error } = await supabase.from('farmacia_medicamentos')
      .update({ stock_actual: Number(e.stock_actual), precio_unitario: Number(e.precio_unitario) }).eq('id', m.id)
    setGuardando(null)
    if (error) { toast.error(error.message || 'No se pudo guardar'); return }
    toast.success('Actualizado')
    setEdits((prev) => { const n = { ...prev }; delete n[m.id]; return n })
    cargar()
  }

  const toggleActivo = async (m: Med) => {
    const { error } = await supabase.from('farmacia_medicamentos').update({ activo: !(m.activo ?? true) }).eq('id', m.id)
    if (error) { toast.error(error.message || 'No se pudo cambiar el estado'); return }
    toast.success((m.activo ?? true) ? 'Desactivado' : 'Activado')
    cargar()
  }

  const crearProducto = async () => {
    if (!alta || !alta.farmacia_id || !alta.nombre.trim()) { toast.error('Sucursal y nombre son obligatorios'); return }
    setCreando(true)
    const { error } = await supabase.from('farmacia_medicamentos').insert({
      farmacia_id: Number(alta.farmacia_id), nombre_medicamento: alta.nombre.trim(),
      stock_actual: Number(alta.stock || 0), precio_unitario: alta.precio ? Number(alta.precio) : null, activo: true,
    })
    setCreando(false)
    if (error) {
      // unique (farmacia_id, nombre_normalizado): ya existe ese medicamento en la sucursal
      toast.error(error.message?.includes('uniq') || error.message?.includes('duplicate') ? 'Ese medicamento ya existe en la sucursal' : (error.message || 'No se pudo crear'))
      return
    }
    toast.success('Producto agregado'); setAlta(null); cargar()
  }

  if (loading || permLoading) return <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2"><Package className="h-6 w-6" /> Catálogo / Inventario</h1>
          <p className="text-sm text-muted-foreground">
            {puedeEditar ? 'Gestiona tu catálogo: alta, stock, precio, activar/desactivar e importar.' : 'Vista de solo lectura (tu rol no edita inventario).'}
          </p>
        </div>
        {puedeEditar && (
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => setAlta({ farmacia_id: sucursales.length === 1 ? String(sucursales[0].id) : '', nombre: '', stock: '', precio: '' })}>
              <Plus className="h-4 w-4 mr-2" /> Nuevo producto
            </Button>
            <Button className="bg-[#B45309] hover:bg-[#92400e]" onClick={() => setImportOpen(true)}>
              <Upload className="h-4 w-4 mr-2" /> Importar CSV/Excel
            </Button>
          </div>
        )}
      </div>

      {/* Alta rápida */}
      {alta && puedeEditar && (
        <Card><CardContent className="p-3 flex flex-col sm:flex-row sm:items-end gap-2">
          <div className="flex-1">
            <label className="text-xs text-muted-foreground">Sucursal</label>
            <select value={alta.farmacia_id} onChange={(e) => setAlta({ ...alta, farmacia_id: e.target.value })} className="w-full p-2 border rounded-lg h-9">
              <option value="">Seleccionar…</option>
              {sucursales.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
            </select>
          </div>
          <div className="flex-1"><label className="text-xs text-muted-foreground">Nombre</label><Input className="h-9" value={alta.nombre} onChange={(e) => setAlta({ ...alta, nombre: e.target.value })} placeholder="Medicamento" /></div>
          <div><label className="text-xs text-muted-foreground">Stock</label><Input type="number" className="h-9 w-24" value={alta.stock} onChange={(e) => setAlta({ ...alta, stock: e.target.value })} /></div>
          <div><label className="text-xs text-muted-foreground">Precio</label><Input type="number" step="0.01" className="h-9 w-28" value={alta.precio} onChange={(e) => setAlta({ ...alta, precio: e.target.value })} /></div>
          <Button size="sm" className="bg-[#B45309] hover:bg-[#92400e] h-9" disabled={creando} onClick={crearProducto}>{creando ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Agregar'}</Button>
          <Button size="sm" variant="outline" className="h-9" onClick={() => setAlta(null)}>Cancelar</Button>
        </CardContent></Card>
      )}

      {meds.length === 0 ? (
        <Card className="bg-gray-50 border-dashed"><CardContent className="p-8 text-center text-muted-foreground">
          <Package className="h-10 w-10 mx-auto mb-3 text-gray-300" />
          <p>Sin inventario.{puedeEditar ? ' Usa "Nuevo producto" o "Importar" para cargar tu catálogo.' : ''}</p>
          {sucursales.length === 0 && <p className="text-xs mt-2">(Tu farmacia aún no tiene sucursales vinculadas.)</p>}
        </CardContent></Card>
      ) : (
        <div className="space-y-2">
          {meds.map((m) => {
            const e = edits[m.id]; const inactivo = !(m.activo ?? true)
            return (
              <Card key={m.id} className={inactivo ? 'opacity-60' : ''}>
                <CardContent className="p-3 flex flex-col sm:flex-row sm:items-center gap-3">
                  <div className="flex-1 min-w-0">
                    <p className="font-medium truncate">{m.nombre_medicamento} {inactivo && <span className="text-xs text-amber-600">(inactivo)</span>}</p>
                    <p className="text-xs text-muted-foreground truncate">{m.presentacion || '—'}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <label className="text-xs text-muted-foreground">Stock</label>
                    <Input type="number" className="w-24 h-9" disabled={!puedeEditar}
                      value={e ? e.stock_actual : (m.stock_actual ?? 0)}
                      onChange={(ev) => setEdits((p) => ({ ...p, [m.id]: { stock_actual: ev.target.value, precio_unitario: (p[m.id]?.precio_unitario ?? String(m.precio_unitario ?? 0)) } }))} />
                    <label className="text-xs text-muted-foreground">Precio</label>
                    <Input type="number" step="0.01" className="w-28 h-9" disabled={!puedeEditar}
                      value={e ? e.precio_unitario : (m.precio_unitario ?? 0)}
                      onChange={(ev) => setEdits((p) => ({ ...p, [m.id]: { precio_unitario: ev.target.value, stock_actual: (p[m.id]?.stock_actual ?? String(m.stock_actual ?? 0)) } }))} />
                    {puedeEditar && e && (
                      <Button size="sm" className="bg-[#B45309] hover:bg-[#92400e]" disabled={guardando === m.id} onClick={() => guardar(m)}>
                        {guardando === m.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                      </Button>
                    )}
                    {puedeEditar && (
                      <Button size="sm" variant="outline" title={inactivo ? 'Activar' : 'Desactivar'} onClick={() => toggleActivo(m)}>
                        {inactivo ? <Eye className="h-4 w-4" /> : <EyeOff className="h-4 w-4" />}
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      <ImportarCatalogoModal open={importOpen} onClose={() => setImportOpen(false)} sucursales={sucursales} onImported={cargar} />
    </div>
  )
}
