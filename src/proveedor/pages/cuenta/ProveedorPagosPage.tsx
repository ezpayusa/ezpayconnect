import { usePagosProveedor } from '@/proveedor/hooks/usePagosProveedor'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { CreditCard, Download, ExternalLink, Loader2 } from 'lucide-react'

function formatMoneda(monto: number, moneda: string) {
  return new Intl.NumberFormat('es-GT', {
    style: 'currency',
    currency: moneda || 'GTQ',
  }).format(monto)
}

function formatFecha(fecha: string | null) {
  if (!fecha) return '-'
  return new Date(fecha).toLocaleDateString('es-GT', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

function estadoColor(estado: string) {
  switch (estado) {
    case 'verificado':
      return 'bg-emerald-50 text-emerald-700 border-emerald-200'
    case 'pendiente':
      return 'bg-amber-50 text-amber-700 border-amber-200'
    case 'rechazado':
      return 'bg-red-50 text-red-700 border-red-200'
    default:
      return 'bg-gray-50 text-gray-700 border-gray-200'
  }
}

function tipoLabel(tipo: string) {
  const map: Record<string, string> = {
    plan_publicidad: 'Plan publicidad',
    plan_visitador: 'Plan visitador',
    campana: 'Campaña',
    suscripcion: 'Suscripción',
  }
  return map[tipo] || tipo
}

export default function ProveedorPagosPage() {
  const { pagos, loading } = usePagosProveedor()

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Historial de Pagos</h1>
        <p className="text-sm text-muted-foreground">Revisa tus pagos y comprobantes</p>
      </div>

      {loading ? (
        <div className="space-y-3">
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-12 w-full" />
        </div>
      ) : pagos.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center">
            <CreditCard className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-gray-700">Sin pagos registrados</h3>
            <p className="text-sm text-muted-foreground max-w-md mx-auto mt-1">
              Aquí aparecerán tus pagos de planes y campañas.
            </p>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">{pagos.length} pago{pagos.length !== 1 ? 's' : ''} registrado{pagos.length !== 1 ? 's' : ''}</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b bg-muted/50">
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Tipo</th>
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Monto</th>
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Estado</th>
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Fecha</th>
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Método</th>
                    <th className="text-right px-4 py-3 font-medium text-muted-foreground">Comprobante</th>
                  </tr>
                </thead>
                <tbody>
                  {pagos.map((pago) => (
                    <tr key={pago.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                      <td className="px-4 py-3 font-medium">{tipoLabel(pago.tipo)}</td>
                      <td className="px-4 py-3">{formatMoneda(pago.monto, pago.moneda)}</td>
                      <td className="px-4 py-3">
                        <Badge variant="outline" className={estadoColor(pago.estado)}>
                          {pago.estado}
                        </Badge>
                      </td>
                      <td className="px-4 py-3 text-muted-foreground">{formatFecha(pago.fecha_pago)}</td>
                      <td className="px-4 py-3 text-muted-foreground capitalize">{pago.metodo_pago || '-'}</td>
                      <td className="px-4 py-3 text-right">
                        {pago.comprobante_url ? (
                          <Button variant="ghost" size="sm" asChild>
                            <a href={pago.comprobante_url} target="_blank" rel="noopener noreferrer">
                              <ExternalLink className="h-4 w-4 mr-1" />
                              Ver
                            </a>
                          </Button>
                        ) : (
                          <span className="text-muted-foreground text-xs">-</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
