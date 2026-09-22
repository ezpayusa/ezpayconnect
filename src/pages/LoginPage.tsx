import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { supabase } from '@/lib/supabase'
import { rutaHomePorRol } from '@/lib/rutas'
import { enviarReset } from '@/lib/enviarReset'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Stethoscope, Loader2 } from 'lucide-react'

export default function LoginPage() {
  const navigate = useNavigate()
  const { login } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [enviandoReset, setEnviandoReset] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError('')

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
        // Ruteo por rol centralizado en rutaHomePorRol (misma tabla de destinos que antes).
        navigate(rutaHomePorRol(profile))
      } else {
        navigate('/dashboard')
      }
    }
    setLoading(false)
  }

  const handleReset = async () => {
    if (!email.trim()) { toast.error('Ingresá tu correo para restablecer la contraseña'); return }
    setEnviandoReset(true)
    const { error } = await enviarReset(email.trim(), '/dashboard')
    setEnviandoReset(false)
    if (error) { toast.error('No se pudo enviar el enlace', { description: error.message }); return }
    toast.success('Si el correo existe, te enviamos un enlace para restablecer tu contraseña')
  }

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
            <CardTitle className="text-2xl text-center">Iniciar Sesión</CardTitle>
            <CardDescription className="text-center">
              Ingresa tus credenciales para continuar
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-4">
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
                Iniciar Sesión
              </Button>
            </form>

            <div className="mt-4 text-center">
              <button type="button" onClick={handleReset} disabled={enviandoReset}
                className="text-sm text-[#1E5C8E] hover:underline disabled:opacity-50">
                ¿Olvidaste tu contraseña?
              </button>
            </div>

            <p className="text-center mt-4 text-sm text-muted-foreground">
              El acceso a EzPayConnect es por invitación.
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
