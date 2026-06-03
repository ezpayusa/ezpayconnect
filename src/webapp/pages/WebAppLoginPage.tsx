import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Mail, Lock, Loader2 } from 'lucide-react'
import { toast } from 'sonner'

export default function WebAppLoginPage() {
  const navigate = useNavigate()
  const { login } = useWebAppAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email || !password) {
      toast.error('Ingresa email y contraseña')
      return
    }
    setLoading(true)
    const { error } = await login(email, password)
    if (error) {
      toast.error('Error al iniciar sesión: ' + (error as Error).message)
    } else {
      toast.success('Bienvenido')
      navigate('/paciente/dashboard')
    }
    setLoading(false)
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-sky-50 to-indigo-50 flex items-center justify-center p-4">
      <div className="w-full max-w-md bg-white rounded-2xl shadow-xl p-8 space-y-6">
        <div className="text-center space-y-2">
          <div className="w-16 h-16 mx-auto rounded-2xl bg-gradient-to-br from-sky-500 to-indigo-500 flex items-center justify-center">
            <span className="text-white font-bold text-2xl">E</span>
          </div>
          <h1 className="text-2xl font-bold text-slate-800">EzPayConnect</h1>
          <p className="text-slate-500">Portal del Paciente</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <div className="relative">
              <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
              <Input
                id="email"
                type="email"
                placeholder="tu@email.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="pl-10"
                required
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="password">Contraseña</Label>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
              <Input
                id="password"
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="pl-10"
                required
              />
            </div>
          </div>

          <Button
            type="submit"
            className="w-full bg-gradient-to-r from-sky-500 to-indigo-500 hover:from-sky-600 hover:to-indigo-600"
            disabled={loading}
          >
            {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
            Iniciar Sesión
          </Button>
        </form>

        <p className="text-center text-sm text-slate-500">
          ¿No tienes cuenta?{' '}
          <button
            onClick={() => navigate('/paciente/registro')}
            className="text-sky-600 font-medium hover:underline"
          >
            Regístrate
          </button>
        </p>
      </div>
    </div>
  )
}
