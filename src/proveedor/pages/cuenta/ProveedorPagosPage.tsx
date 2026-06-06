import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { CreditCard } from 'lucide-react'

export default function ProveedorPagosPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Historial de Pagos</h1>
        <p className="text-sm text-muted-foreground">Revisa tus pagos y comprobantes</p>
      </div>

      <Card className="bg-gray-50 border-dashed">
        <CardContent className="p-8 text-center">
          <CreditCard className="h-10 w-10 text-gray-300 mx-auto mb-3" />
          <h3 className="text-lg font-semibold text-gray-700">Sin pagos registrados</h3>
          <p className="text-sm text-muted-foreground max-w-md mx-auto mt-1">
            Aquí aparecerán tus pagos de planes y campañas.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
