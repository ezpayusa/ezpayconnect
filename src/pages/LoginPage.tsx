import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Stethoscope, Loader2 } from 'lucide-react'

export default function LoginPage() {
  const navigate = useNavigate()
  const { login, register } = useAuth()
  const [isRegister, setIsRegister] = useState(false)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [nombre, setNombre] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError('')

    if (isRegister) {
      const { error } = await register(email, password, nombre)
      if (error) setError(error.message)
      else setIsRegister(false)
    } else {
      const { error } = await login(email, password)
      if (error) setError(error.message)
      else navigate('/dashboard')
    }
    setLoading(false)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-[#1a2a3a] to-[#1E5C8E]">
      <div className="w-full max-w-md p-4">
        <div className="flex justify-center mb-8">
          <div className="flex items-center gap-3">
            <Stethoscope className="h-12 w-12 text-white" />
            <div>
              <h1 className="text-3xl font-bold text-white">EzPayConnect</h1>
              <p className="text-[#B8D0E0]">Software Medico</p>
            </div>
          </div>
        </div>

        <Card className="border-0 shadow-2xl">
          <CardHeader className="space-y-1">
            <CardTitle className="text-2xl text-center">
              {isRegister ? 'Crear Cuenta' : 'Iniciar Sesion'}
            </CardTitle>
            <CardDescription className="text-center">
              {isRegister
                ? 'Registrate como medico para empezar'
                : 'Ingresa tus credenciales para continuar'}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-4">
              {isRegister && (
                <div className="space-y-2">
                  <Label htmlFor="nombre">Nombre Completo</Label>
                  <Input
                    id="nombre"
                    value={nombre}
                    onChange={(e) => setNombre(e.target.value)}
                    placeholder="Dr. Juan Perez"
                    required
                  />
                </div>
              )}
              <div className="space-y-2">
                <Label htmlFor="email">Correo Electronico</Label>
                <Input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="doctor@email.com"
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="password">Contrasena</Label>
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
                {isRegister ? 'Registrarse' : 'Iniciar Sesion'}
              </Button>
            </form>

            <p className="text-center mt-4 text-sm text-muted-foreground">
              {isRegister ? 'Ya tienes cuenta?' : 'No tienes cuenta?'}{' '}
              <button
                type="button"
                onClick={() => { setIsRegister(!isRegister); setError('') }}
                className="text-[#1E5C8E] hover:underline font-medium"
              >
                {isRegister ? 'Inicia Sesion' : 'Registrate'}
              </button>
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
