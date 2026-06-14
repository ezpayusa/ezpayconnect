import { useEffect, useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { toast } from 'sonner'
import { Package, Loader2, Save } from 'lucide-react'

interface Med {
  id: string
  farmacia_id: number
  nombre_medicamento: string
  presentacion: string | null
  stock_actual: number | null
  stock_minimo: number | null
  precio_unitario: number | null
}

export default function FarmaciaInventarioPage() {
  const { empresa } = useProveedorAuth()
  const { tienePermiso, loading: permLoading } = useFarmaciaPermisos()
  const [meds, setMeds] = useState<Med[]>([])
  const [loading, setLoading] = useState(true)
  const [guardando, setGuardando] = useState<string | null>(null)
  const [edits, setEdits] = useState<Record<string, { stock_actual: string; precio_unitario: string }>>({})

  const puedeEditar = tienePermiso('inventario_editar')

  const cargar = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data: farmacias } = await supabase.from('farmacias').select('id').eq('empresa_id', empresa.id)
    const ids = (farmacias || []).map((f: { id: number }) => f.id)
    if (!ids.length) { setMeds([]); setLoading(false); return }
    const { data, error } = await supabase
      .from('farmacia_medicamentos')
      .select('id, farmacia_id, nombre_medicamento, presentacion, stock_actual, stock_minimo, precio_unitario')
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
    // La RLS (farm_med_tenant_all → tiene_permiso('inventario_editar') + scope empresa)
    // es la barrera real; si el rol no puede, el UPDATE no afecta filas.
    const { error } = await supabase
      .from('farmacia_medicamentos')
      .update({ stock_actual: Number(e.stock_actual), precio_unitario: Number(e.precio_unitario) })
      .eq('id', m.id)
    setGuardando(null)
    if (error) { toast.error(error.message || 'No se pudo guardar'); return }
    toast.success('Actualizado')
    setEdits((prev) => { const n = { ...prev }; delete n[m.id]; return n })
    cargar()
  }

  if (loading || permLoading) {
    return <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2"><Package className="h-6 w-6" /> Inventario</h1>
        <p className="text-sm text-muted-foreground">
          {puedeEditar ? 'Edita stock y precio de tu inventario.' : 'Vista de solo lectura (tu rol no edita inventario).'}
        </p>
      </div>

      {meds.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center text-muted-foreground">
            <Package className="h-10 w-10 mx-auto mb-3 text-gray-300" />
            <p>Sin inventario. (¿La farmacia ya fue promovida a tenant y tiene sucursales vinculadas?)</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {meds.map((m) => {
            const e = edits[m.id]
            return (
              <Card key={m.id}>
                <CardContent className="p-3 flex flex-col sm:flex-row sm:items-center gap-3">
                  <div className="flex-1 min-w-0">
                    <p className="font-medium truncate">{m.nombre_medicamento}</p>
                    <p className="text-xs text-muted-foreground truncate">{m.presentacion || '—'}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <label className="text-xs text-muted-foreground">Stock</label>
                    <Input
                      type="number" className="w-24 h-9" disabled={!puedeEditar}
                      value={e ? e.stock_actual : (m.stock_actual ?? 0)}
                      onChange={(ev) => setEdits((p) => ({ ...p, [m.id]: { stock_actual: ev.target.value, precio_unitario: (p[m.id]?.precio_unitario ?? String(m.precio_unitario ?? 0)) } }))}
                    />
                    <label className="text-xs text-muted-foreground">Precio</label>
                    <Input
                      type="number" step="0.01" className="w-28 h-9" disabled={!puedeEditar}
                      value={e ? e.precio_unitario : (m.precio_unitario ?? 0)}
                      onChange={(ev) => setEdits((p) => ({ ...p, [m.id]: { precio_unitario: ev.target.value, stock_actual: (p[m.id]?.stock_actual ?? String(m.stock_actual ?? 0)) } }))}
                    />
                    {puedeEditar && e && (
                      <Button size="sm" className="bg-[#B45309] hover:bg-[#92400e]" disabled={guardando === m.id} onClick={() => guardar(m)}>
                        {guardando === m.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
