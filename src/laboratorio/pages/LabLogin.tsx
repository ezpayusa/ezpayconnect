import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { supabase } from '@/lib/supabase'
import { aceptarInvitacionPendiente } from '@/lib/invitacionProveedor'
import { FlaskConical, Loader2 } from 'lucide-react'
import { toast } from 'sonner'

export default function LabLogin() {
  const navigate = useNavigate()
  const { login } = useProveedorAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    const { error } = await login(email, password)
    if (error) {
      setLoading(false)
      toast.error('Error al iniciar sesión', { description: error.message })
      return
    }
    await aceptarInvitacionPendiente()
    // Enrutar según el tipo de empresa
    const { data: { user } } = await supabase.auth.getUser()
    const { data: cuenta } = await supabase
      .from('cuentas_proveedor')
      .select('empresa:empresa_id(tipo)')
      .eq('id', user?.id)
      .maybeSingle()
    setLoading(false)
    const tipo = (cuenta as any)?.empresa?.tipo
    toast.success('Bienvenido')
    if (tipo === 'laboratorio_clinico') {
      navigate('/laboratorio/dashboard')
    } else if (tipo === 'farmacia') {
      navigate('/farmacia/dashboard')
    } else {
      navigate('/proveedor/dashboard')
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-emerald-50 to-teal-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-md shadow-xl">
        <CardHeader className="text-center">
          <div className="mx-auto w-12 h-12 rounded-xl bg-[#0E7C6B] flex items-center justify-center mb-4">
            <FlaskConical className="h-6 w-6 text-white" />
          </div>
          <CardTitle className="text-xl">Laboratorio Clínico</CardTitle>
          <p className="text-sm text-muted-foreground">Inicia sesión con tu cuenta de laboratorio</p>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Correo electrónico</Label>
              <Input id="email" type="email" placeholder="contacto@laboratorio.com"
                value={email} onChange={(e) => setEmail(e.target.value)} required />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Contraseña</Label>
              <Input id="password" type="password" placeholder="••••••••"
                value={password} onChange={(e) => setPassword(e.target.value)} required />
            </div>
            <Button type="submit" className="w-full bg-[#0E7C6B] hover:bg-[#0a5e51]" disabled={loading}>
              {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Iniciar sesión
            </Button>
          </form>
          <div className="mt-3 text-center text-sm">
            <Link to="/recuperar-password" className="text-[#0E7C6B] hover:underline">¿Olvidaste tu contraseña?</Link>
          </div>
          <div className="mt-4 text-center text-sm">
            <span className="text-muted-foreground">¿No tienes cuenta? </span>
            <Link to="/laboratorio/registro" className="text-[#0E7C6B] hover:underline font-medium">
              Registra tu laboratorio
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
