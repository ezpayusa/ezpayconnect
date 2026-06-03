import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { User, Mail, Phone, Calendar, AlertTriangle } from 'lucide-react'

export default function WebAppPerfil() {
  const { perfil } = useWebAppAuth()

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Mi Perfil</h1>
        <p className="text-slate-500 mt-1">Tus datos personales y médicos</p>
      </div>

      <Card className="bg-white border-slate-100">
        <CardContent className="p-6">
          <div className="flex items-center gap-4 mb-6">
            <div className="w-16 h-16 rounded-full bg-gradient-to-br from-sky-500 to-indigo-500 flex items-center justify-center text-white font-bold text-xl">
              {perfil ? `${perfil.nombre?.charAt(0)}${perfil.apellido?.charAt(0)}` : '?'}
            </div>
            <div>
              <h2 className="text-lg font-semibold text-slate-800">
                {perfil ? `${perfil.nombre} ${perfil.apellido}` : 'Paciente'}
              </h2>
              <p className="text-sm text-slate-500">Paciente</p>
            </div>
          </div>

          <div className="space-y-4">
            <div className="flex items-center gap-3 text-slate-600">
              <Mail className="h-4 w-4 text-slate-400" />
              <span>{perfil?.email || 'No registrado'}</span>
            </div>
            <div className="flex items-center gap-3 text-slate-600">
              <Phone className="h-4 w-4 text-slate-400" />
              <span>{perfil?.telefono || 'No registrado'}</span>
            </div>
            <div className="flex items-center gap-3 text-slate-600">
              <Calendar className="h-4 w-4 text-slate-400" />
              <span>{perfil?.fecha_nacimiento ? new Date(perfil.fecha_nacimiento).toLocaleDateString('es-GT') : 'No registrada'}</span>
            </div>
            {perfil?.alergias && (
              <div className="flex items-start gap-3 text-amber-600 bg-amber-50 p-3 rounded-lg">
                <AlertTriangle className="h-4 w-4 mt-0.5" />
                <div>
                  <p className="font-medium text-sm">Alergias</p>
                  <p className="text-sm">{perfil.alergias}</p>
                </div>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
