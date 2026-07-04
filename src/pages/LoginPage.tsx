import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { usePaisesRegistro } from '@/hooks/usePaisesRegistro'
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
  const [paisId, setPaisId] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const { paises } = usePaisesRegistro()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError('')

    if (isRegister) {
      // Mapeo a roles del catálogo (perfiles.rol tiene FK → roles_catalogo):
      // admin→admin_clinica; asistente/enfermera/contador→gerente; medico/gerente igual.
      const ROL_CATALOGO: Record<string, string> = {
        admin: 'admin_clinica', asistente: 'gerente', enfermera: 'gerente',
        contador: 'gerente', medico: 'medico', gerente: 'gerente',
      }
      const { error } = await register(email, password, nombre, ROL_CATALOGO[rol] ?? 'medico', paisId)
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
            .select('rol, pais_id')
            .eq('id', user.id)
            .single()
          const adminRoles = ['super_admin', 'admin_pais']  // admins de sistema del catálogo (admin_pais reintroducido mig 216)
          if (profile?.rol === 'medico') {
            navigate('/medico')
          } else if (profile?.rol && adminRoles.includes(profile.rol)) {
            // admin_pais entra directo al dashboard de su país; super_admin al índice global.
            // pais_id null es imposible (CHECK mig 216); defensivo → /admin-ezpay y AdminRoute decide.
            if (profile.rol === 'admin_pais' && profile.pais_id) {
              navigate(`/admin-ezpay/pais/${profile.pais_id}`)
            } else {
              navigate('/admin-ezpay')
            }
          } else if (profile?.rol === 'secretaria') {
            // La secretaria solo opera el calendario → entra directo (su única superficie).
            navigate('/clinica/calendario')
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
    setPaisId('')
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
                    <Label>País</Label>
                    <Select value={paisId} onValueChange={setPaisId}>
                      <SelectTrigger>
                        <SelectValue placeholder="Selecciona tu país" />
                      </SelectTrigger>
                      <SelectContent>
                        {paises.map((p) => (
                          <SelectItem key={p.id} value={p.id}>
                            {p.nombre} ({p.codigo})
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
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