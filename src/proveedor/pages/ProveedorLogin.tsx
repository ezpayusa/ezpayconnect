import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Building2, Loader2 } from 'lucide-react'
import { toast } from 'sonner'

export default function ProveedorLogin() {
  const navigate = useNavigate()
  const { login } = useProveedorAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    const { error } = await login(email, password)
    setLoading(false)
    if (error) {
      toast.error('Error al iniciar sesión', { description: error.message })
    } else {
      toast.success('Bienvenido')
      navigate('/proveedor/dashboard')
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-sky-50 to-indigo-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-md shadow-xl">
        <CardHeader className="text-center">
          <div className="mx-auto w-12 h-12 rounded-xl bg-[#1E5C8E] flex items-center justify-center mb-4">
            <Building2 className="h-6 w-6 text-white" />
          </div>
          <CardTitle className="text-xl">Portal Proveedores</CardTitle>
          <p className="text-sm text-muted-foreground">Inicia sesión con tu cuenta de empresa</p>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Correo electrónico</Label>
              <Input
                id="email"
                type="email"
                placeholder="contacto@empresa.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Contraseña</Label>
              <Input
                id="password"
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
            <Button type="submit" className="w-full bg-[#1E5C8E] hover:bg-[#164a70]" disabled={loading}>
              {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Iniciar sesión
            </Button>
          </form>
          <div className="mt-6 text-center text-sm">
            <span className="text-muted-foreground">¿No tienes cuenta? </span>
            <Link to="/proveedor/registro" className="text-[#1E5C8E] hover:underline font-medium">
              Registra tu empresa
            </Link>
          </div>
          <div className="mt-4 text-center text-xs text-muted-foreground">
            <Link to="/login" className="hover:underline">← Volver al portal médico</Link>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
