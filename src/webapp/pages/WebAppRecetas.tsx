import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { FileText, Download, QrCode, Pill } from 'lucide-react'

export default function WebAppRecetas() {
  const [expandedId, setExpandedId] = useState<number | null>(null)

  const recetas: any[] = [] // TODO: hook useWebAppRecetas

  const getEstadoColor = (estado: string) => {
    switch (estado) {
      case 'activa': return 'bg-emerald-50 text-emerald-700 border-emerald-200'
      case 'completada': return 'bg-blue-50 text-blue-700 border-blue-200'
      case 'vencida': return 'bg-amber-50 text-amber-700 border-amber-200'
      case 'cancelada': return 'bg-red-50 text-red-700 border-red-200'
      default: return 'bg-slate-50 text-slate-700'
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Mis Recetas</h1>
        <p className="text-slate-500 mt-1">Tus recetas médicas digitales</p>
      </div>

      {recetas.length === 0 ? (
        <div className="text-center py-12">
          <FileText className="h-12 w-12 text-slate-300 mx-auto mb-3" />
          <p className="text-slate-500">No tienes recetas registradas</p>
        </div>
      ) : (
        <div className="space-y-4">
          {recetas.map((r) => (
            <Card key={r.id} className="bg-white border-slate-100">
              <CardContent className="p-4">
                {/* TODO: render recetas */}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
