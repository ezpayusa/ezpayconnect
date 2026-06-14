import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent } from '@/components/ui/card'
import { Package, Building2, AlertTriangle, Users } from 'lucide-react'

export default function FarmaciaDashboard() {
  const { empresa } = useProveedorAuth()
  const [stats, setStats] = useState({ farmacias: 0, medicamentos: 0, bajoStock: 0, miembros: 0 })

  useEffect(() => {
    if (!empresa?.id) return
    ;(async () => {
      const { data: farmacias } = await supabase.from('farmacias').select('id').eq('empresa_id', empresa.id)
      const ids = (farmacias || []).map((f: { id: number }) => f.id)
      let medicamentos = 0, bajoStock = 0
      if (ids.length) {
        const { data: meds } = await supabase
          .from('farmacia_medicamentos')
          .select('id, stock_actual, stock_minimo')
          .in('farmacia_id', ids)
        medicamentos = (meds || []).length
        bajoStock = (meds || []).filter((m: any) => (m.stock_actual ?? 0) <= (m.stock_minimo ?? 0)).length
      }
      const { count: miembros } = await supabase
        .from('cuentas_proveedor')
        .select('id', { count: 'exact', head: true })
        .eq('empresa_id', empresa.id)
      setStats({ farmacias: ids.length, medicamentos, bajoStock, miembros: miembros || 0 })
    })()
  }, [empresa?.id])

  const cards = [
    { label: 'Sucursales', value: stats.farmacias, icon: Building2, color: 'text-amber-600' },
    { label: 'Medicamentos', value: stats.medicamentos, icon: Package, color: 'text-emerald-600' },
    { label: 'Bajo stock', value: stats.bajoStock, icon: AlertTriangle, color: 'text-red-600' },
    { label: 'Personal', value: stats.miembros, icon: Users, color: 'text-sky-600' },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Panel de Farmacia</h1>
        <p className="text-sm text-muted-foreground">{empresa?.nombre_empresa}</p>
      </div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {cards.map((c) => (
          <Card key={c.label}>
            <CardContent className="p-4">
              <c.icon className={`h-6 w-6 ${c.color} mb-2`} />
              <div className="text-2xl font-bold">{c.value}</div>
              <div className="text-xs text-muted-foreground">{c.label}</div>
            </CardContent>
          </Card>
        ))}
      </div>
      <div className="flex flex-wrap gap-3">
        <Link to="/farmacia/inventario" className="text-sm text-[#B45309] hover:underline">Gestionar inventario →</Link>
        <Link to="/farmacia/personal" className="text-sm text-[#B45309] hover:underline">Personal y roles →</Link>
      </div>
    </div>
  )
}
