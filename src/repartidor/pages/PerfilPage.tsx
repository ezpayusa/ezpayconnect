import { useNavigate } from 'react-router-dom'
import { LogOut, User, Building2, BadgeCheck } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'

function iniciales(nombre?: string | null): string {
  if (!nombre) return '··'
  const p = nombre.trim().split(/\s+/)
  return ((p[0]?.[0] ?? '') + (p[1]?.[0] ?? '')).toUpperCase() || '··'
}

export default function PerfilPage() {
  const navigate = useNavigate()
  const { cuenta, empresa, logout } = useProveedorAuth()

  const salir = async () => {
    await logout()
    navigate('/farmacia/login', { replace: true })
  }

  const fila = (Icon: typeof User, label: string, valor: string) => (
    <div className="flex items-center gap-3 px-4 py-3">
      <Icon className="h-5 w-5 text-gray-400 shrink-0" />
      <div className="min-w-0">
        <p className="text-xs text-gray-400">{label}</p>
        <p className="text-sm text-gray-800 truncate">{valor}</p>
      </div>
    </div>
  )

  return (
    <div className="space-y-5">
      <div className="flex flex-col items-center gap-2 pt-4">
        <div className="h-20 w-20 rounded-full bg-[#1E5C8E] text-white grid place-items-center text-2xl font-semibold">
          {iniciales(cuenta?.nombre_completo)}
        </div>
        <p className="font-semibold text-gray-800">{cuenta?.nombre_completo ?? 'Repartidor'}</p>
      </div>

      <div className="rounded-2xl bg-white border border-gray-100 divide-y divide-gray-100">
        {fila(BadgeCheck, 'Rol', 'Repartidor')}
        {fila(Building2, 'Farmacia', empresa?.nombre_empresa ?? '—')}
        {fila(User, 'Sucursal', cuenta?.sucursal_id ? `Sucursal ${cuenta.sucursal_id}` : '—')}
      </div>

      <Button type="button" variant="outline" className="w-full border-red-300 text-red-600 hover:bg-red-50" onClick={salir}>
        <LogOut className="h-4 w-4 mr-1" /> Cerrar sesión
      </Button>
    </div>
  )
}
