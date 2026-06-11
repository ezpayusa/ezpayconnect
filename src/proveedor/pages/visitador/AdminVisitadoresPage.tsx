import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useVisitadoresEmpresa } from '@/proveedor/hooks/useVisitadoresEmpresa'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { toast } from 'sonner'
import { UserPlus, Users, Mail, Phone, Copy, MessageCircle, CheckCircle, Clock, AlertCircle } from 'lucide-react'

export default function AdminVisitadoresPage() {
  const { visitadores, loading } = useVisitadoresEmpresa()
  const { puede } = useProveedorAuth()

  if (!puede('visitadores.gestionar')) {
    return (
      <div className="p-8 text-center">
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">Solo administradores pueden gestionar visitadores.</p>
      </div>
    )
  }

  return (
    <div className="p-4 max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Visitadores Médicos</h1>
        <p className="text-muted-foreground">
          Equipo de visitadores de tu empresa. Haz clic en un visitador para ver su desempeño.
          Para invitar personal, ve a <span className="font-medium">"Personal y Roles"</span>.
        </p>
      </div>

      {/* Visitadores activos */}
      <div className="space-y-3">
        <h2 className="text-lg font-semibold">Visitadores activos ({visitadores.length})</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {visitadores.map((v) => (
            <Link key={v.id} to={`/proveedor/visitadores/${v.id}`} className="block">
            <Card className="hover:shadow-md hover:border-primary/40 transition cursor-pointer h-full">
              <CardContent className="p-4 space-y-3">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center text-primary font-bold">
                      {v.nombre_completo.split(' ').map((n) => n[0]).join('').slice(0, 2).toUpperCase()}
                    </div>
                    <div>
                      <h3 className="font-semibold">{v.nombre_completo}</h3>
                      <Badge variant="outline" className="text-xs">Visitador Médico</Badge>
                    </div>
                  </div>
                </div>

                <Separator />

                <div className="space-y-1 text-sm text-muted-foreground">
                  <p className="flex items-center gap-2">
                    <Mail className="w-4 h-4" /> {v.email}
                  </p>
                  {v.telefono && (
                    <p className="flex items-center gap-2">
                      <Phone className="w-4 h-4" /> {v.telefono}
                    </p>
                  )}
                </div>

                <div className="grid grid-cols-2 gap-2 pt-2">
                  <div className="bg-muted rounded p-2 text-center">
                    <p className="text-lg font-bold">{v.visitas_asignadas || 0}</p>
                    <p className="text-xs text-muted-foreground">Visitas asignadas</p>
                  </div>
                  <div className="bg-green-50 rounded p-2 text-center">
                    <p className="text-lg font-bold text-green-700">{v.visitas_completadas || 0}</p>
                    <p className="text-xs text-green-600">Completadas</p>
                  </div>
                </div>
                <p className="text-xs text-primary font-medium pt-1">Ver desempeño →</p>
              </CardContent>
            </Card>
            </Link>
          ))}
        </div>
      </div>

      {visitadores.length === 0 && !loading && (
        <div className="text-center py-12 text-muted-foreground">
          <Users className="mx-auto h-12 w-12 mb-4" />
          <h3 className="text-lg font-medium">No hay visitadores registrados</h3>
          <p className="mt-1">Invita a tu primer visitador médico para comenzar.</p>
        </div>
      )}
    </div>
  )
}
