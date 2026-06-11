import { useState, useEffect } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { supabase } from '@/lib/supabase'
import { etiquetaRol } from '@/proveedor/lib/permisos'
import { toast } from 'sonner'
import { Loader2, UserPlus, AlertCircle, CheckCircle } from 'lucide-react'

export default function ProveedorRegistroVisitador() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const token = searchParams.get('token')

  const [validando, setValidando] = useState(true)
  const [invitacion, setInvitacion] = useState<any>(null)
  const [error, setError] = useState<string | null>(null)

  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [registrando, setRegistrando] = useState(false)
  const [registrado, setRegistrado] = useState(false)

  // Validar token al cargar
  useEffect(() => {
    if (!token) {
      setError('No se proporcionó un token de invitación. Solicita una nueva invitación al administrador de tu empresa.')
      setValidando(false)
      return
    }

    const validar = async () => {
      try {
        const { data, error } = await supabase.functions.invoke('validar-invitacion', {
          body: { token },
        })

        if (error || data?.error) {
          setError(data?.error || 'Invitación no válida o expirada. Solicita una nueva invitación.')
        } else {
          setInvitacion(data)
        }
      } catch (err) {
        setError('Error al validar la invitación. Intenta de nuevo más tarde.')
      }
      setValidando(false)
    }

    validar()
  }, [token])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!invitacion) return

    if (password !== confirmPassword) {
      toast.error('Las contraseñas no coinciden')
      return
    }
    if (password.length < 6) {
      toast.error('La contraseña debe tener al menos 6 caracteres')
      return
    }

    setRegistrando(true)

    try {
      // 1. Crear usuario en Supabase Auth
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: invitacion.email,
        password,
      })

      if (authError) {
        const msg = authError.message || ''
        if (msg.toLowerCase().includes('already registered') || msg.toLowerCase().includes('already exists')) {
          toast.error('Este correo ya está registrado. Inicia sesión o usa otro email.')
        } else {
          toast.error(authError.message)
        }
        setRegistrando(false)
        return
      }

      if (!authData.user) {
        toast.error('No se pudo crear el usuario. Intenta de nuevo.')
        setRegistrando(false)
        return
      }

      // 2. Completar registro como visitador usando la RPC
      const { data: empresaId, error: rpcError } = await supabase.rpc('registrar_visitador_desde_invitacion', {
        p_token: token,
        p_user_id: authData.user.id,
        p_email: invitacion.email,
        p_nombre_completo: invitacion.nombre_completo,
        p_telefono: invitacion.telefono,
      })

      if (rpcError) {
        console.error('Error RPC registrar_visitador_desde_invitacion:', rpcError)
        // Si la RPC falló, intentar limpiar
        await supabase.auth.signOut()
        toast.error(`Error al completar el registro: ${rpcError.message}`)
        setRegistrando(false)
        return
      }

      setRegistrado(true)
      toast.success('¡Registro completado! Ahora puedes iniciar sesión.')
    } catch (err: any) {
      console.error('Error en registro:', err)
      toast.error(err.message || 'Error al registrarse')
    }

    setRegistrando(false)
  }

  if (validando) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-sky-50 to-indigo-50 flex items-center justify-center p-4">
        <Card className="w-full max-w-md shadow-xl">
          <CardContent className="p-8 text-center">
            <Loader2 className="mx-auto h-8 w-8 animate-spin text-primary mb-4" />
            <p className="text-muted-foreground">Validando tu invitación...</p>
          </CardContent>
        </Card>
      </div>
    )
  }

  if (error) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-sky-50 to-indigo-50 flex items-center justify-center p-4">
        <Card className="w-full max-w-md shadow-xl">
          <CardContent className="p-8 text-center space-y-4">
            <AlertCircle className="mx-auto h-12 w-12 text-destructive" />
            <h2 className="text-xl font-semibold">Invitación no válida</h2>
            <p className="text-muted-foreground">{error}</p>
            <Link to="/proveedor/login">
              <Button variant="outline" className="w-full">Ir al login</Button>
            </Link>
          </CardContent>
        </Card>
      </div>
    )
  }

  if (registrado) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-sky-50 to-indigo-50 flex items-center justify-center p-4">
        <Card className="w-full max-w-md shadow-xl">
          <CardContent className="p-8 text-center space-y-4">
            <CheckCircle className="mx-auto h-12 w-12 text-green-600" />
            <h2 className="text-xl font-semibold">¡Registro exitoso!</h2>
            <p className="text-muted-foreground">
              Tu cuenta de visitador médico ha sido creada. Ya puedes iniciar sesión.
            </p>
            <Button className="w-full bg-[#1E5C8E] hover:bg-[#164a70]" onClick={() => navigate('/proveedor/login')}>
              Iniciar sesión
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-sky-50 to-indigo-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-md shadow-xl">
        <CardHeader className="text-center">
          <div className="mx-auto w-12 h-12 rounded-xl bg-[#1E5C8E] flex items-center justify-center mb-4">
            <UserPlus className="h-6 w-6 text-white" />
          </div>
          <CardTitle className="text-xl">Completa tu registro</CardTitle>
          <p className="text-sm text-muted-foreground">
            Has sido invitado como <strong>{invitacion?.rol ? etiquetaRol(invitacion.rol) : 'Visitador Médico'}</strong> en <strong>{invitacion?.empresa_nombre}</strong>
          </p>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Datos pre-llenos de la invitación */}
            <div className="rounded-lg bg-muted/50 p-3 space-y-2">
              <p className="text-sm font-medium text-muted-foreground">Datos de la invitación</p>
              <div>
                <p className="text-xs text-muted-foreground">Nombre completo</p>
                <p className="font-medium">{invitacion?.nombre_completo}</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Correo electrónico</p>
                <p className="font-medium">{invitacion?.email}</p>
              </div>
              {invitacion?.telefono && (
                <div>
                  <p className="text-xs text-muted-foreground">Teléfono</p>
                  <p className="font-medium">{invitacion.telefono}</p>
                </div>
              )}
            </div>

            <div className="space-y-2">
              <Label htmlFor="password">Crea tu contraseña *</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Mínimo 6 caracteres"
                required
                autoFocus
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="confirmPassword">Confirma tu contraseña *</Label>
              <Input
                id="confirmPassword"
                type="password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                placeholder="Repite la contraseña"
                required
              />
            </div>
            <Button type="submit" className="w-full bg-[#1E5C8E] hover:bg-[#164a70]" disabled={registrando}>
              {registrando ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Crear mi cuenta
            </Button>
          </form>

          <div className="mt-6 text-center text-sm">
            <span className="text-muted-foreground">¿Ya tienes cuenta? </span>
            <Link to="/proveedor/login" className="text-[#1E5C8E] hover:underline font-medium">
              Inicia sesión
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
