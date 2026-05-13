import { useAuth } from '@/hooks/useAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Settings, User, Shield, Download } from 'lucide-react'

export default function ConfiguracionPage() {
  const { perfil, logout } = useAuth()

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-3xl font-bold text-[#1a2a3a]">Configuracion</h1>
        <p className="text-[#8a9aaa] mt-1">Perfil y preferencias de tu cuenta</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card>
          <CardHeader className="flex flex-row items-center gap-3">
            <User className="h-6 w-6 text-[#1E5C8E]" />
            <CardTitle className="text-lg">Perfil del Medico</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label>Nombre Completo</Label>
              <Input value={perfil?.nombre_completo || ''} readOnly className="bg-gray-50" />
            </div>
            <div className="space-y-2">
              <Label>Correo Electronico</Label>
              <Input value={perfil?.email || ''} readOnly className="bg-gray-50" />
            </div>
            <div className="space-y-2">
              <Label>Rol</Label>
              <Input value={perfil?.rol || 'medico'} readOnly className="bg-gray-50" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center gap-3">
            <Shield className="h-6 w-6 text-[#1E5C8E]" />
            <CardTitle className="text-lg">Seguridad</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm text-[#8a9aaa]">
              Tus datos de pacientes estan protegidos por Row Level Security (RLS). 
              Nadie mas puede acceder a tu informacion medica.
            </p>
            <div className="flex items-center gap-3 p-3 bg-green-50 rounded-lg">
              <Shield className="h-5 w-5 text-green-600" />
              <div>
                <p className="text-sm font-medium text-green-700">Proteccion activa</p>
                <p className="text-xs text-green-600">RLS habilitado - Datos aislados</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center gap-3">
            <Download className="h-6 w-6 text-[#1E5C8E]" />
            <CardTitle className="text-lg">Exportar Datos</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm text-[#8a9aaa]">
              Exporta todos tus datos medicos en formato CSV. 
              Tienes control total sobre tu informacion.
            </p>
            <Button variant="outline" className="w-full">
              <Download className="h-4 w-4 mr-2" /> Exportar Pacientes (CSV)
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center gap-3">
            <Settings className="h-6 w-6 text-red-500" />
            <CardTitle className="text-lg text-red-500">Cerrar Sesion</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-[#8a9aaa] mb-4">
              Cierra tu sesion de forma segura. Necesitaras tu contrasena para volver a entrar.
            </p>
            <Button variant="destructive" className="w-full" onClick={logout}>
              Cerrar Sesion
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
