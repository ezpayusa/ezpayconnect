import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { supabase } from '@/lib/supabase'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Stethoscope, Loader2, Shield, User, Headphones, Briefcase, Calculator } from 'lucide-react'

export default function LoginPage() {
  const navigate = useNavigate()
  const { login, register } = useAuth()
  const [isRegister, setIsRegister] = useState(false)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [nombre, setNombre] = useState('')
  const [rol, setRol] = useState('medico')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError('')

    if (isRegister) {
      const { error } = await register(email, password, nombre, rol)
      if (error) setError(error.message)
      else {
        setIsRegister(false)
        setEmail('')
        setPassword('')
        setNombre('')
        setRol('medico')
      }
    } else {
      const { error } = await login(email, password)
      if (error) {
        setError(error.message)
      } else {
        // Verificar rol para redirigir al panel correcto
        const { data: { user } } = await supabase.auth.getUser()
        if (user) {
          const { data: profile } = await supabase
            .from('perfiles')
            .select('rol')
            .eq('id', user.id)
            .single()
          const adminRoles = ['super_admin', 'admin_pais', 'admin_finanzas', 'admin_soporte', 'admin_ventas']
          if (profile?.rol && adminRoles.includes(profile.rol)) {
            navigate('/admin-ezpay')
          } else {
            navigate('/dashboard')
          }
        } else {
          navigate('/dashboard')
        }
      }
    }
    setLoading(false)
  }

  const toggleMode = () => {
    setIsRegister(!isRegister)
    setError('')
    setEmail('')
    setPassword('')
    setNombre('')
    setRol('medico')
  }

  const roles = [
    { value: 'admin', label: 'Administrador', icon: Shield, color: 'text-red-600', desc: 'Control total del sistema' },
    { value: 'medico', label: 'Médico', icon: Stethoscope, color: 'text-[#1E5C8E]', desc: 'Atención médica y recetas' },
    { value: 'asistente', label: 'Asistente / Recepcionista', icon: Headphones, color: 'text-green-600', desc: 'Agenda citas y atención al paciente' },
    { value: 'enfermera', label: 'Enfermera', icon: User, color: 'text-pink-600', desc: 'Asistencia médica y signos vitales' },
    { value: 'contador', label: 'Contador', icon: Calculator, color: 'text-purple-600', desc: 'Facturación y reportes financieros' },
    { value: 'gerente', label: 'Gerente de Clínica', icon: Briefcase, color: 'text-orange-600', desc: 'Gestión operativa del consultorio' },
  ]

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-[#1a2a3a] to-[#1E5C8E]">
      <div className="w-full max-w-md p-4">
        <div className="flex justify-center mb-8">
          <div className="flex items-center gap-3">
            <Stethoscope className="h-12 w-12 text-white" />
            <div>
              <h1 className="text-3xl font-bold text-white">EzPayConnect</h1>
              <p className="text-[#B8D0E0]">Software Médico</p>
            </div>
          </div>
        </div>

        <Card className="border-0 shadow-2xl">
          <CardHeader className="space-y-1">
            <CardTitle className="text-2xl text-center">
              {isRegister ? 'Crear Cuenta' : 'Iniciar Sesión'}
            </CardTitle>
            <CardDescription className="text-center">
              {isRegister
                ? 'Regístrate para empezar a usar EzPayConnect'
                : 'Ingresa tus credenciales para continuar'}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-4">
              {isRegister && (
                <>
                  <div className="space-y-2">
                    <Label htmlFor="nombre">Nombre Completo</Label>
                    <Input
                      id="nombre"
                      value={nombre}
                      onChange={(e) => setNombre(e.target.value)}
                      placeholder="Dr. Juan Pérez"
                      required
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="rol">Tipo de Usuario</Label>
                    <Select value={rol} onValueChange={setRol}>
                      <SelectTrigger>
                        <SelectValue placeholder="Seleccionar rol" />
                      </SelectTrigger>
                      <SelectContent>
                        {roles.map((r) => (
                          <SelectItem key={r.value} value={r.value}>
                            <div className="flex items-center gap-2">
                              <r.icon className={`h-4 w-4 ${r.color}`} />
                              <div>
                                <p className="font-medium">{r.label}</p>
                                <p className="text-xs text-[#8a9aaa]">{r.desc}</p>
                              </div>
                            </div>
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </>
              )}
              <div className="space-y-2">
                <Label htmlFor="email">Correo Electrónico</Label>
                <Input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="usuario@email.com"
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="password">Contraseña</Label>
                <Input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="******"
                  required
                  minLength={6}
                />
              </div>
              {error && (
                <p className="text-sm text-red-500 bg-red-50 p-2 rounded">{error}</p>
              )}
              <Button type="submit" className="w-full bg-[#1E5C8E] hover:bg-[#3A8ABF]" disabled={loading}>
                {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {isRegister ? 'Registrarse' : 'Iniciar Sesión'}
              </Button>
            </form>

            <p className="text-center mt-4 text-sm text-muted-foreground">
              {isRegister ? '¿Ya tienes cuenta?' : '¿No tienes cuenta?'}{' '}
              <button
                type="button"
                onClick={toggleMode}
                className="text-[#1E5C8E] hover:underline font-medium"
              >
                {isRegister ? 'Inicia Sesión' : 'Regístrate'}
              </button>
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}