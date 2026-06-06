import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Building2, Mail, Phone, MapPin, Briefcase } from 'lucide-react'

export default function ProveedorPerfilPage() {
  const { empresa, cuenta } = useProveedorAuth()

  return (
    <div className="space-y-6 max-w-2xl mx-auto">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Perfil de Empresa</h1>
        <p className="text-sm text-muted-foreground">Información de tu empresa registrada</p>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center gap-2">
            <Building2 className="h-5 w-5 text-[#1E5C8E]" />
            {empresa?.nombre_empresa || 'Empresa'}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          <div className="flex items-center gap-3">
            <Briefcase className="h-4 w-4 text-muted-foreground" />
            <span className="text-muted-foreground w-24">Tipo</span>
            <span className="font-medium capitalize">{empresa?.tipo?.replace('_', ' ') || '-'}</span>
          </div>
          <div className="flex items-center gap-3">
            <Mail className="h-4 w-4 text-muted-foreground" />
            <span className="text-muted-foreground w-24">Email</span>
            <span className="font-medium">{empresa?.email_contacto || '-'}</span>
          </div>
          <div className="flex items-center gap-3">
            <Phone className="h-4 w-4 text-muted-foreground" />
            <span className="text-muted-foreground w-24">Teléfono</span>
            <span className="font-medium">{empresa?.telefono || '-'}</span>
          </div>
          <div className="flex items-center gap-3">
            <MapPin className="h-4 w-4 text-muted-foreground" />
            <span className="text-muted-foreground w-24">Ubicación</span>
            <span className="font-medium">
              {[empresa?.direccion, empresa?.ciudad].filter(Boolean).join(', ') || '-'}
            </span>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg">Representante</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          <div className="flex items-center gap-3">
            <span className="text-muted-foreground w-24">Nombre</span>
            <span className="font-medium">{cuenta?.nombre_completo || '-'}</span>
          </div>
          <div className="flex items-center gap-3">
            <span className="text-muted-foreground w-24">Email</span>
            <span className="font-medium">{cuenta?.email || '-'}</span>
          </div>
          <div className="flex items-center gap-3">
            <span className="text-muted-foreground w-24">Rol</span>
            <span className="font-medium capitalize">{cuenta?.rol_en_empresa || '-'}</span>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
